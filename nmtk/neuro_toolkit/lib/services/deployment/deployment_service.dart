import 'package:neuro_toolkit/models/backend_deployment.dart';

enum DeploymentPhase {
  queued,
  connecting,
  preflight,
  bootstrappingAccess,
  reconcilingExistingInstall,
  installingPrerequisites,
  uploadingAssets,
  pullingImages,
  startingContainers,
  verifyingSuiteApi,
  verifyingLauncherControl,
  verifyingOptionalCapabilities,
  completed,
  failed,
  cancelled,
}

extension DeploymentPhaseWireName on DeploymentPhase {
  String get wireName => switch (this) {
        DeploymentPhase.queued => 'queued',
        DeploymentPhase.connecting => 'connecting',
        DeploymentPhase.preflight => 'preflight_running',
        DeploymentPhase.bootstrappingAccess => 'bootstrapping_access',
        DeploymentPhase.reconcilingExistingInstall =>
          'reconciling_existing_install',
        DeploymentPhase.installingPrerequisites => 'installing_prerequisites',
        DeploymentPhase.uploadingAssets => 'uploading_assets',
        DeploymentPhase.pullingImages => 'pulling_images',
        DeploymentPhase.startingContainers => 'starting_containers',
        DeploymentPhase.verifyingSuiteApi => 'verifying_suite_api',
        DeploymentPhase.verifyingLauncherControl =>
          'verifying_launcher_control',
        DeploymentPhase.verifyingOptionalCapabilities =>
          'verifying_optional_capabilities',
        DeploymentPhase.completed => 'completed',
        DeploymentPhase.failed => 'failed',
        DeploymentPhase.cancelled => 'cancelled',
      };
}

enum RemoteReinstallMode {
  preserveData,
  factoryReset,
}

/// Ephemeral administrator input for the one-action remote setup flow.
///
/// This type deliberately has no JSON serializer. Administrator credentials
/// must remain in memory only and are replaced with a generated deploy key
/// before a target is persisted.
class RemoteServerSetupRequest {
  const RemoteServerSetupRequest({
    required this.host,
    required this.adminUsername,
    required this.containerEngine,
    this.adminPassword = '',
    this.adminPrivateKey = '',
    this.sshPort = 22,
    this.reinstallMode = RemoteReinstallMode.preserveData,
  });

  final String host;
  final int sshPort;
  final String adminUsername;
  final String adminPassword;
  final String adminPrivateKey;
  final String containerEngine;
  final RemoteReinstallMode reinstallMode;
}

class DeploymentRequest {
  const DeploymentRequest({
    required this.targetType,
    required this.mode,
    required this.displayName,
    this.host = '',
    this.username = '',
    this.sshPort = 22,
    this.authMethod = 'ssh_key',
    this.sshPassword = '',
    this.sshPrivateKey = '',
    this.backendPort = 9000,
    this.namespace = 'nmtk',
    this.context = '',
    this.apiServer = '',
    this.containerEngine = 'docker',
    this.kubeconfig = '',
    this.cleanInstall = false,
  });

  final String targetType;
  final String mode;
  final String displayName;
  final String host;
  final String username;
  final int sshPort;
  final String authMethod;
  final String sshPassword;
  final String sshPrivateKey;
  final int backendPort;
  final String namespace;
  final String context;
  final String apiServer;
  final String containerEngine;
  final String kubeconfig;
  final bool cleanInstall;

  Map<String, dynamic> toPublicJson({required String id}) => {
        'id': id,
        'displayName': displayName,
        'targetType': targetType,
        'mode': mode,
        'authMode': targetType == 'local'
            ? 'none'
            : targetType == 'kubernetes_cluster'
                ? 'kubeconfig'
                : authMethod,
        'host': host,
        'username': username,
        'sshPort': sshPort,
        'backendPort': backendPort,
        'namespace': namespace,
        'context': context,
        'apiServer': apiServer,
        'containerEngine': containerEngine,
      };

  Map<String, dynamic> toSecretJson() => {
        if (sshPassword.isNotEmpty) 'sshPassword': sshPassword,
        if (sshPrivateKey.isNotEmpty) 'sshPrivateKey': sshPrivateKey,
        if (kubeconfig.isNotEmpty) 'kubeconfig': kubeconfig,
      };
}

class DeploymentSnapshot {
  const DeploymentSnapshot({
    this.targets = const [],
    this.activeJob,
    this.isReady = false,
  });

  final List<DeploymentTarget> targets;
  final DeploymentJob? activeJob;
  final bool isReady;
}

abstract class DeploymentService {
  Future<DeploymentSnapshot> load();

  Future<DeploymentPreflightResult> preflight(DeploymentRequest request);

  Future<RemoteUserBootstrapResult> bootstrapRemoteUser({
    required String host,
    required int sshPort,
    required String rootUsername,
    required String rootPassword,
    required String rootPrivateKey,
    required String containerEngine,
  });

  Future<DeploymentJob> setupRemoteServer(
    RemoteServerSetupRequest request,
  ) {
    throw UnsupportedError('One-action remote setup is not supported.');
  }

  Future<DeploymentJob> deploy(DeploymentRequest request);

  Future<DeploymentJob> fetchJob(String jobId);

  Future<DeploymentJob> cancelJob(String jobId);

  Future<DeploymentJob?> retryJob(String jobId);

  /// Restarts just the Jupyter container for [targetId], without touching
  /// any other service — unlike [retryJob], which reruns the entire
  /// install. Throws if the target is unknown or Jupyter still isn't
  /// healthy afterwards.
  Future<void> retryJupyter(String targetId);
}
