import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:neuro_toolkit/services/environment_api_service.dart';

part 'environment_state.freezed.dart';

@freezed
abstract class EnvironmentState with _$EnvironmentState {
  const factory EnvironmentState({
    @Default([]) List<EnvironmentInfo> environments,
    @Default(false) bool busy,
    String? activeOperation,
  }) = _EnvironmentState;
}
