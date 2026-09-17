import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_target_registry_service.dart';

void main() {
  test('Akida visualization request forwards mode, layer, and sample', () async {
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'modelId': 'model-1',
          'mode': 'sample',
          'provenance': 'akida_software_replay',
        }),
        200,
      );
    });
    final service = StudioTargetRegistryService(client: client);

    final result = await service.fetchAkidaModelVisualizationViaLauncher(
      hostId: 'host-1',
      modelId: 'model-1',
      mode: 'sample',
      layerIndex: 2,
      sampleIndex: 42,
    );

    expect(
      capturedRequest.url.toString(),
      'http://127.0.0.1:8090/api/launcher/akida/hosts/host-1/models/model-1/visualization',
    );
    expect(jsonDecode(capturedRequest.body), <String, dynamic>{
      'mode': 'sample',
      'layerIndex': 2,
      'sampleIndex': 42,
    });
    expect(result['provenance'], 'akida_software_replay');
  });

  test(
    'selectAkidaHost persists the launcher-selected host on port 8090',
    () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response('{}', 200);
      });
      final service = StudioTargetRegistryService(client: client);

      await service.selectAkidaHost('host-2');

      expect(
        capturedRequest.url.toString(),
        'http://127.0.0.1:8090/api/launcher/settings',
      );
      expect(capturedRequest.method, 'PUT');
      expect(jsonDecode(capturedRequest.body), {
        'selectedAkidaHostId': 'host-2',
      });
    },
  );

  // The Akida host routes return two different shapes, and a serialized host
  // carries its own `host` key holding the *address string*. Unwrapping
  // `payload['host']` unconditionally threw
  // "type 'String' is not a subtype of type 'Map<String, dynamic>?'" on every
  // route that does not nest — which is what connectivity-test does.
  test('testAkidaHostConnection parses an un-nested host response', () async {
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response(
        jsonEncode({
          'id': 'akida-1',
          'displayName': 'Hp prodesk',
          // The trap: a String under the same key the wrapper shape uses.
          'host': '203.0.113.51',
          'sshPort': 22,
          'username': 'dev',
          'state': 'reachable',
          'lastReadinessMessage': 'SSH reachable',
          'hasPassword': true,
        }),
        200,
      );
    });
    final service = StudioTargetRegistryService(client: client);

    final host = await service.testAkidaHostConnection('akida-1');

    expect(
      capturedRequest.url.toString(),
      'http://127.0.0.1:8090/api/launcher/akida/hosts/akida-1/connectivity-test',
    );
    expect(capturedRequest.method, 'POST');
    expect(host.id, 'akida-1');
    expect(host.host, '203.0.113.51');
    expect(host.lastReadinessMessage, 'SSH reachable');
  });

  test('preflight still unwraps the nested host shape', () async {
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'host': {
            'id': 'akida-1',
            'displayName': 'Hp prodesk',
            'host': '203.0.113.51',
            'state': 'simulator_only',
            'lastReadinessMessage': 'No physical Akida device found.',
          },
          'preflight': {'preflight_status': 'degraded'},
        }),
        200,
      );
    });
    final service = StudioTargetRegistryService(client: client);

    final host = await service.fetchAkidaHostPreflight('akida-1');

    expect(host.host, '203.0.113.51');
    expect(host.lastReadinessMessage, 'No physical Akida device found.');
  });

  test(
    'downloadAkidaPackage sends X-API-Key when credentialRef is present',
    () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response.bytes(const [1, 2, 3], 200);
      });
      final service = StudioTargetRegistryService(client: client);

      final result = await service.downloadAkidaPackage(
        runtimeApiUrl: 'http://192.0.2.9:8002',
        credentialRef: 'token-123',
        mappedNetwork: const {'graph': 'ok'},
        bitWidth: 4,
      );

      expect(result, [1, 2, 3]);
      expect(
        capturedRequest.url.toString(),
        'http://192.0.2.9:8002/api/neurochip/akida/deploy/mapped?bit_width=4',
      );
      expect(capturedRequest.headers['X-API-Key'], 'token-123');
      expect(capturedRequest.headers['Content-Type'], 'application/json');
      expect(jsonDecode(capturedRequest.body), {'graph': 'ok'});
    },
  );

  test(
    'mapAkidaRuntime sends X-API-Key when credentialRef is present',
    () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'sdk_status': 'deployable',
            'sdk_available': true,
            'sdk_issues': <String>[],
            'environment_checks': {
              'host_supported': true,
              'python_supported': true,
              'tensorflow_available': true,
              'cnn2snn_available': true,
              'akida_models_available': true,
              'recommended_runtime': 'remote_sdk',
            },
            'runtime_target': 'hardware',
            'state': 'mapped',
          }),
          200,
        );
      });
      final service = StudioTargetRegistryService(client: client);

      await service.mapAkidaRuntime(
        runtimeApiUrl: 'http://192.0.2.9:8002',
        credentialRef: 'token-123',
        mappedNetwork: const {'graph': 'ok'},
        bitWidth: 4,
      );

      expect(
        capturedRequest.url.toString(),
        'http://192.0.2.9:8002/api/neurochip/akida/map?bit_width=4',
      );
      expect(capturedRequest.headers['X-API-Key'], 'token-123');
      expect(capturedRequest.headers['Content-Type'], 'application/json');
      expect(jsonDecode(capturedRequest.body), {'graph': 'ok'});
    },
  );

  test(
    'runAkidaInference sends X-API-Key when credentialRef is present',
    () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'outputs': [0.0, 1.0],
            'telemetry': {'fps': 123.0},
          }),
          200,
        );
      });
      final service = StudioTargetRegistryService(client: client);

      await service.runAkidaInference(
        runtimeApiUrl: 'http://192.0.2.9:8002',
        credentialRef: 'token-123',
        inputs: const <double>[1, 0, 0],
      );

      expect(
        capturedRequest.url.toString(),
        'http://192.0.2.9:8002/api/neurochip/akida/inference',
      );
      expect(capturedRequest.headers['X-API-Key'], 'token-123');
      expect(capturedRequest.headers['Content-Type'], 'application/json');
      expect(jsonDecode(capturedRequest.body), {
        'inputs': [1.0, 0.0, 0.0],
      });
    },
  );

  test(
    'mapAkidaRuntimeViaLauncher posts to selected host launcher endpoint',
    () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'sdk_status': 'deployable',
            'sdk_available': true,
            'sdk_issues': <String>[],
            'environment_checks': {
              'host_supported': true,
              'python_supported': true,
              'tensorflow_available': true,
              'cnn2snn_available': true,
              'akida_models_available': true,
              'recommended_runtime': 'remote_sdk',
            },
            'runtime_target': 'hardware',
            'state': 'mapped',
          }),
          200,
        );
      });
      final service = StudioTargetRegistryService(client: client);

      await service.mapAkidaRuntimeViaLauncher(
        hostId: 'host-1',
        mappedNetwork: const {'graph': 'ok'},
        bitWidth: 4,
      );

      expect(
        capturedRequest.url.toString(),
        'http://127.0.0.1:8090/api/launcher/akida/hosts/host-1/map?bit_width=4',
      );
      expect(capturedRequest.headers['Content-Type'], 'application/json');
      expect(jsonDecode(capturedRequest.body), {'graph': 'ok'});
    },
  );

  test(
    'runAkidaInferenceViaLauncher posts to selected host launcher endpoint',
    () async {
      late http.Request capturedRequest;
      final client = MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({
            'outputs': [0.0, 1.0],
            'telemetry': {'fps': 123.0},
            'execution_time_us': 4.2,
            'runtime_target': 'hardware',
          }),
          200,
        );
      });
      final service = StudioTargetRegistryService(client: client);

      await service.runAkidaInferenceViaLauncher(
        hostId: 'host-1',
        inputs: const <double>[1, 0, 0],
      );

      expect(
        capturedRequest.url.toString(),
        'http://127.0.0.1:8090/api/launcher/akida/hosts/host-1/run',
      );
      expect(capturedRequest.headers['Content-Type'], 'application/json');
      expect(jsonDecode(capturedRequest.body), {
        'inputs': [1.0, 0.0, 0.0],
      });
    },
  );

  test(
    'Akida model bundle operations use selected launcher host paths',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'jobId': 'job-1',
              'bundleSha256': 'abc',
              'stage': 'completed',
              'progress': 100,
              'message': 'Done',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/inference')) {
          return http.Response(
            jsonEncode(<String, dynamic>{'prediction': 7}),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{'jobId': 'job-1'}),
          202,
        );
      });
      final service = StudioTargetRegistryService(client: client);

      await service.submitAkidaModelJobViaLauncher(
        hostId: 'host-1',
        filename: 'mnist.akida-bundle.zip',
        bundleBase64: 'UEs=',
        sha256: 'abc',
      );
      await service.fetchAkidaModelJobViaLauncher(
        hostId: 'host-1',
        jobId: 'job-1',
      );
      await service.runAkidaModelInferenceViaLauncher(
        hostId: 'host-1',
        modelId: 'model-1',
        sampleIndex: 42,
      );

      expect(requests.map((request) => request.url.path), <String>[
        '/api/launcher/akida/hosts/host-1/model-jobs',
        '/api/launcher/akida/hosts/host-1/model-jobs/job-1',
        '/api/launcher/akida/hosts/host-1/models/model-1/inference',
      ]);
      expect(jsonDecode(requests.first.body), <String, dynamic>{
        'filename': 'mnist.akida-bundle.zip',
        'bundleBase64': 'UEs=',
        'sha256': 'abc',
        'requirePhysicalHardware': true,
      });
      expect(jsonDecode(requests.last.body), <String, dynamic>{
        'sampleIndex': 42,
      });
    },
  );

  test(
    'Akida runtime update operations use suite launcher port 8090',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(<String, dynamic>{
            'jobId': 'runtime-job',
            'hostId': 'host-1',
            'artifactVersion': '0.6.0',
            'artifactSha256': 'abc',
            'stage': request.method == 'POST' ? 'queued' : 'completed',
            'progress': request.method == 'POST' ? 0 : 100,
            'message': 'Ready',
            'status': request.method == 'POST' ? 'queued' : 'completed',
            'installedVersion': '0.6.0',
          }),
          request.method == 'POST' ? 202 : 200,
        );
      });
      final service = StudioTargetRegistryService(client: client);

      final created = await service.startAkidaRuntimeUpdate('host-1');
      final completed = await service.fetchAkidaRuntimeUpdate(
        hostId: 'host-1',
        jobId: created.jobId,
      );

      expect(completed.isCompleted, isTrue);
      expect(requests.map((request) => request.url.port), everyElement(8090));
      expect(requests.map((request) => request.url.path), <String>[
        '/api/launcher/akida/hosts/host-1/runtime-update-jobs',
        '/api/launcher/akida/hosts/host-1/runtime-update-jobs/runtime-job',
      ]);
    },
  );
}
