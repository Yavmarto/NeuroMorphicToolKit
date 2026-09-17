import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_config.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_result_session.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/autosave_status_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart' as canvas_sim;
import 'package:neuro_toolkit/features/neurocnl/providers/native_file_adapter_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/nir_import_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/studio_result_session_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_history_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/training_job_ids_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/picked_save_path_writer.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/workspace_file_io/studio_workspace_file_io_host.dart';

/// Workspace file I/O: debounced local-storage autosave, manual save/save-as,
/// open, and new-file — previously an `extension on _StudioScreenState`,
/// now a standalone controller addressed through [StudioWorkspaceFileIoHost]
/// so it can live in its own library.
class WorkspaceFileIoController {
  WorkspaceFileIoController(this._host);

  final StudioWorkspaceFileIoHost _host;

  /// Debounces the canvas/simulation/training autosave (below) so a
  /// continuous stream of changes — e.g. `SimulationController.currentTime`
  /// ticking during playback — doesn't write to local storage every frame.
  /// 300ms mirrors the debounce already used for similar high-frequency
  /// state in `canvas_provider.dart` and `canonical_doc_provider.dart`.
  static const _canvasAutosaveDebounce = Duration(milliseconds: 300);

  /// Merges the current canvas/simulation/training state into the same
  /// local-storage key the workspace autosave (`WorkspaceController._persist`)
  /// uses, so the Train/Eval pipeline ("eval grid") survives hot restart —
  /// and, when `workspaceFilePath` is set (a `.nmtk` file has been opened or
  /// saved this session), also writes through to that file so it stays in
  /// sync without a manual "Save Workspace" every time.
  void scheduleCanvasAutosave() {
    // Reported as "saving" from the moment a change is detected (not just
    // once the debounce timer fires below) so the toolbar indicator gives
    // instant feedback that an edit is pending a write. Only mark the start
    // of a *new* pending write — further changes that land while one is
    // already pending just extend the debounce (cancel + reschedule below)
    // without an extra markSaveStarted(), otherwise every keystroke would
    // leak an in-flight count that never gets decremented back to zero.
    final alreadyPending = _host.canvasAutosaveTimer?.isActive ?? false;
    if (!alreadyPending) {
      _host.ref.read(autosaveStatusProvider.notifier).markSaveStarted();
    }
    _host.canvasAutosaveTimer?.cancel();
    _host.canvasAutosaveTimer = Timer(_canvasAutosaveDebounce, () async {
      if (!_host.mounted) {
        return;
      }
      // Captured synchronously, before any `await` — `mergeJsonString` may
      // queue this write behind another in-flight merge for the same key,
      // and by the time our callback actually runs the screen could already
      // be disposed; reading `ref`/rebuilding this inside that deferred
      // callback would then throw or read stale providers. Snapshot it now.
      final payload = {
        ..._host.ref.read(workspaceProvider.notifier).buildRestorePayload(),
        'canvas': _buildCanvasSection(),
        if (_host.ref.read(studioResultSessionProvider).persistableSnapshot
            case final snapshot?)
          'resultSnapshot': snapshot.toJson(),
      };
      try {
        // Serialized against WorkspaceController._doPersist's writes to the
        // same key via ServerConfigService.mergeJsonString, so a workspace-
        // only save landing around the same time can't revert this write
        // (or vice versa) with a stale read of the section it doesn't own.
        await ServerConfigService.mergeJsonString(
          WorkspaceController.workspaceStorageKey,
          (current) => {...current, ...payload},
        );
        // Write-through to the actual workspace file (see the equivalent
        // comment in WorkspaceController._doPersist) — `payload` here
        // already has both 'workspace' and 'canvas' fully up to date, so
        // this can just overwrite those two keys outright rather than
        // needing per-field merge logic.
        final filePath = _host.ref.read(workspaceProvider).workspaceFilePath;
        if (filePath != null) {
          await mergeJsonFile(filePath, (current) => {...current, ...payload});
        }
        _host.ref.read(workspaceProvider.notifier).scheduleServerSync();
      } finally {
        // The screen may have been disposed while the write was in flight.
        if (_host.mounted) {
          _host.ref.read(autosaveStatusProvider.notifier).markSaveFinished();
        }
      }
    });
  }

  bool get _isDesktopPlatform =>
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;

  bool get _textFieldHasPrimaryFocus {
    final focus = FocusManager.instance.primaryFocus;
    if (focus == null) {
      return false;
    }
    return focus.context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  void runDesktopShortcutIfAllowed(VoidCallback action) {
    if (!_isDesktopPlatform || _textFieldHasPrimaryFocus) {
      return;
    }
    action();
  }

  String _workspaceSaveSuggestedName(String workspaceName) {
    final slug = workspaceName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    if (slug.isEmpty || slug == 'untitled-workspace') {
      return 'session.nmtk';
    }
    return '$slug.nmtk';
  }

  /// Builds the `'canvas'` section shared by the manual workspace-file save
  /// (below) and the debounced local-storage autosave
  /// (`scheduleCanvasAutosave`) — Train/Eval pipeline, simulation results,
  /// none of which live on `WorkspaceState` itself. Result history is stored
  /// separately as one bounded terminal snapshot.
  Map<String, Object?> _buildCanvasSection() {
    final canvasState = _host.ref.read(canvasProvider);
    final simState = _host.ref.read(canvas_sim.simulationProvider);
    return {
      'pipeline': canvasState.pipeline.toJson(),
      'pipelinePhases': canvasState.pipelinePhases.toJson(),
      'simulationResults': simState.results?.toJson(),
      'simulationCurrentTime': simState.currentTime,
      // Position/size/visibility — "UI-local", never round-tripped through
      // the canonical document (see CanvasController._layoutOverrides), so
      // this is the only place they're persisted at all.
      'nodeLayout': {
        for (final node in canvasState.graph.nodes)
          node.id: {
            'x': node.position[0],
            'y': node.position[1],
            'width': node.width,
            'height': node.height,
            'isVisible': node.isVisible,
          },
      },
    };
  }

  Future<void> saveWorkspace({bool forceDialog = false}) async {
    final workspace = _host.ref.read(workspaceProvider);
    final suggestedName = _workspaceSaveSuggestedName(workspace.workspaceName);
    final payload = {
      ..._host.ref.read(workspaceProvider.notifier).buildRestorePayload(),
      'canvas': _buildCanvasSection(),
      if (_host.ref.read(studioResultSessionProvider).persistableSnapshot
          case final snapshot?)
        'resultSnapshot': snapshot.toJson(),
    };
    final result = await _host.ref
        .read(nativeFileAdapterProvider)
        .saveWorkspaceFile(suggestedName: suggestedName, payload: payload);
    if (!_host.context.mounted) {
      return;
    }
    if (result.outcome == SaveOutcome.saved) {
      _host.ref
          .read(workspaceProvider.notifier)
          .recordWorkspaceFilePath(result.path);
      NmtkSnackBars.success(
          _host.context,
          'Saved to ${result.path ?? suggestedName}',
        );
    } else if (result.outcome == SaveOutcome.failed) {
      NmtkSnackBars.error(
          _host.context,
          result.message ?? 'Workspace save failed.',
        );
    }
  }

  Future<void> saveWorkspaceAs() => saveWorkspace(forceDialog: true);

  Future<void> openWorkspace() async {
    _host.rebuild(() => _host.isOpeningWorkspace = true);
    try {
      final workspaceFile = await _host.ref
          .read(nativeFileAdapterProvider)
          .openWorkspaceFile();
      if (!_host.context.mounted) {
        return;
      }
      if (workspaceFile == null) {
        return;
      }
      _host.ref
          .read(workspaceProvider.notifier)
          .replaceFromWorkspacePayload(
            workspaceFile.payload,
            sourceFileName: workspaceFile.name,
            sourceFilePath: workspaceFile.path,
          );
      final restoreFailed = restoreCanvasSectionFromPayload(
        _host.ref,
        workspaceFile.payload,
      );
      if (!_host.context.mounted) {
        return;
      }
      if (restoreFailed) {
        NmtkSnackBars.error(
          _host.context,
          'Opened workspace ${workspaceFile.name}, but part of its '
          'canvas state (pipeline, simulation, or layout) could not '
          'be restored. Check the logs and re-save to repair the file.',
        );
      } else {
        NmtkSnackBars.success(
          _host.context,
          'Opened workspace ${workspaceFile.name}.',
        );
      }
    } on FormatException {
      if (!_host.context.mounted) {
        return;
      }
      NmtkSnackBars.error(
          _host.context,
          'Workspace file must contain a valid workspace JSON object.',
        );
    } catch (_) {
      if (!_host.context.mounted) {
        return;
      }
      NmtkSnackBars.error(
          _host.context,
          'Workspace open failed. Check the file and try again.',
        );
    } finally {
      if (_host.mounted) {
        _host.rebuild(() => _host.isOpeningWorkspace = false);
      }
    }
  }

  void newFile() {
    _host.ref.read(workspaceProvider.notifier).createUntitledFile();
  }
}

/// Restores the architecture graph, Train/Eval pipeline config/DAGs, and last
/// simulation and training results from a saved workspace payload's
/// `'canvas'` section. Missing or malformed data (e.g. a workspace file saved
/// before this section existed) is a no-op for that field — the canvas stays
/// at its current state for whatever couldn't be restored.
///
/// Top-level (not on [WorkspaceFileIoController]) so every workspace load
/// entry point can call it — not just [WorkspaceFileIoController.openWorkspace],
/// but also `setup_step.dart`'s "Load from disc"/"Load from hub" flows, which
/// run on a different `ConsumerState` and previously never restored the
/// canvas section at all.
///
/// Returns `true` if any section failed to restore (so the caller can warn
/// the user instead of reporting a silent success).
bool restoreCanvasSectionFromPayload(
  WidgetRef ref,
  Map<String, Object?> payload,
) {
  restoreResultSessionFromPayload(ref, payload);
  // Best-effort, independent of the 'canvas' section below: re-mint the
  // NIR import_id from the active file's cached bytes so a restart doesn't
  // silently fall back to placeholder weights on the next notebook
  // generation. Fire-and-forget — failure just leaves import_id empty,
  // same as if nothing had ever been imported.
  unawaited(
    ref
        .read(latestFileBackedNirImportIdProvider.notifier)
        .restoreFromWorkspaceCache(),
  );

  // `replaceFromWorkspacePayload` (called just before this) swapped in a
  // brand-new canonical document. If a debounced canvas edit was still
  // pushing to the canonical doc when the load landed, the regular
  // ref.listen mirror in CanvasController.build() silently skips itself —
  // force a re-mirror so the loaded graph always wins over stale state.
  ref.read(canvasProvider.notifier).resyncFromCanonicalDocument();
  ref.read(canvasProvider.notifier).resetLayoutOverrides();

  final canvasJson = payload['canvas'];
  if (canvasJson is! Map) {
    return false;
  }
  final canvas = Map<String, dynamic>.from(canvasJson);
  var failed = false;

  try {
    ref
        .read(canvasProvider.notifier)
        .restorePipelineState(
          pipeline: PipelineConfig.fromJson(
            Map<String, dynamic>.from(canvas['pipeline'] as Map? ?? {}),
          ),
          pipelinePhases: PipelinePhases.fromJson(
            Map<String, dynamic>.from(canvas['pipelinePhases'] as Map? ?? {}),
          ),
        );
  } catch (error, stackTrace) {
    failed = true;
    debugPrint(
      'Workspace restore: failed to restore pipeline/pipelinePhases: '
      '$error\n$stackTrace',
    );
  }

  try {
    final simResults = canvas['simulationResults'];
    ref
        .read(canvas_sim.simulationProvider.notifier)
        .restoreSnapshot(
          resultsJson: simResults is Map
              ? Map<String, dynamic>.from(simResults)
              : null,
          currentTime:
              (canvas['simulationCurrentTime'] as num?)?.toDouble() ?? 0.0,
        );
  } catch (error, stackTrace) {
    failed = true;
    debugPrint(
      'Workspace restore: failed to restore simulation snapshot: '
      '$error\n$stackTrace',
    );
  }

  try {
    final nodeLayoutJson = canvas['nodeLayout'];
    if (nodeLayoutJson is Map) {
      ref
          .read(canvasProvider.notifier)
          .applyNodeLayout(Map<String, dynamic>.from(nodeLayoutJson));
    }
  } catch (error, stackTrace) {
    failed = true;
    debugPrint(
      'Workspace restore: failed to restore node layout: $error\n$stackTrace',
    );
  }

  // The graph, pipeline phases, and saved node layout are now all in place.
  // Only now ask every canvas to establish its safe first-node viewport.
  ref.read(canvasProvider.notifier).requestWorkspaceRestoreFocus();

  final finalGraph = ref.read(canvasProvider).graph;
  debugPrint(
    'restoreCanvasSectionFromPayload: done, graph has '
    '${finalGraph.nodes.length} nodes / ${finalGraph.edges.length} edges '
    '(failed=$failed)',
  );

  return failed;
}

/// Restores only the compact, terminal result snapshot. Legacy
/// `canvas.trainingHistory` is migrated into that shape, while active jobs,
/// subscriptions, simulation arrays, and decoded activity buffers are never
/// reconstructed.
bool restoreResultSessionFromPayload(
  WidgetRef ref,
  Map<String, Object?> payload,
) {
  try {
    StudioResultSnapshot? snapshot;
    final snapshotJson = payload['resultSnapshot'];
    if (snapshotJson is Map) {
      snapshot = StudioResultSnapshot.fromJson(
        Map<String, dynamic>.from(snapshotJson),
      );
    } else {
      final directLegacy = payload['legacyTrainingHistory'];
      final canvasJson = payload['canvas'];
      final canvasLegacy = canvasJson is Map
          ? canvasJson['trainingHistory']
          : null;
      final legacy = directLegacy is Map
          ? directLegacy
          : canvasLegacy is Map
          ? canvasLegacy
          : null;
      if (legacy != null) {
        snapshot = StudioResultSnapshot.fromLegacyHistory(
          Map<String, dynamic>.from(legacy),
          workspaceName: ref.read(workspaceProvider).workspaceName,
        );
        if (!snapshot.hasVisualizationData) snapshot = null;
      }
    }

    final session = ref.read(studioResultSessionProvider.notifier);
    ref.read(trainingHistoryProvider.notifier).reset();
    ref.read(trainingJobIdsProvider.notifier).reset();
    if (snapshot == null) {
      session.clear();
      return false;
    }
    session.restoreSnapshot(snapshot);
    ref.read(trainingHistoryProvider.notifier).update(snapshot.history);
    for (final entry in snapshot.platforms.entries) {
      final job = entry.value.completedJob;
      if (job == null) continue;
      ref
          .read(trainingJobIdsProvider.notifier)
          .setJobId(entry.key, job.jobId, service: job.service);
    }
    return false;
  } catch (error, stackTrace) {
    ref.read(studioResultSessionProvider.notifier).clear();
    debugPrint(
      'Workspace restore: failed to restore result snapshot: '
      '$error\n$stackTrace',
    );
    return true;
  }
}
