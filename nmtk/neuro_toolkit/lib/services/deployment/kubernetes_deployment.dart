import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/services/deployment/deployment_persistence.dart';
import 'package:neuro_toolkit/services/deployment/deployment_service.dart';
import 'package:yaml/yaml.dart';

typedef KubernetesProgress =
    Future<void> Function(
      DeploymentPhase phase,
      double percent,
      String message,
    );

class KubernetesDeploymentService {
  const KubernetesDeploymentService();

  Future<KubernetesConfigInfo> inspectKubeconfig(
    DeploymentRequest request,
  ) async {
    final credentials = await _credentials(request);
    return KubernetesConfigInfo(
      server: credentials.server,
      usesBearerToken: credentials.token?.isNotEmpty ?? false,
      usesClientCertificate:
          credentials.clientCertificate != null &&
          credentials.clientKey != null,
    );
  }

  Future<DeploymentPreflightResult> preflight(DeploymentRequest request) async {
    try {
      final credentials = await _credentials(request);
      final client = _KubernetesClient(credentials);
      try {
        await client.get('/version');
      } finally {
        client.close();
      }
      return const DeploymentPreflightResult(
        status: 'ok',
        message: 'Kubernetes credentials and API access are ready.',
        blockingFindings: [],
        degradedFindings: [],
        suggestedRecovery: 'No recovery action needed.',
      );
    } catch (error) {
      final message = _friendlyError(error);
      return DeploymentPreflightResult(
        status: 'failed',
        message: 'preflight failed: $message',
        blockingFindings: ['preflight failed: $message'],
        degradedFindings: const [],
        suggestedRecovery: message,
      );
    }
  }

  Future<String> deploy(
    DeploymentRequest request, {
    required KubernetesProgress onProgress,
  }) async {
    final credentials = await _credentials(request);
    final client = _KubernetesClient(credentials);
    final namespace = request.namespace.trim().isEmpty
        ? 'nmtk'
        : request.namespace.trim();
    try {
      await onProgress(
        DeploymentPhase.preflight,
        20,
        'Validating Kubernetes access',
      );
      await client.get('/version');

      await onProgress(
        DeploymentPhase.uploadingAssets,
        40,
        'Applying Kubernetes resources',
      );
      await client.upsert(
        collectionPath: '/api/v1/namespaces',
        name: namespace,
        body: _namespace(namespace),
      );
      for (final resource in _resources(namespace)) {
        await client.upsert(
          collectionPath: resource.collectionPath,
          name: resource.name,
          body: resource.body,
        );
      }

      await onProgress(
        DeploymentPhase.startingContainers,
        70,
        'Waiting for Kubernetes rollout',
      );
      await _waitForDeployment(client, namespace, 'nmtk-suite-api');
      await _waitForDeployment(client, namespace, 'nmtk-launcher-control');

      await onProgress(
        DeploymentPhase.verifyingLauncherControl,
        92,
        'Resolving the public launcher endpoint',
      );
      return request.apiServer.trim().isNotEmpty
          ? Uri.parse(request.apiServer).host
          : _waitForExternalHost(client, namespace);
    } finally {
      client.close();
    }
  }

  /// Deploys [request] to the cluster and persists the resulting external
  /// host onto [target], reporting progress through [emit].
  Future<void> deployAndPersist(
    DeploymentJob job,
    DeploymentTarget target,
    DeploymentRequest request, {
    required DeploymentPersistence persistence,
    required Future<void> Function(
      DeploymentJob job,
      DeploymentPhase phase,
      double percent,
      String label,
    )
    emit,
  }) async {
    await emit(job, DeploymentPhase.connecting, 10, 'Connecting to Kubernetes');
    final host = await deploy(
      request,
      onProgress: (phase, percent, message) =>
          emit(job, phase, percent, message),
    );
    await persistence.saveTarget(
      target.copyWith(
        host: host,
        lastReadiness: 'ready',
        updatedAt: DateTime.now(),
      ),
      request,
    );
    await emit(
      job,
      DeploymentPhase.completed,
      100,
      'Kubernetes backend and launcher control are ready',
    );
  }

  Future<_KubeCredentials> _credentials(DeploymentRequest request) async {
    if (request.kubeconfig.trim().isEmpty) {
      throw const FormatException('Import a kubeconfig file first.');
    }
    final document = loadYaml(request.kubeconfig);
    if (document is! YamlMap) {
      throw const FormatException('The selected kubeconfig is not valid YAML.');
    }
    final contexts = _namedItems(document['contexts']);
    final selectedContext = request.context.trim().isNotEmpty
        ? request.context.trim()
        : document['current-context']?.toString() ?? '';
    final context = contexts[selectedContext];
    if (context == null) {
      throw FormatException(
        'Kubeconfig context "$selectedContext" was not found.',
      );
    }
    final contextBody = _stringMap(_stringMap(context)['context']);
    final cluster = _namedItems(document['clusters'])[contextBody['cluster']];
    final user = _namedItems(document['users'])[contextBody['user']];
    if (cluster == null || user == null) {
      throw const FormatException(
        'The kubeconfig context does not reference a valid cluster and user.',
      );
    }
    final clusterBody = _stringMap(_stringMap(cluster)['cluster']);
    final userBody = _stringMap(_stringMap(user)['user']);
    final server = clusterBody['server']?.toString() ?? '';
    if (server.isEmpty) {
      throw const FormatException('The kubeconfig cluster has no API server.');
    }

    var token = userBody['token']?.toString();
    var clientCertificate = _decodeData(
      userBody['client-certificate-data']?.toString(),
    );
    var clientKey = _decodeData(userBody['client-key-data']?.toString());
    final exec = userBody['exec'];
    if (exec is YamlMap || exec is Map<dynamic, dynamic>) {
      if (!_isDesktop) {
        throw UnsupportedError(
          'This kubeconfig uses an external exec login command. Mobile cannot '
          'run that command; export a kubeconfig with a static token or client '
          'certificate and import it instead.',
        );
      }
      final execBody = _stringMap(exec);
      final command = execBody['command']?.toString() ?? '';
      final args = (execBody['args'] as Iterable<dynamic>? ?? const [])
          .map((value) => value.toString())
          .toList(growable: false);
      if (command.isEmpty) {
        throw const FormatException(
          'The kubeconfig exec credential has no command.',
        );
      }
      final result = await Process.run(command, args);
      if (result.exitCode != 0) {
        throw StateError('Kubernetes login command failed: ${result.stderr}');
      }
      final payload = jsonDecode(result.stdout.toString());
      final status = payload is Map<String, dynamic>
          ? payload['status'] as Map<String, dynamic>? ?? const {}
          : const <String, dynamic>{};
      token = status['token'] as String? ?? token;
      clientCertificate =
          _decodeData(status['clientCertificateData'] as String?) ??
          clientCertificate;
      clientKey = _decodeData(status['clientKeyData'] as String?) ?? clientKey;
    }

    return _KubeCredentials(
      server: Uri.parse(server),
      token: token,
      certificateAuthority: _decodeData(
        clusterBody['certificate-authority-data']?.toString(),
      ),
      clientCertificate: clientCertificate,
      clientKey: clientKey,
      insecureSkipTlsVerify:
          clusterBody['insecure-skip-tls-verify']?.toString() == 'true',
    );
  }

  static bool get _isDesktop =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux);

  static Map<String, dynamic> _namedItems(dynamic raw) {
    final result = <String, dynamic>{};
    if (raw is Iterable<dynamic>) {
      for (final item in raw) {
        final body = _stringMap(item);
        final name = body['name']?.toString();
        if (name != null) result[name] = item;
      }
    }
    return result;
  }

  static Map<String, dynamic> _stringMap(dynamic raw) {
    if (raw is! Map<dynamic, dynamic>) return const {};
    return {for (final entry in raw.entries) entry.key.toString(): entry.value};
  }

  static List<int>? _decodeData(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return base64Decode(value);
  }

  static String _friendlyError(Object error) => error.toString().replaceFirst(
    RegExp(r'^(FormatException|StateError): '),
    '',
  );

  static Map<String, dynamic> _namespace(String namespace) => {
    'apiVersion': 'v1',
    'kind': 'Namespace',
    'metadata': {'name': namespace},
  };

  static List<_KubeResource> _resources(String namespace) => [
    _deployment(
      namespace: namespace,
      name: 'nmtk-suite-api',
      image: 'ghcr.io/completed-spoon-6/neuromorphictoolkit/suite-api:latest',
      port: 9000,
      healthPath: '/api/suite/health',
      environment: {
        'PYTHONUNBUFFERED': '1',
        'NEUROSENSE_HW_WORKER_URL': 'http://neurosense-hw-worker:8004',
        'NEUROBENCH_RUNNER_URL': 'http://neurobench-runner-worker:8003',
        'NEUROCHIP_HW_WORKER_URL': 'http://neurochip-hw-worker:8002',
        'NEUROCNL_PHYSICS_WORKER_URL': 'http://neurocnl-physics-worker:8006',
        'NEUROCNL_LAVA_WORKER_URL': 'http://lava-backend:8012',
        'SNN_MLIR_COMPILER_WORKER_URL': 'http://snn-mlir-compiler:8007',
        'JUPYTER_WORKER_URL': 'http://jupyter-server:8008',
      },
    ),
    _service(namespace, 'nmtk-suite-api', 9000, external: true),
    _deployment(
      namespace: namespace,
      name: 'nmtk-launcher-control',
      image:
          'ghcr.io/completed-spoon-6/neuromorphictoolkit/launcher-control:latest',
      port: 8091,
      healthPath: '/health',
      environment: {
        'PYTHONUNBUFFERED': '1',
        'NMTK_STATE_DIR': '/app/state',
        'NMTK_DATA_DIR': '/app/data',
        'NMTK_BACKEND_DEPLOYMENT_READY': '1',
        'NMTK_SUITE_API_URL': 'http://nmtk-suite-api:9000',
      },
    ),
    _service(
      namespace,
      'nmtk-launcher-control',
      8090,
      targetPort: 8091,
      external: true,
    ),
    ..._workerResources(
      namespace,
      name: 'neurosense-hw-worker',
      image:
          'ghcr.io/completed-spoon-6/neuromorphictoolkit/neurosense-hw-worker:latest',
      port: 8004,
    ),
    ..._workerResources(
      namespace,
      name: 'neurobench-runner-worker',
      image:
          'ghcr.io/completed-spoon-6/neuromorphictoolkit/neurobench-runner-worker:latest',
      port: 8003,
    ),
    ..._workerResources(
      namespace,
      name: 'neurochip-hw-worker',
      image:
          'ghcr.io/completed-spoon-6/neuromorphictoolkit/neurochip-hw-worker:latest',
      port: 8002,
    ),
    ..._workerResources(
      namespace,
      name: 'lava-backend',
      image:
          'ghcr.io/completed-spoon-6/neuromorphictoolkit/lava-backend:latest',
      port: 8012,
    ),
    ..._workerResources(
      namespace,
      name: 'neurocnl-physics-worker',
      image:
          'ghcr.io/completed-spoon-6/neuromorphictoolkit/neurocnl-physics-worker:latest',
      port: 8006,
    ),
    ..._workerResources(
      namespace,
      name: 'snn-mlir-compiler',
      image:
          'ghcr.io/completed-spoon-6/neuromorphictoolkit/snn-mlir-compiler:latest',
      port: 8007,
    ),
    ..._workerResources(
      namespace,
      name: 'jupyter-server',
      image:
          'ghcr.io/completed-spoon-6/neuromorphictoolkit/jupyter-server:latest',
      port: 8008,
      healthPath: '/api/status',
    ),
  ];

  static List<_KubeResource> _workerResources(
    String namespace, {
    required String name,
    required String image,
    required int port,
    String healthPath = '/health',
  }) => [
    _deployment(
      namespace: namespace,
      name: name,
      image: image,
      port: port,
      healthPath: healthPath,
      environment: const {'PYTHONUNBUFFERED': '1'},
    ),
    _service(namespace, name, port),
  ];

  static _KubeResource _deployment({
    required String namespace,
    required String name,
    required String image,
    required int port,
    required String healthPath,
    required Map<String, String> environment,
  }) {
    final labels = {'app.kubernetes.io/name': name};
    return _KubeResource(
      collectionPath: '/apis/apps/v1/namespaces/$namespace/deployments',
      name: name,
      body: {
        'apiVersion': 'apps/v1',
        'kind': 'Deployment',
        'metadata': {'name': name, 'namespace': namespace, 'labels': labels},
        'spec': {
          'replicas': 1,
          'selector': {'matchLabels': labels},
          'template': {
            'metadata': {'labels': labels},
            'spec': {
              'containers': [
                {
                  'name': name,
                  'image': image,
                  'ports': [
                    {'containerPort': port},
                  ],
                  'env': [
                    for (final entry in environment.entries)
                      {'name': entry.key, 'value': entry.value},
                  ],
                  'readinessProbe': {
                    'httpGet': {'path': healthPath, 'port': port},
                    'initialDelaySeconds': 5,
                    'periodSeconds': 5,
                  },
                },
              ],
            },
          },
        },
      },
    );
  }

  static _KubeResource _service(
    String namespace,
    String name,
    int port, {
    int? targetPort,
    bool external = false,
  }) {
    return _KubeResource(
      collectionPath: '/api/v1/namespaces/$namespace/services',
      name: name,
      body: {
        'apiVersion': 'v1',
        'kind': 'Service',
        'metadata': {'name': name, 'namespace': namespace},
        'spec': {
          'type': external ? 'LoadBalancer' : 'ClusterIP',
          'selector': {'app.kubernetes.io/name': name},
          'ports': [
            {'name': 'http', 'port': port, 'targetPort': targetPort ?? port},
          ],
        },
      },
    );
  }

  Future<void> _waitForDeployment(
    _KubernetesClient client,
    String namespace,
    String name,
  ) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      final deployment = await client.get(
        '/apis/apps/v1/namespaces/$namespace/deployments/$name',
      );
      final status = deployment['status'] as Map<String, dynamic>? ?? const {};
      if ((status['availableReplicas'] as num? ?? 0).toInt() >= 1) return;
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw StateError('Kubernetes rollout for $name timed out.');
  }

  Future<String> _waitForExternalHost(
    _KubernetesClient client,
    String namespace,
  ) async {
    for (var attempt = 0; attempt < 100; attempt++) {
      final service = await client.get(
        '/api/v1/namespaces/$namespace/services/nmtk-launcher-control',
      );
      final status = service['status'] as Map<String, dynamic>? ?? const {};
      final loadBalancer =
          status['loadBalancer'] as Map<String, dynamic>? ?? const {};
      final ingress = loadBalancer['ingress'] as List<dynamic>? ?? const [];
      if (ingress.isNotEmpty && ingress.first is Map<String, dynamic>) {
        final first = ingress.first as Map<String, dynamic>;
        final host = first['ip']?.toString() ?? first['hostname']?.toString();
        if (host != null && host.isNotEmpty) return host;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    throw StateError(
      'The Kubernetes launcher-control service has no external address. '
      'Configure a LoadBalancer or enter a reachable API endpoint override.',
    );
  }
}

class KubernetesConfigInfo {
  const KubernetesConfigInfo({
    required this.server,
    required this.usesBearerToken,
    required this.usesClientCertificate,
  });

  final Uri server;
  final bool usesBearerToken;
  final bool usesClientCertificate;
}

class _KubeCredentials {
  const _KubeCredentials({
    required this.server,
    this.token,
    this.certificateAuthority,
    this.clientCertificate,
    this.clientKey,
    this.insecureSkipTlsVerify = false,
  });

  final Uri server;
  final String? token;
  final List<int>? certificateAuthority;
  final List<int>? clientCertificate;
  final List<int>? clientKey;
  final bool insecureSkipTlsVerify;
}

class _KubeResource {
  const _KubeResource({
    required this.collectionPath,
    required this.name,
    required this.body,
  });

  final String collectionPath;
  final String name;
  final Map<String, dynamic> body;
}

class _KubernetesClient {
  _KubernetesClient(this.credentials) {
    final context = SecurityContext(
      withTrustedRoots: credentials.certificateAuthority == null,
    );
    final authority = credentials.certificateAuthority;
    if (authority != null) context.setTrustedCertificatesBytes(authority);
    final certificate = credentials.clientCertificate;
    final key = credentials.clientKey;
    if (certificate != null && key != null) {
      context.useCertificateChainBytes(certificate);
      context.usePrivateKeyBytes(key);
    }
    _client = HttpClient(context: context);
    if (credentials.insecureSkipTlsVerify) {
      _client.badCertificateCallback = (_, _, _) => true;
    }
  }

  final _KubeCredentials credentials;
  late final HttpClient _client;

  void close() => _client.close(force: true);

  Future<Map<String, dynamic>> get(String resourcePath) =>
      _request('GET', resourcePath);

  Future<void> upsert({
    required String collectionPath,
    required String name,
    required Map<String, dynamic> body,
  }) async {
    Map<String, dynamic>? existing;
    try {
      existing = await get('$collectionPath/$name');
    } on _KubernetesHttpError catch (error) {
      if (error.statusCode != 404) rethrow;
    }
    if (existing == null) {
      await _request('POST', collectionPath, body: body);
      return;
    }
    final resourceVersion =
        (existing['metadata'] as Map<String, dynamic>?)?['resourceVersion'];
    final next = Map<String, dynamic>.from(body);
    next['metadata'] = {
      ...(body['metadata'] as Map<String, dynamic>),
      'resourceVersion': ?resourceVersion,
    };
    await _request('PUT', '$collectionPath/$name', body: next);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String resourcePath, {
    Map<String, dynamic>? body,
  }) async {
    final uri = credentials.server.resolve(resourcePath);
    final request = await _client.openUrl(method, uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (credentials.token?.isNotEmpty ?? false) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${credentials.token}',
      );
    }
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _KubernetesHttpError(response.statusCode, text);
    }
    if (text.trim().isEmpty) return const {};
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : const {};
  }
}

class _KubernetesHttpError implements Exception {
  const _KubernetesHttpError(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'Kubernetes API error $statusCode: $body';
}
