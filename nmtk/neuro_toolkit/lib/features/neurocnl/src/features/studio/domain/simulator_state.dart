import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/simulator.dart';

part 'simulator_state.freezed.dart';

@freezed
sealed class SimulatorRunState with _$SimulatorRunState {
  const factory SimulatorRunState.idle() = SimulatorRunIdle;
  const factory SimulatorRunState.loading() = SimulatorRunLoading;
  const factory SimulatorRunState.success(SimulatorRunResult result) =
      SimulatorRunSuccess;
  const factory SimulatorRunState.error(
    String message, {
    @Default([]) List<String> details,
    int? statusCode,
  }) = SimulatorRunError;
}
