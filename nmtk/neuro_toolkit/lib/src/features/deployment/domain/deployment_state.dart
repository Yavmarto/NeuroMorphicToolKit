import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';

part 'deployment_state.freezed.dart';

@freezed
abstract class DeploymentState with _$DeploymentState {
  const factory DeploymentState({
    @Default([]) List<DeploymentTarget> targets,
    DeploymentJob? activeJob,
    @Default(false) bool isReady,
    // Set instead of silently clearing activeJob when the notifier loses
    // contact with a running job (staleness watchdog / repeated poll
    // failures) -- the UI must always show an honest reason rather than
    // falling through to an unrelated stale card.
    String? connectionLostReason,
  }) = _DeploymentState;
}
