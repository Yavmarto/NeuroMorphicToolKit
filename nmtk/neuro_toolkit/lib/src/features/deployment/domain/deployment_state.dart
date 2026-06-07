import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:neuro_toolkit/models/backend_deployment.dart';

part 'deployment_state.freezed.dart';

@freezed
abstract class DeploymentState with _$DeploymentState {
  const factory DeploymentState({
    @Default([]) List<DeploymentTarget> targets,
    DeploymentJob? activeJob,
    @Default(false) bool isReady,
  }) = _DeploymentState;
}
