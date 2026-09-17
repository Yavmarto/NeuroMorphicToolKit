import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';

import 'package:neuro_toolkit/features/neurocnl/services/pipeline_workflow_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/deploy_readiness_result.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/pipeline_state.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_workflow_provider.dart';
export 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/pipeline_state.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/simulator_preflight_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';

part 'pipeline_provider.g.dart';

// State is now imported from '../src/features/studio/domain/pipeline_state.dart'

@riverpod
class PipelineController extends _$PipelineController {
  static const _parseCacheKey = 'cached_parse_result';
  static const _validateCacheKey = 'cached_validate_result';

  /// Tracks which file the current generate/simulate run belongs to.
  String? _runningForFileId;

  /// Stale-request guard for the auto-triggered deploy-readiness check,
  /// mirroring `SimulatorPreflightController._currentKey`.
  String? _deployReadinessKey;

  @override
  PipelineState build() {
    // React to active file switches.
    ref.listen<WorkspaceFile?>(
      workspaceProvider.select((workspace) => workspace.activeFile),
      (previous, next) {
        if (previous?.id == next?.id) return;
        _hydrateFromActiveFile(next);
      },
    );

    // Seed initial state from the active file's cached pipeline state.
    final initialFile = ref.read(workspaceProvider).activeFile;
    final initialCache = initialFile?.pipelineCache;
    final initial = _buildFromCacheOrEmpty(initialFile, initialCache);

    // Also try to restore parse/validate from persistent storage.
    return _mergeStoredResults(initial);
  }

  // ---------------------------------------------------------------------------
  // Initialization helpers
  // ---------------------------------------------------------------------------

  PipelineState _buildFromCacheOrEmpty(
    WorkspaceFile? file,
    WorkspacePipelineCache? cache,
  ) {
    if (file?.pipelineState != null) {
      return file!.pipelineState!;
    }
    if (file != null &&
        cache != null &&
        cache.isValidForContent(file.canonicalDocument?.cnlText ?? '')) {
      return const PipelineState().copyWith(
        generateStatus: StepStatus.success,
        simulateStatus: StepStatus.success,
        generateResult: cache.generateResult,
        simulateResult: cache.simulationResult,
        simulationStartTime: null,
        requestedDuration: null,
      );
    }
    return const PipelineState();
  }

  PipelineState _mergeStoredResults(PipelineState current) {
    final parseJson = ServerConfigService.getString(_parseCacheKey);
    final validateJson = ServerConfigService.getString(_validateCacheKey);

    ParseResult? parseResult;
    ValidationResult? validateResult;

    if (parseJson != null) {
      try {
        parseResult = ParseResult.fromJson(
          jsonDecode(parseJson) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('Failed to parse cached ParseResult: $e');
      }
    }
    if (validateJson != null) {
      try {
        validateResult = ValidationResult.fromJson(
          jsonDecode(validateJson) as Map<String, dynamic>,
        );
      } catch (e) {
        debugPrint('Failed to parse cached ValidationResult: $e');
      }
    }

    if (parseResult == null && validateResult == null) {
      return current;
    }

    // Only apply stored results if the pipeline doesn't already have better data.
    if (current.parseStatus != StepStatus.idle ||
        current.validateStatus != StepStatus.idle) {
      return current;
    }

    return current.copyWith(
      parseResult: parseResult,
      validateResult: validateResult,
      parseStatus: parseResult != null
          ? (parseResult.errors > 0 ? StepStatus.error : StepStatus.success)
          : StepStatus.idle,
      validateStatus: validateResult != null
          ? (validateResult.overall ? StepStatus.success : StepStatus.error)
          : StepStatus.idle,
    );
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  PipelineWorkflowService get _workflow =>
      ref.read(pipelineWorkflowServiceProvider);

  void _hydrateFromActiveFile(WorkspaceFile? file) {
    final pipelineState = file?.pipelineState;
    if (pipelineState != null) {
      state = pipelineState;
      return;
    }
    state = const PipelineState();
    final cache = file?.pipelineCache;
    if (file != null &&
        cache != null &&
        cache.isValidForContent(file.canonicalDocument?.cnlText ?? '')) {
      state = state.copyWith(
        generateStatus: StepStatus.success,
        simulateStatus: StepStatus.success,
        generateResult: cache.generateResult,
        simulateResult: cache.simulationResult,
        simulationStartTime: null,
        requestedDuration: null,
      );
    }
  }

  void _publishState(PipelineState next) {
    state = next;
    ref
        .read(workspaceControllerProvider.notifier)
        .setActiveFilePipelineState(next);
  }

  void _clearPublishedState() {
    _deployReadinessKey = null;
    state = const PipelineState();
    ref
        .read(workspaceControllerProvider.notifier)
        .clearActiveFilePipelineState();
  }

  bool _matchesActiveDocument(String? fileId, int? revision) {
    if (fileId == null || revision == null) return true;
    final activeFile = ref.read(workspaceProvider).activeFile;
    return activeFile?.id == fileId && activeFile?.revision == revision;
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  void hydrateCachedResultsForFile(WorkspaceFile? file) {
    final cache = file?.pipelineCache;
    if (file == null ||
        cache == null ||
        !cache.isValidForContent(file.canonicalDocument?.cnlText ?? '')) {
      _publishState(
        state.copyWith(
          generateStatus: StepStatus.idle,
          simulateStatus: StepStatus.idle,
          generateResult: null,
          simulateResult: null,
          simulationStartTime: null,
          requestedDuration: null,
        ),
      );
      return;
    }
    _publishState(
      state.copyWith(
        generateStatus: StepStatus.success,
        simulateStatus: StepStatus.success,
        generateResult: cache.generateResult,
        simulateResult: cache.simulationResult,
        simulationStartTime: null,
        requestedDuration: null,
      ),
    );
  }

  /// Simulator target identifiers — validate and preflight use these backends.
  static const _simulatorTargets = {
    'lava_sim',
    'snntorch_sim',
    'sc_neurocore_sim',
  };

  /// Run parse + validate automatically when spec text changes.
  Future<void> runParseAndValidate(
    String spec, {
    String? backendOverride,
  }) async {
    if (spec.trim().isEmpty) {
      _clearPublishedState();
      ref.read(simulatorPreflightControllerProvider.notifier).invalidate();
      return;
    }

    final activeFile = ref.read(workspaceProvider).activeFile;
    final runFileId = activeFile?.id;
    final runRevision = activeFile?.revision;

    final selectedTarget = ref.read(workspaceProvider).selectedDeployTarget;
    final bool isSimulator = _simulatorTargets.contains(selectedTarget);
    final String backend =
        backendOverride ?? (isSimulator ? selectedTarget : 'nir');

    // ── Parse ──
    _deployReadinessKey = null;
    state = state.copyWith(
      parseStatus: StepStatus.running,
      validateStatus: StepStatus.idle,
      generateStatus: StepStatus.idle,
      simulateStatus: StepStatus.idle,
      deployReadinessStatus: StepStatus.idle,
      errorMessage: null,
      parseResult: null,
      validateResult: null,
      generateResult: null,
      simulateResult: null,
      deployReadinessResult: null,
      simulationStartTime: null,
      requestedDuration: null,
    );
    try {
      await _workflow.parseAndValidate(
        spec: spec,
        backend: backend,
        shouldContinue: () => _matchesActiveDocument(runFileId, runRevision),
        onParsed: (parseResult) {
          if (!_matchesActiveDocument(runFileId, runRevision)) return;
          _publishState(
            state.copyWith(
              parseStatus: parseResult.errors > 0
                  ? StepStatus.error
                  : StepStatus.success,
              validateStatus: StepStatus.running,
              parseResult: parseResult,
            ),
          );
          ServerConfigService.setString(
            _parseCacheKey,
            jsonEncode(parseResult.toJson()),
          );
        },
        onValidated: (validateResult) {
          if (!_matchesActiveDocument(runFileId, runRevision)) return;
          _publishState(
            state.copyWith(
              validateStatus: validateResult.overall
                  ? StepStatus.success
                  : StepStatus.error,
              validateResult: validateResult,
            ),
          );
          ServerConfigService.setString(
            _validateCacheKey,
            jsonEncode(validateResult.toJson()),
          );
        },
      );
      if (!_matchesActiveDocument(runFileId, runRevision)) return;
      if (state.validateStatus == StepStatus.success) {
        if (isSimulator) {
          unawaited(
            _mirrorSimulatorReadiness(
              spec,
              selectedTarget,
              runFileId,
              runRevision,
            ),
          );
        } else {
          unawaited(
            _runHardwareReadiness(spec, selectedTarget, runFileId, runRevision),
          );
        }
      } else {
        _deployReadinessKey = null;
        _publishState(
          state.copyWith(
            deployReadinessStatus: StepStatus.idle,
            deployReadinessResult: null,
          ),
        );
      }
    } on PipelineWorkflowFailure catch (failure) {
      if (!_matchesActiveDocument(runFileId, runRevision)) return;
      if (failure.stage == PipelineWorkflowStage.parse) {
        _publishState(
          state.copyWith(
            parseStatus: StepStatus.error,
            errorMessage: 'Parse failed: ${failure.cause}',
          ),
        );
        return;
      }
      _deployReadinessKey = null;
      _publishState(
        state.copyWith(
          validateStatus: StepStatus.error,
          errorMessage: 'Validate failed: ${failure.cause}',
          deployReadinessStatus: StepStatus.idle,
          deployReadinessResult: null,
        ),
      );
      if (isSimulator) {
        ref.read(simulatorPreflightControllerProvider.notifier).invalidate();
      }
    }
  }

  /// Run the simulator preflight check and mirror its terminal
  /// `SimulatorPreflightState` into the unified `deployReadiness*` fields.
  Future<void> _mirrorSimulatorReadiness(
    String spec,
    String target,
    String? fileId,
    int? revision,
  ) async {
    final key = 'sim:$target:${spec.hashCode}';
    _deployReadinessKey = key;
    _publishState(state.copyWith(deployReadinessStatus: StepStatus.running));

    final notifier = ref.read(simulatorPreflightControllerProvider.notifier);
    await notifier.runPreflight(spec, target);
    if (!ref.mounted ||
        _deployReadinessKey != key ||
        !_matchesActiveDocument(fileId, revision)) {
      return;
    }

    final preflight = ref.read(simulatorPreflightControllerProvider);
    if (preflight.status == SimulatorPreflightStatus.success) {
      final level = preflight.level;
      final result = (level == 'unsupported' || level == 'approximate')
          ? DeployReadinessResult.unsupported(
              level: level!,
              unsupportedNodes: preflight.unsupportedNodes,
              diagnostics: preflight.diagnostics,
            )
          : const DeployReadinessResult.ok();
      _publishState(
        state.copyWith(
          deployReadinessStatus: StepStatus.success,
          deployReadinessResult: result,
        ),
      );
    } else if (preflight.status == SimulatorPreflightStatus.error) {
      _publishState(
        state.copyWith(
          deployReadinessStatus: StepStatus.error,
          deployReadinessResult: DeployReadinessResult.error(
            message: preflight.errorMessage ?? 'Preflight failed',
          ),
        ),
      );
    }
  }

  /// Hardware/codegen deploy targets have no live preflight endpoint; use
  /// the side-effect-free `/notebook/preview` codegen preview instead.
  Future<void> _runHardwareReadiness(
    String spec,
    String target,
    String? fileId,
    int? revision,
  ) async {
    final key = 'hw:$target:${spec.hashCode}';
    _deployReadinessKey = key;
    _publishState(state.copyWith(deployReadinessStatus: StepStatus.running));

    try {
      final result = await _workflow.previewDeployReadiness(spec, target);
      if (!ref.mounted ||
          _deployReadinessKey != key ||
          !_matchesActiveDocument(fileId, revision)) {
        return;
      }
      if (result.ioError != null) {
        _publishState(
          state.copyWith(
            deployReadinessStatus: StepStatus.error,
            deployReadinessResult: DeployReadinessResult.error(
              message: result.ioError!,
            ),
          ),
        );
        return;
      }
      final level = result.supportLevel;
      final readiness = (level == 'unsupported' || level == 'approximate')
          ? DeployReadinessResult.unsupported(
              level: level!,
              unsupportedNodes: const [],
              diagnostics: result.diagnostics,
            )
          : const DeployReadinessResult.ok();
      _publishState(
        state.copyWith(
          deployReadinessStatus: StepStatus.success,
          deployReadinessResult: readiness,
        ),
      );
    } catch (e) {
      if (!ref.mounted ||
          _deployReadinessKey != key ||
          !_matchesActiveDocument(fileId, revision)) {
        return;
      }
      _publishState(
        state.copyWith(
          deployReadinessStatus: StepStatus.error,
          deployReadinessResult: DeployReadinessResult.error(
            message: 'Deploy readiness check failed: $e',
          ),
        ),
      );
    }
  }

  /// Run generate + compiled preview (on-demand, triggered by user).
  Future<void> runGenerateAndSimulate(
    String spec, {
    double duration = 1.0,
  }) async {
    if (spec.trim().isEmpty) return;

    final fileId = ref.read(workspaceProvider).activeFileId;
    _runningForFileId = fileId;

    // ── Generate ──
    state = state.copyWith(
      generateStatus: StepStatus.running,
      simulateStatus: StepStatus.idle,
      errorMessage: null,
      generateResult: null,
      simulateResult: null,
      simulationStartTime: null,
      requestedDuration: null,
    );
    try {
      await _workflow.generateAndSimulate(
        spec: spec,
        duration: duration,
        onGenerated: (generateResult) {
          _publishState(
            state.copyWith(
              generateStatus: StepStatus.success,
              generateResult: generateResult,
              simulateStatus: StepStatus.running,
              simulationStartTime: DateTime.now(),
              requestedDuration: duration,
            ),
          );
          if (ref.read(workspaceProvider).activeFileId == _runningForFileId) {
            ref
                .read(workspaceControllerProvider.notifier)
                .savePipelineCacheForActiveFile(
                  generateResult: generateResult,
                  simulationResult: null,
                );
          }
        },
        onSimulated: (simulateResult) {
          _publishState(
            state.copyWith(
              simulateStatus: StepStatus.success,
              simulateResult: simulateResult,
            ),
          );
          if (ref.read(workspaceProvider).activeFileId == _runningForFileId) {
            ref
                .read(workspaceControllerProvider.notifier)
                .savePipelineCacheForActiveFile(
                  generateResult: state.generateResult!,
                  simulationResult: simulateResult,
                );
          }
        },
      );
    } on PipelineWorkflowFailure catch (failure) {
      final isGenerateFailure = failure.stage == PipelineWorkflowStage.generate;
      if (isGenerateFailure) {
        _publishState(
          state.copyWith(
            generateStatus: StepStatus.error,
            errorMessage: 'Generate failed: ${failure.cause}',
          ),
        );
      } else {
        _publishState(
          state.copyWith(
            simulateStatus: StepStatus.error,
            errorMessage: 'Simulation failed: ${failure.cause}',
          ),
        );
      }
      if (isGenerateFailure) {
        _runningForFileId = null;
        return;
      }
    }
    _runningForFileId = null;
  }

  /// Abort an in-progress preview run and return to idle.
  void cancelSimulation() {
    if (state.simulateStatus != StepStatus.running &&
        state.generateStatus != StepStatus.running) {
      return;
    }
    _runningForFileId = null;
    _publishState(
      state.copyWith(
        generateStatus: StepStatus.idle,
        simulateStatus: StepStatus.idle,
        simulateResult: null,
        errorMessage: null,
      ),
    );
  }

  /// Reset everything.
  void reset() => _clearPublishedState();
}

/// Backward-compat alias consumed by all existing widgets/providers.
final pipelineProvider = pipelineControllerProvider;
