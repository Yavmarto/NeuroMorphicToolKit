import 'package:neuro_toolkit/features/neurocnl/models/deploy_preview_result.dart';
import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

/// Backend stages used by a Studio pipeline workflow.
enum PipelineWorkflowStage { parse, validate, generate, simulate, readiness }

/// Identifies a failed backend stage without coupling callers to HTTP details.
class PipelineWorkflowFailure implements Exception {
  const PipelineWorkflowFailure({required this.stage, required this.cause});

  final PipelineWorkflowStage stage;
  final Object cause;

  @override
  String toString() => cause.toString();
}

/// API-only Studio pipeline workflow.
///
/// Riverpod controllers provide UI state transitions through callbacks, so this
/// request ordering can be tested without a provider container or widget tree.
class PipelineWorkflowService {
  const PipelineWorkflowService(this._api);

  final ApiClient _api;

  Future<void> parseAndValidate({
    required String spec,
    required String backend,
    required void Function(ParseResult result) onParsed,
    required void Function(ValidationResult result) onValidated,
    bool Function()? shouldContinue,
  }) async {
    final parseResult = await _run(
      PipelineWorkflowStage.parse,
      () => _api.parse(spec),
    );
    onParsed(parseResult);

    if (shouldContinue != null && !shouldContinue()) return;

    final validationResult = await _run(
      PipelineWorkflowStage.validate,
      () => _api.validate(spec, backend: backend),
    );
    onValidated(validationResult);
  }

  Future<void> generateAndSimulate({
    required String spec,
    required double duration,
    required void Function(GenerateResult result) onGenerated,
    required void Function(SimulationResult result) onSimulated,
  }) async {
    final generateResult = await _run(
      PipelineWorkflowStage.generate,
      () => _api.generate(spec),
    );
    onGenerated(generateResult);

    final simulationResult = await _run(
      PipelineWorkflowStage.simulate,
      () => _api.simulate(spec, duration: duration),
    );
    onSimulated(simulationResult);
  }

  Future<DeployPreviewResult> previewDeployReadiness(
    String spec,
    String target,
  ) {
    return _run(
      PipelineWorkflowStage.readiness,
      () => _api.previewDeployTarget(spec, target),
    );
  }

  Future<T> _run<T>(
    PipelineWorkflowStage stage,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } catch (error) {
      throw PipelineWorkflowFailure(stage: stage, cause: error);
    }
  }
}
