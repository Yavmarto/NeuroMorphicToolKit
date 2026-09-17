import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/deploy_readiness_result.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/workflow/pipeline_stepper.dart';

/// Horizontal pipeline progress bar showing the state of each step.
///
/// This widget is now a thin wrapper around the shared [NmtkPipelineStepper]
/// from `nmtk_ui_core`.
class PipelineBar extends ConsumerWidget {
  const PipelineBar({
    super.key,
    this.bare = false,
    this.activeStepId,
    this.onStepSelected,
  });

  /// When true, renders only the inner scrollable step row with no container
  /// border — suitable for embedding in a parent toolbar row.
  final bool bare;
  final String? activeStepId;
  final ValueChanged<String>? onStepSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pipeline = ref.watch(pipelineProvider);
    final l10n = AppLocalizations.of(context)!;

    final steps = [
      NmtkPipelineStepData(
        id: 'validation',
        label: l10n.validate,
        status: _mergedParseValidateStatus(pipeline),
        detail: _mergedParseValidateDetail(pipeline),
      ),
      NmtkPipelineStepData(
        id: 'deploy',
        label: l10n.deploy,
        status: _mapStatus(pipeline.deployStepStatus),
        detail: _deployDetailFor(pipeline),
      ),
    ];

    return NmtkPipelineStepper(
      steps: steps,
      selectedStepId: activeStepId,
      onSelected: onStepSelected,
      bare: bare,
    );
  }

  NmtkStepStatus _mapStatus(StepStatus status) {
    return switch (status) {
      StepStatus.idle => NmtkStepStatus.idle,
      StepStatus.running => NmtkStepStatus.running,
      StepStatus.success => NmtkStepStatus.success,
      StepStatus.error => NmtkStepStatus.error,
    };
  }

  NmtkStepStatus _mergedParseValidateStatus(PipelineState pipeline) {
    if (pipeline.parseStatus == StepStatus.error) return NmtkStepStatus.error;
    if (pipeline.parseStatus == StepStatus.running ||
        pipeline.validateStatus == StepStatus.running) {
      return NmtkStepStatus.running;
    }
    if (pipeline.validateStatus == StepStatus.error) {
      return NmtkStepStatus.error;
    }
    if (pipeline.validateStatus == StepStatus.success) {
      return pipeline.validateResult?.overall == true
          ? NmtkStepStatus.success
          : NmtkStepStatus.error;
    }
    if (pipeline.parseStatus == StepStatus.success) {
      return NmtkStepStatus.running;
    }
    return NmtkStepStatus.idle;
  }

  String? _mergedParseValidateDetail(PipelineState pipeline) {
    if (pipeline.validateResult != null) {
      return pipeline.validateResult!.overall ? 'Passed' : 'Failed';
    }
    if (pipeline.parseResult != null) {
      final r = pipeline.parseResult!;
      return r.errors == 0 ? '${r.total} ok' : '${r.errors} err';
    }
    return null;
  }

  /// Detail text for the Deploy step, sourced from the deploy-readiness
  /// check (simulator preflight or hardware codegen preview) with a fallback
  /// to the legacy generate-based detail when no readiness check has run.
  String? _deployDetailFor(PipelineState pipeline) {
    if (pipeline.deployReadinessStatus == StepStatus.running) {
      return 'Checking\u2026';
    }
    final result = pipeline.deployReadinessResult;
    if (result != null) {
      return switch (result) {
        DeployReadinessOk() => 'Ready',
        DeployReadinessUnsupported(level: final level) =>
          level == 'unsupported' ? 'Unsupported nodes' : 'Approximate',
        DeployReadinessError() => 'Readiness check failed',
      };
    }
    if (pipeline.generateResult != null) {
      return 'Ready';
    }
    if (pipeline.validateResult?.overall == true) {
      return 'Available';
    }
    return null;
  }
}
