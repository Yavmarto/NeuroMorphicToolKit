import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/server/provision/provision_service.dart';

/// Either half of the admin credential a sudo-capable login accepts: a
/// password or a private key, never both populated.
class ProvisionCredential {
  const ProvisionCredential.password(this.password) : privateKey = '';

  const ProvisionCredential.privateKey(this.privateKey) : password = '';

  final String password;
  final String privateKey;
}

/// What the setup form submits to [ProvisionNotifier.provision].
class ProvisionRequest {
  const ProvisionRequest({
    required this.host,
    required this.sudoUser,
    required this.credential,
    required this.engine,
    this.sshPort = 22,
    this.reinstallMode = RemoteReinstallMode.preserveData,
    this.moduleEnvironment = const <String, String>{},
    this.moduleSecrets = const <String, String>{},
  });

  final String host;
  final String sudoUser;
  final ProvisionCredential credential;
  final String engine;
  final int sshPort;
  final RemoteReinstallMode reinstallMode;
  final Map<String, String> moduleEnvironment;
  final Map<String, String> moduleSecrets;
}

/// A plain-English provisioning failure — never a stack trace. [retryable]
/// tells the form whether to offer "Retry" with re-entered credentials.
class ProvisionFailure {
  const ProvisionFailure({required this.cause, this.retryable = true});

  final String cause;
  final bool retryable;
}

/// Backs the one setup form: drives [ProvisionService.run] and exposes its
/// progress as a single flat state, so the form only ever reads one value.
class ProvisionState {
  const ProvisionState({
    this.isRunning = false,
    this.phaseLabel,
    this.progress,
    this.failure,
    this.result,
  });

  final bool isRunning;
  final String? phaseLabel;
  final double? progress;
  final ProvisionFailure? failure;
  final ProvisionResult? result;
}

final provisionServiceProvider = Provider<ProvisionService>(
  (ref) => ProvisionService(),
);

final provisionNotifierProvider =
    NotifierProvider<ProvisionNotifier, ProvisionState>(ProvisionNotifier.new);

class ProvisionNotifier extends Notifier<ProvisionState> {
  String? _activeJobId;

  @override
  ProvisionState build() => const ProvisionState();

  /// Runs (or re-runs) provisioning for [request]. Re-provisioning an
  /// already-set-up server is expected and safe — the underlying script is
  /// idempotent — so this also backs the "Re-provision this server" action
  /// and, on failure, a retry with re-entered credentials.
  Future<void> provision(ProvisionRequest request) async {
    _activeJobId = null;
    state = const ProvisionState(isRunning: true, phaseLabel: 'Connecting…');
    try {
      final result = await ref
          .read(provisionServiceProvider)
          .run(
            host: request.host,
            sshPort: request.sshPort,
            sudoUsername: request.sudoUser,
            sudoPassword: request.credential.password,
            sudoPrivateKey: request.credential.privateKey,
            containerEngine: request.engine,
            reinstallMode: request.reinstallMode,
            moduleEnvironment: request.moduleEnvironment,
            moduleSecrets: request.moduleSecrets,
            onProgress: (job) {
              _activeJobId = job.id;
              state = ProvisionState(
                isRunning: true,
                phaseLabel: job.stageLabel,
                progress: job.percent / 100,
              );
            },
          );
      _activeJobId = null;
      state = ProvisionState(result: result);
    } on RemoteSetupException catch (error) {
      _activeJobId = null;
      state = ProvisionState(
        failure: ProvisionFailure(cause: error.details.recovery),
      );
    } catch (error) {
      _activeJobId = null;
      state = ProvisionState(
        failure: ProvisionFailure(cause: 'Server setup failed: $error'),
      );
    }
  }

  /// Cancels an in-progress provision run, if any.
  void cancel() {
    final jobId = _activeJobId;
    if (jobId == null) return;
    ref.read(provisionServiceProvider).cancelAdministratorSession(jobId);
  }

  void reset() => state = const ProvisionState();
}
