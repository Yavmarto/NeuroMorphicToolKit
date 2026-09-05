import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/models/backend_deployment.dart';
import 'package:neuro_toolkit/features/server/provision/provision_service.dart';

/// Backs the one setup form: drives [ProvisionService.run] and exposes its
/// progress as a simple idle → running → success/failure state, so the form
/// widget only has to render whichever case is current.
sealed class ProvisionState {
  const ProvisionState();
}

class ProvisionIdle extends ProvisionState {
  const ProvisionIdle();
}

class ProvisionRunning extends ProvisionState {
  const ProvisionRunning({required this.jobId, required this.job});

  final String jobId;
  final DeploymentJob job;
}

class ProvisionSuccess extends ProvisionState {
  const ProvisionSuccess(this.result);

  final ProvisionResult result;
}

class ProvisionFailure extends ProvisionState {
  const ProvisionFailure(this.details);

  final DeploymentFailureDetails details;
}

final provisionServiceProvider = Provider<ProvisionService>(
  (ref) => ProvisionService(),
);

final provisionNotifierProvider =
    NotifierProvider<ProvisionNotifier, ProvisionState>(ProvisionNotifier.new);

class ProvisionNotifier extends Notifier<ProvisionState> {
  @override
  ProvisionState build() => const ProvisionIdle();

  /// Runs (or re-runs) provisioning against [host]. Re-provisioning an
  /// already-set-up server is expected and safe — the underlying script is
  /// idempotent — so this is also the "Re-provision this server" action.
  Future<void> provision({
    required String host,
    required int sshPort,
    required String sudoUsername,
    String sudoPassword = '',
    String sudoPrivateKey = '',
    required String containerEngine,
    RemoteReinstallMode reinstallMode = RemoteReinstallMode.preserveData,
  }) async {
    final service = ref.read(provisionServiceProvider);
    try {
      final result = await service.run(
        host: host,
        sshPort: sshPort,
        sudoUsername: sudoUsername,
        sudoPassword: sudoPassword,
        sudoPrivateKey: sudoPrivateKey,
        containerEngine: containerEngine,
        reinstallMode: reinstallMode,
        onProgress: (job) => state = ProvisionRunning(jobId: job.id, job: job),
      );
      state = ProvisionSuccess(result);
    } on RemoteSetupException catch (error) {
      state = ProvisionFailure(error.details);
    } catch (error) {
      state = ProvisionFailure(
        DeploymentFailureDetails(
          code: 'provision_failed',
          phase: 'failed',
          summary: 'Server setup failed',
          recovery: error.toString(),
        ),
      );
    }
  }

  /// Cancels an in-progress provision run, if any.
  void cancel() {
    final current = state;
    if (current is! ProvisionRunning) return;
    ref.read(provisionServiceProvider).cancelAdministratorSession(current.jobId);
  }

  void reset() => state = const ProvisionIdle();
}
