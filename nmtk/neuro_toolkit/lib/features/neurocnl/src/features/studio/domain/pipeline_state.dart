import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/deploy_readiness_result.dart';

part 'pipeline_state.freezed.dart';
part 'pipeline_state.g.dart';

/// Status of each pipeline step.
enum StepStatus { idle, running, success, error }

/// State of the entire pipeline.
@freezed
abstract class PipelineState with _$PipelineState {
  const PipelineState._();

  const factory PipelineState({
    @Default(StepStatus.idle) StepStatus parseStatus,
    @Default(StepStatus.idle) StepStatus validateStatus,
    @Default(StepStatus.idle) StepStatus generateStatus,
    @Default(StepStatus.idle) StepStatus simulateStatus,
    @Default(StepStatus.idle) StepStatus deployReadinessStatus,
    ParseResult? parseResult,
    ValidationResult? validateResult,
    GenerateResult? generateResult,
    SimulationResult? simulateResult,
    DeployReadinessResult? deployReadinessResult,
    String? errorMessage,

    /// When preview generation is running, tracks start time and requested duration.
    DateTime? simulationStartTime,
    double? requestedDuration,
  }) = _PipelineState;

  factory PipelineState.fromJson(Map<String, dynamic> json) =>
      _$PipelineStateFromJson(json);

  /// Unified Deploy step status combining the deploy-readiness check
  /// (simulator preflight or hardware codegen preview) with the legacy
  /// generate-based fallback for when no readiness check has run yet.
  ///
  /// An `unsupported` readiness result with level `'approximate'` still
  /// counts as deployable (matches the pre-existing preflight behavior);
  /// only level `'unsupported'` and `DeployReadinessError` count as failed.
  StepStatus get deployStepStatus {
    if (deployReadinessStatus == StepStatus.running) {
      return StepStatus.running;
    }
    final result = deployReadinessResult;
    if (result != null) {
      return switch (result) {
        DeployReadinessOk() => StepStatus.success,
        DeployReadinessUnsupported(level: final level) =>
          level == 'unsupported' ? StepStatus.error : StepStatus.success,
        DeployReadinessError() => StepStatus.error,
      };
    }
    if (generateStatus == StepStatus.error) return StepStatus.error;
    if (generateStatus == StepStatus.running) return StepStatus.running;
    if (generateResult != null) return StepStatus.success;
    return StepStatus.idle;
  }

  /// True iff validate passed and the unified Deploy step is not in error.
  bool get overallReady {
    if (validateStatus != StepStatus.success ||
        validateResult?.overall != true) {
      return false;
    }
    return deployStepStatus != StepStatus.error;
  }

  /// True iff the deploy-readiness check itself (not the legacy generate
  /// fallback) reported a blocking failure — used by the Validation panel's
  /// Overall banner to name "Deploy readiness" as a failing section.
  bool get deployReadinessFailed {
    final result = deployReadinessResult;
    if (result == null) return false;
    return switch (result) {
      DeployReadinessOk() => false,
      DeployReadinessUnsupported(level: final level) => level == 'unsupported',
      DeployReadinessError() => true,
    };
  }
}
