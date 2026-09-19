import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/autosave_status_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart';
import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/models/studio_pipeline_steps.dart';
import 'package:neuro_toolkit/features/neurocnl/services/export_artifact.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/services/picked_save_path_writer.dart' as picked_save_path_writer;
import 'package:neuro_toolkit/features/neurocnl/utils/workspace_slug.dart';

part 'workspace_provider.g.dart';

class WorkspaceBootstrap {
  const WorkspaceBootstrap({
    this.initialLocation = '/',
    this.initialRestoreState = const <String, Object?>{},
  });

  final String initialLocation;
  final Map<String, Object?> initialRestoreState;
}

@riverpod
WorkspaceBootstrap workspaceBootstrap(Ref ref) {
  return const WorkspaceBootstrap();
}

/// Derives a human-readable workspace name from a workspace file name
/// (e.g. `my-project.nmtk` -> `my-project`). Returns `null` when the input
/// is null/empty so callers can keep the previous name as a fallback.
String? workspaceNameFromFile(String? fileName) {
  if (fileName == null) {
    return null;
  }
  final trimmed = fileName.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  final base = trimmed.replaceAll('\\', '/').split('/').last;
  const knownSuffixes = <String>['.nmtk'];
  for (final suffix in knownSuffixes) {
    if (base.toLowerCase().endsWith(suffix)) {
      final stripped = base.substring(0, base.length - suffix.length).trim();
      if (stripped.isNotEmpty) {
        return stripped;
      }
    }
  }
  final dotIndex = base.lastIndexOf('.');
  if (dotIndex > 0) {
    final stripped = base.substring(0, dotIndex).trim();
    if (stripped.isNotEmpty) {
      return stripped;
    }
  }
  return base;
}

@riverpod
class WorkspaceController extends _$WorkspaceController {
  static const int _maxRecentActivities = 20;

  /// Shared with `_StudioWorkspaceFileIo`'s debounced canvas autosave, which
  /// merges a `'canvas'` section into this same key so the Train/Eval
  /// pipeline survives hot restart alongside the workspace/model state.
  static const workspaceStorageKey = ServerConfigService.workspaceCacheKey;
  static const _legacySpecKey = 'cached_spec_text';

  /// CNL text recovered from the pre-workspace-model legacy cache
  /// (`cached_spec_text`), which predates `canonicalDocument` entirely.
  /// `WorkspaceFile` has nowhere to carry raw text anymore, so this is
  /// stashed here for the app's startup hook to feed into
  /// `CanonicalDocController.updateFromCnl` once — see
  /// [consumePendingLegacyMigrationText]. Avoids a circular import between
  /// this file and canonical_doc_provider.dart (which already imports this
  /// one for `workspaceProvider`).
  String? _pendingLegacyMigrationText;

  String? consumePendingLegacyMigrationText() {
    final text = _pendingLegacyMigrationText;
    _pendingLegacyMigrationText = null;
    return text;
  }

  /// The `'canvas'` section (Train/Eval pipeline, simulation, training
  /// history) found alongside the restored `WorkspaceState`, stashed here
  /// during [_buildInitialState] because `CanvasController` and friends
  /// live in a different provider file that can't be imported here without
  /// a circular import (see the `_pendingLegacyMigrationText` note above).
  /// Consumed once by the studio screen's startup hook via
  /// [consumePendingCanvasRestorePayload].
  Map<String, Object?>? _pendingCanvasRestorePayload;

  Map<String, Object?>? consumePendingCanvasRestorePayload() {
    final payload = _pendingCanvasRestorePayload;
    _pendingCanvasRestorePayload = null;
    return payload;
  }

  /// One bounded, terminal Studio result snapshot. This is deliberately kept
  /// separate from the canvas payload so cold-start restoration can recover
  /// useful result summaries without rehydrating simulation buffers.
  Map<String, Object?>? _pendingResultRestorePayload;
  Map<String, Object?>? _pendingResumeResultPayload;

  Map<String, Object?>? consumePendingResultRestorePayload() {
    final payload = _pendingResultRestorePayload;
    _pendingResultRestorePayload = null;
    return payload;
  }

  /// The `'workspace'` section of a previous session found in
  /// `ServerConfigService` cache at cold start, stashed here rather than
  /// applied automatically — see the round-4/round-5 memory-leak history in
  /// `current tasks/`. A cold start never auto-restores this (or the
  /// `'canvas'` section at all, deliberately — simulation results/training
  /// history/in-flight job ids are the payloads implicated in the leak and
  /// are never offered for resume). The studio screen's startup hook checks
  /// [hasPendingWorkspaceResume] and, only on explicit user confirmation,
  /// calls [resumeCachedWorkspace]; otherwise [discardPendingWorkspaceResume].
  Map<String, Object?>? _pendingResumeWorkspaceJson;

  bool _isPromptingResume = false;

  bool get hasPendingWorkspaceResume => _pendingResumeWorkspaceJson != null;

  /// Claims the right to prompt the user about resuming a workspace. Returns true
  /// if this is the first caller to claim it for this pending resume, false otherwise.
  bool beginWorkspaceResumePrompt() {
    if (_isPromptingResume) return false;
    _isPromptingResume = true;
    return true;
  }

  /// Applies the previously-found workspace JSON (files + CNL/graph text,
  /// plus which pipeline step was active) on explicit user confirmation.
  /// Still never touches the `'canvas'` section (simulation results,
  /// training history, pipeline DAG, node layout) — that stays excluded from
  /// cold-start resume regardless, since those are the payloads implicated
  /// in the round-4/round-5 memory leak.
  void resumeCachedWorkspace() {
    final json = _pendingResumeWorkspaceJson;
    _pendingResumeWorkspaceJson = null;
    _isPromptingResume = false;
    if (json == null) return;
    try {
      final restored = WorkspaceState.fromJson(Map<String, dynamic>.from(json));
      state = _normalizeWorkspaceState(restored);
      _pendingResultRestorePayload = _pendingResumeResultPayload;
      _pendingResumeResultPayload = null;
    } catch (e) {
      debugPrint('Failed to resume cached workspace: $e');
    }
  }

  /// Discards the pending resume offer without applying it (user chose to
  /// start fresh). The underlying cached blob is left untouched on disk —
  /// this only clears the in-memory offer for this session.
  void discardPendingWorkspaceResume() {
    _pendingResumeWorkspaceJson = null;
    _pendingResumeResultPayload = null;
    _isPromptingResume = false;
  }

  /// Debounces the server-side workspace sync (see [scheduleServerSync])
  /// separately from the local-storage/file writes above — a network call
  /// is more expensive than a local write, so this waits longer to coalesce
  /// bursts of edits into fewer requests.
  ///
  /// Overridable via [debugSetDebounces] because widget tests otherwise die on
  /// the leftover 1500ms timer: a bare Timer schedules no frames, so
  /// pumpAndSettle returns with it still pending and the binding reports
  /// "A Timer is still pending" before any assertion is reached.
  static Duration _serverSyncDebounce = const Duration(milliseconds: 1500);
  Timer? _serverSyncTimer;

  /// Coalesces the local write. Every mutator calls [_persist], and each write
  /// is a full `state.toJson()` plus a jsonDecode+jsonEncode merge, an fsync'd
  /// atomic file swap, and a pretty-printed `.nmtk` rewrite — far too much to
  /// run once per keystroke or once per stepper tap.
  static Duration _persistDebounce = const Duration(milliseconds: 300);
  Timer? _persistTimer;

  /// Test seam for the two debounces above. [Duration.zero] makes the local
  /// write synchronous and disables the server sync outright (see the notes on
  /// [_persist] and [scheduleServerSync]); call with no arguments to restore.
  @visibleForTesting
  static void debugSetDebounces({Duration? persist, Duration? serverSync}) {
    _persistDebounce = persist ?? const Duration(milliseconds: 300);
    _serverSyncDebounce = serverSync ?? const Duration(milliseconds: 1500);
  }

  @override
  WorkspaceState build() {
    ref.onDispose(() {
      _serverSyncTimer?.cancel();
      _persistTimer?.cancel();
    });
    final bootstrap = ref.read(workspaceBootstrapProvider);
    return _buildInitialState(bootstrap);
  }

  WorkspaceState _buildInitialState(WorkspaceBootstrap bootstrap) {
    final deepLinkUri = Uri.parse(bootstrap.initialLocation);
    final restorePayload = Map<String, Object?>.from(
      bootstrap.initialRestoreState,
    );
    var fullPayload = restorePayload;
    var workspaceJson = restorePayload['workspace'];

    // Deliberately NOT falling back to the persisted
    // `ServerConfigService.getString(workspaceStorageKey)` cache here: a cold
    // start always begins from an empty/untitled workspace rather than
    // silently reopening whatever model/canvas was last open (which could be
    // a large graph with an active train/eval pipeline still attached). The
    // cached blob (if any) is stashed in `_pendingResumeWorkspaceJson` for an
    // explicit user-confirmed resume instead — see [hasPendingWorkspaceResume]
    // — and only its `'workspace'` (files/CNL/graph) section is ever eligible
    // for that; the `'canvas'` section (simulation results, training history,
    // in-flight job ids — the payloads implicated in the memory leak) is
    // never read back in on cold start at all, confirmed or not.
    if (workspaceJson is! Map) {
      final cached = ServerConfigService.getString(workspaceStorageKey);
      if (cached != null) {
        try {
          final decoded = Map<String, Object?>.from(
            jsonDecode(cached) as Map<String, dynamic>,
          );
          final cachedWorkspace = decoded['workspace'] is Map
              ? decoded['workspace']
              : (decoded['files'] is List ? decoded : null);
          if (cachedWorkspace is Map) {
            _pendingResumeWorkspaceJson = Map<String, Object?>.from(
              cachedWorkspace.cast<String, Object?>(),
            );
          }
          final cachedResult = decoded['resultSnapshot'];
          if (cachedResult is Map) {
            _pendingResumeResultPayload = <String, Object?>{
              'resultSnapshot': Map<String, Object?>.from(cachedResult),
            };
          } else {
            final cachedCanvas = decoded['canvas'];
            final legacyHistory = cachedCanvas is Map
                ? cachedCanvas['trainingHistory']
                : null;
            if (legacyHistory is Map) {
              _pendingResumeResultPayload = <String, Object?>{
                'legacyTrainingHistory': Map<String, Object?>.from(
                  legacyHistory,
                ),
              };
            }
          }
        } catch (e) {
          debugPrint('Failed to parse cached WorkspaceState for resume: $e');
        }
      }
    }

    final canvasJson = fullPayload['canvas'];
    if (canvasJson is Map) {
      // Kept wrapped under a 'canvas' key so callers can hand the result
      // straight to `_restoreCanvasFromPayload`, which expects that shape.
      _pendingCanvasRestorePayload = <String, Object?>{
        'canvas': Map<String, Object?>.from(canvasJson),
      };
    }

    final resultSnapshotJson = fullPayload['resultSnapshot'];
    if (resultSnapshotJson is Map) {
      _pendingResultRestorePayload = <String, Object?>{
        'resultSnapshot': Map<String, Object?>.from(resultSnapshotJson),
      };
    } else if (canvasJson is Map && canvasJson['trainingHistory'] is Map) {
      _pendingResultRestorePayload = <String, Object?>{
        'legacyTrainingHistory': Map<String, Object?>.from(
          canvasJson['trainingHistory'] as Map,
        ),
      };
    }

    WorkspaceState? restored;
    if (workspaceJson is Map<String, dynamic>) {
      restored = WorkspaceState.fromJson(workspaceJson);
    } else if (workspaceJson is Map) {
      restored = WorkspaceState.fromJson(
        Map<String, dynamic>.from(workspaceJson.cast<String, dynamic>()),
      );
    }

    restored ??= _buildLegacyFallback();
    return _normalizeWorkspaceState(_applyDeepLink(restored, deepLinkUri));
  }

  WorkspaceState _buildLegacyFallback() {
    final cachedSpec = ServerConfigService.getString(_legacySpecKey) ?? '';
    if (cachedSpec.trim().isNotEmpty) {
      _pendingLegacyMigrationText = cachedSpec;
    }
    final file = WorkspaceFile(
      id: 'untitled-1',
      name: 'Untitled 1',
      dirty: cachedSpec.trim().isNotEmpty,
      isUntitled: true,
      cursorOffset: cachedSpec.length,
      selectionBase: cachedSpec.length,
      selectionExtent: cachedSpec.length,
    );
    return WorkspaceState(files: <WorkspaceFile>[file], activeFileId: file.id);
  }

  static WorkspaceState _applyDeepLink(WorkspaceState ws, Uri uri) {
    var next = ws;
    // Mirrors the hardware and simulator entries of `_deployTargets` in
    // `deploy_target_catalog.dart`, which is private to the Studio screen and
    // so cannot be read from here. An id missing from this set makes
    // `?target=<id>` silently land on the default target instead — which is
    // what `pynq` used to do, before it had a workspace worth linking to.
    const supportedDeployTargets = <String>{
      'lava_sim',
      'snntorch_sim',
      'sc_neurocore_sim',
      'brian2_sim',
      'nengo_sim',
      'sinabs_sim',
      'rockpool',
      'akida',
      'pynq',
      'lava',
      'sc_neurocore_fpga',
      'voyager_axelera',
    };
    final fileId = uri.queryParameters['file'];
    if (fileId != null && ws.files.any((f) => f.id == fileId)) {
      next = next.copyWith(activeFileId: fileId);
    }

    final panel = uri.queryParameters['panel'];
    if (panel != null && panel.isNotEmpty) {
      final resolvedPanel = _resolveDeepLinkPanel(panel);
      next = next.copyWith(
        activePanel: resolvedPanel,
        activePipelineStep: _pipelineStepForPanel(resolvedPanel),
      );
    }

    final target = uri.queryParameters['target'];
    if (target != null && supportedDeployTargets.contains(target)) {
      next = next.copyWith(selectedDeployTarget: target);
    }

    final validation = uri.queryParameters['validation'];
    if (validation != null && validation.isNotEmpty) {
      final parts = validation.split(':');
      next = next.copyWith(
        validationFocus: ValidationFocus(
          section: parts.first,
          itemId: parts.length > 1 ? parts.sublist(1).join(':') : null,
        ),
      );
    }
    return next;
  }

  static String _resolveDeepLinkPanel(String panel) {
    return switch (panel) {
      'network' || 'parameters' || 'simulation' || 'generate' => 'deploy',
      'handoff' ||
      'artifacts' ||
      'export' ||
      'analysis' ||
      'hardware' => 'deploy',
      'parsed_specs' || 'parse' => 'validation',
      'training' || 'comparison' || 'deploy' || 'validation' => panel,
      _ => panel,
    };
  }

  static String _pipelineStepForPanel(String panel) {
    return switch (panel) {
      'model' => 'defineModel',
      'training' => 'run',
      // Training results live inside the Run step now, not a step of their own.
      'comparison' => 'run',
      'deploy' => 'deployHardware',
      _ => kDefaultStudioPipelineStep,
    };
  }

  static WorkspaceState _normalizeWorkspaceState(WorkspaceState ws) {
    final resolvedPanel = _resolveDeepLinkPanel(ws.activePanel);
    final normalizedStep = normalizeStudioPipelineStep(
      ws.activePipelineStep,
      fallback: _pipelineStepForPanel(resolvedPanel),
    );
    if (normalizedStep == ws.activePipelineStep &&
        resolvedPanel == ws.activePanel) {
      return ws;
    }
    return ws.copyWith(
      activePanel: resolvedPanel,
      activePipelineStep: normalizedStep,
    );
  }

  Map<String, dynamic> buildRestorePayload() {
    return <String, dynamic>{'version': 1, 'workspace': state.toJson()};
  }

  void createUntitledFile() {
    final fileNumber = state.files.length + 1;
    final file = WorkspaceFile(
      id: 'untitled-$fileNumber-${DateTime.now().microsecondsSinceEpoch}',
      name: 'Untitled $fileNumber',
      isUntitled: true,
      dirty: false,
    );
    state = state.copyWith(
      files: <WorkspaceFile>[...state.files, file],
      activeFileId: file.id,
    );
    _persist();
    unawaited(_ensureWorkspaceFolder(state.workspaceName));
  }

  void closeFile(String fileId) {
    final remaining = state.files
        .where((f) => f.id != fileId)
        .toList(growable: false);
    if (remaining.isEmpty) {
      state = _buildLegacyFallback();
      _persist();
      return;
    }
    final activeFileId = state.activeFileId == fileId
        ? remaining.last.id
        : state.activeFileId;
    state = state.copyWith(files: remaining, activeFileId: activeFileId);
    _persist();
  }

  void setActiveFile(String fileId) {
    if (state.files.any((f) => f.id == fileId)) {
      state = state.copyWith(activeFileId: fileId);
      _persist();
    }
  }

  void markActiveFileSaved() {
    final activeFile = state.activeFile;
    if (activeFile == null || !activeFile.dirty) {
      return;
    }
    _replaceFile(activeFile.copyWith(dirty: false));
  }

  void markActiveFileSavedAs({required String name, String? path}) {
    final activeFile = state.activeFile;
    if (activeFile == null) {
      return;
    }
    _replaceFile(
      activeFile.copyWith(
        name: name,
        path: path,
        dirty: false,
        isUntitled: false,
      ),
    );
  }

  void replaceFromWorkspacePayload(
    Map<String, Object?> payload, {
    String? sourceFileName,
    String? sourceFilePath,
  }) {
    final workspaceJson = payload['workspace'];
    if (workspaceJson is! Map) {
      throw const FormatException(
        'Workspace payload missing workspace object.',
      );
    }
    final workspace = WorkspaceState.fromJson(
      Map<String, dynamic>.from(workspaceJson),
    );
    final derivedName = workspaceNameFromFile(sourceFileName);
    if (workspace.files.isEmpty) {
      state = _normalizeWorkspaceState(
        _buildLegacyFallback().copyWith(
          workspaceName: derivedName ?? workspace.workspaceName,
          workspaceFilePath: sourceFilePath,
          activePipelineStep: kDefaultStudioPipelineStep,
        ),
      );
    } else {
      state = _normalizeWorkspaceState(
        workspace.copyWith(
          workspaceName: derivedName ?? workspace.workspaceName,
          workspaceFilePath: sourceFilePath,
          activePipelineStep: kDefaultStudioPipelineStep,
        ),
      );
    }
    _persist();
  }

  /// Records the absolute path of the `.nmtk` file this
  /// workspace was just saved to, so autosave (`_doPersist` below, and the
  /// canvas-section autosave in `_StudioWorkspaceFileIo`) can write through
  /// to it going forward. Pass `null` to clear it (e.g. opening a Hub asset
  /// that has no local file of its own).
  void recordWorkspaceFilePath(String? path) {
    if (path == state.workspaceFilePath) {
      return;
    }
    state = state.copyWith(workspaceFilePath: path);
  }

  Future<void> _ensureWorkspaceFolder(String name) async {
    final slug = name.trim();
    if (slug.isEmpty) return;
    try {
      await ref.read(apiClientProvider).ensureWorkspace(workspacePath: slug);
    } catch (e) {
      // Non-fatal — folder will be created at generation time anyway.
      debugPrint('Failed to eagerly ensure workspace folder: $e');
    }
  }

  void setWorkspaceName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == state.workspaceName) {
      return;
    }
    state = state.copyWith(workspaceName: trimmed);
    _persist();
    unawaited(_ensureWorkspaceFolder(trimmed));
  }

  void setWorkspaceSourceKind(String? kind) {
    final normalized = kind?.trim();
    if ((normalized == null || normalized.isEmpty) &&
        state.workspaceSourceKind == null) {
      return;
    }
    if (normalized == state.workspaceSourceKind) {
      return;
    }
    state = state.copyWith(
      workspaceSourceKind: normalized == null || normalized.isEmpty
          ? null
          : normalized,
    );
    _persist();
  }

  void setBenchmarkSelection({
    String? benchmarkId,
    String? benchmarkName,
    String? sourceKind,
  }) {
    final normalizedId = benchmarkId?.trim();
    final normalizedName = benchmarkName?.trim();
    final normalizedSource = sourceKind?.trim();
    final hasChange =
        normalizedId != state.selectedBenchmarkId ||
        normalizedName != state.selectedBenchmarkName ||
        (normalizedSource == null || normalizedSource.isEmpty
            ? state.workspaceSourceKind != null
            : normalizedSource != state.workspaceSourceKind);
    if (!hasChange) {
      return;
    }
    state = state.copyWith(
      selectedBenchmarkId: normalizedId == null || normalizedId.isEmpty
          ? null
          : normalizedId,
      selectedBenchmarkName: normalizedName == null || normalizedName.isEmpty
          ? null
          : normalizedName,
      workspaceSourceKind: normalizedSource == null || normalizedSource.isEmpty
          ? state.workspaceSourceKind
          : normalizedSource,
    );
    _persist();
  }

  void clearBenchmarkSelection() {
    if (state.selectedBenchmarkId == null &&
        state.selectedBenchmarkName == null) {
      return;
    }
    state = state.copyWith(
      selectedBenchmarkId: null,
      selectedBenchmarkName: null,
    );
    _persist();
  }

  void setBenchmarkResultSummary(Map<String, dynamic>? summary) {
    final normalized = summary ?? const <String, dynamic>{};
    if (mapEquals(state.benchmarkResultSummary, normalized)) {
      return;
    }
    state = state.copyWith(benchmarkResultSummary: normalized);
    _persist();
  }

  void savePipelineCacheForActiveFile({
    required GenerateResult generateResult,
    SimulationResult? simulationResult,
  }) {
    final activeFile = state.activeFile;
    if (activeFile == null) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    _replaceFile(
      activeFile.copyWith(
        pipelineCache: WorkspacePipelineCache(
          sourceHash: WorkspacePipelineCache.sourceHashFor(
            activeFile.canonicalDocument?.cnlText ?? '',
          ),
          generatedAt: now,
          simulatedAt: simulationResult == null ? null : now,
          generateResult: generateResult,
          simulationResult: simulationResult,
        ),
      ),
    );
  }

  void setActiveFilePipelineState(PipelineState pipelineState) {
    final activeFile = state.activeFile;
    if (activeFile == null) {
      return;
    }
    _replaceFile(activeFile.copyWith(pipelineState: pipelineState));
  }

  void clearActiveFilePipelineState() {
    final activeFile = state.activeFile;
    if (activeFile == null || activeFile.pipelineState == null) {
      return;
    }
    _replaceFile(activeFile.copyWith(pipelineState: null));
  }

  /// The one write path for spec content. Bumps [WorkspaceFile.revision] —
  /// the token every canonical-doc mutation checks against before publishing
  /// its result, so a stale in-flight request from a superseded edit or a
  /// file switch is detected — and invalidates caches keyed off the old
  /// content.
  void setActiveFileCanonicalDocument(CanonicalEditorDocument? document) {
    final activeFile = state.activeFile;
    if (activeFile == null) {
      return;
    }
    final cnlText = document?.cnlText ?? '';
    _replaceFile(
      activeFile.copyWith(
        canonicalDocument: document,
        dirty: cnlText.isNotEmpty,
        cursorOffset: cnlText.length,
        selectionBase: cnlText.length,
        selectionExtent: cnlText.length,
        pipelineCache: null,
        nirArtifactCache: null,
        pipelineState: null,
        revision: activeFile.revision + 1,
      ),
    );
  }

  void saveNirArtifactForActiveFile(ExportArtifact artifact) {
    final activeFile = state.activeFile;
    if (activeFile == null || !artifact.isBinary) {
      return;
    }
    final now = DateTime.now().toIso8601String();
    final existingCache = activeFile.pipelineCache;
    _replaceFile(
      activeFile.copyWith(
        pipelineCache: existingCache,
        nirArtifactCache: WorkspaceNirArtifactCache.fromBytes(
          content: activeFile.canonicalDocument?.cnlText ?? '',
          filename: artifact.filename,
          mimeType: artifact.mimeType,
          payload: artifact.bytes!,
          savedAt: now,
        ),
      ),
    );
  }

  void updateActiveFileSelection({
    required int cursorOffset,
    required int selectionBase,
    required int selectionExtent,
  }) {
    final activeFile = state.activeFile;
    if (activeFile == null) {
      return;
    }
    _replaceFile(
      activeFile.copyWith(
        cursorOffset: cursorOffset,
        selectionBase: selectionBase,
        selectionExtent: selectionExtent,
      ),
    );
  }

  void updateActiveFileScroll(double scrollOffset) {
    final activeFile = state.activeFile;
    if (activeFile == null) {
      return;
    }
    _replaceFile(activeFile.copyWith(scrollOffset: scrollOffset));
  }

  void renameFile(String fileId, String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return;
    }
    WorkspaceFile? target;
    for (final file in state.files) {
      if (file.id == fileId) {
        target = file;
        break;
      }
    }
    if (target == null) {
      return;
    }
    _replaceFile(target.copyWith(name: trimmed));
  }

  void setActivePanel(String panelId) {
    state = state.copyWith(activePanel: panelId);
    _persist();
  }

  void setActivePipelineStep(String stepName) {
    final normalized = normalizeStudioPipelineStep(stepName);
    state = state.copyWith(activePipelineStep: normalized);
    _persist();
  }

  void selectDataset(String? datasetId, {String? serverPath}) {
    state = state.copyWith(
      selectedDataset: datasetId,
      selectedDatasetPath: serverPath,
    );
    _persist();
  }

  void togglePlatform(String platformId) {
    final current = List<String>.from(state.selectedPlatforms);
    if (current.contains(platformId)) {
      current.remove(platformId);
    } else {
      current.add(platformId);
    }
    state = state.copyWith(selectedPlatforms: current);
    _persist();
  }

  void applyRouteUri(Uri uri) {
    final next = _applyDeepLink(state, uri);
    if (_sameWorkspaceState(state, next)) {
      return;
    }
    state = next;
    _persist();
  }

  bool _sameWorkspaceState(WorkspaceState left, WorkspaceState right) {
    return encodeWorkspacePayload(left.toJson()) ==
        encodeWorkspacePayload(right.toJson());
  }

  void setSelectedDeployTarget(String targetId) {
    state = state.copyWith(selectedDeployTarget: targetId);
    _persist();
  }

  void setSplitRatio(double ratio) {
    final normalized = ratio.clamp(0.25, 0.75).toDouble();
    state = state.copyWith(splitRatio: normalized);
    _persist();
  }

  void setValidationFocus(String section, {String? itemId}) {
    state = state.copyWith(
      activePanel: 'validation',
      validationFocus: ValidationFocus(section: section, itemId: itemId),
    );
    _persist();
  }

  void recordActivity({
    required String kind,
    required String title,
    required String detail,
    required String status,
    String? panelId,
    bool switchToArtifacts = false,
  }) {
    final activity = WorkspaceActivity(
      id: 'activity-${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      title: title,
      detail: detail,
      status: status,
      timestamp: DateTime.now().toIso8601String(),
      panelId: panelId,
    );
    final activities = <WorkspaceActivity>[activity, ...state.recentActivities];
    if (activities.length > _maxRecentActivities) {
      activities.removeRange(_maxRecentActivities, activities.length);
    }
    state = state.copyWith(
      recentActivities: activities,
      activePanel: switchToArtifacts ? 'artifacts' : state.activePanel,
    );
    _persist();
  }

  void _replaceFile(WorkspaceFile updated, {bool persist = true}) {
    final files = state.files
        .map((f) => f.id == updated.id ? updated : f)
        .toList(growable: false);
    state = state.copyWith(files: files);
    if (persist) {
      _persist();
    }
  }

  /// Fire-and-forget from ~20 call sites (typing, file switch, stepper taps) —
  /// the autosave status indicator in the toolbar reports the write's progress
  /// so callers don't need to await it.
  ///
  /// Debounced by [_persistDebounce] so a burst — a stepper tap, a run of
  /// keystrokes — coalesces into one write instead of one full
  /// encode+decode+fsync per mutation.
  ///
  /// markSaveStarted/markSaveFinished deliberately stay paired inside
  /// [_doPersist] rather than being split across the debounce (which is what
  /// `_scheduleCanvasAutosave` does for earlier feedback): the timer is
  /// cancelled in `ref.onDispose`, so marking at arm-time would leave a
  /// teardown-during-debounce with a start and no finish, stranding the toolbar
  /// on "Saving…". 300ms of delayed feedback is not worth a stuck indicator.
  void _persist() {
    // Duration.zero means "write synchronously, no timer" rather than "write on
    // the next tick". Tests set it that way, and a zero-duration Timer would
    // still be a pending timer at the point flutter_test checks invariants.
    if (_persistDebounce == Duration.zero) {
      unawaited(_doPersist());
      return;
    }
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () => unawaited(_doPersist()));
  }

  Future<void> _doPersist() async {
    if (!ref.mounted) {
      return;
    }
    ref.read(autosaveStatusProvider.notifier).markSaveStarted();
    // Captured synchronously, before any `await` — `mergeJsonString` may
    // queue this write behind another in-flight merge for the same key, and
    // by the time our callback actually runs the provider could already be
    // disposed (test teardown, hot restart mid-save); reading `state` inside
    // that deferred callback would then throw. Snapshot it now instead.
    final workspaceJson = state.toJson();
    final filePath = state.workspaceFilePath;
    try {
      // Only ever touches 'version'/'workspace' — 'canvas' (owned by the
      // debounced autosave in `_StudioWorkspaceFileIo`) is left as whatever
      // `current` already holds. `ServerConfigService.mergeJsonString`
      // serializes this against that other writer so neither can race the
      // other with a stale read of the section it doesn't own (see the
      // 2026-07 bug: two independent read-then-write callers on this same
      // key could silently revert each other's most recent write).
      await ServerConfigService.mergeJsonString(workspaceStorageKey, (current) {
        return <String, Object?>{
          ...current,
          'version': 1,
          'workspace': workspaceJson,
        };
      });
      // Write-through to the actual `.nmtk` file, so
      // "autosave" keeps that file (not just the local-storage cache) in
      // sync once the user has opened or saved one. Same merge contract as
      // above, against the file's own JSON instead of a SharedPreferences
      // key — preserves whatever 'canvas' section the file already has, so
      // this writer never has to know about `_StudioWorkspaceFileIo`'s
      // canvas-section autosave (avoids a circular import). A `false`
      // result (no path yet, or a sandbox write failure after an app
      // restart — see `picked_save_path_writer_io.dart`) is an expected,
      // silent no-op: the local-storage cache above already covers it.
      if (filePath != null) {
        await picked_save_path_writer.mergeJsonFile(filePath, (current) {
          return <String, Object?>{
            ...current,
            'version': 1,
            'workspace': workspaceJson,
          };
        });
      }
      scheduleServerSync();
    } finally {
      // The container/provider may have been disposed while the write was
      // in flight (e.g. test teardown, or a hot restart mid-save) — reading
      // ref after that throws, so guard with `ref.mounted` per Riverpod's
      // own guidance rather than letting this rethrow past the write.
      if (ref.mounted) {
        ref.read(autosaveStatusProvider.notifier).markSaveFinished();
      }
    }
  }

  /// Debounced trigger for syncing the full workspace+canvas config to the
  /// server (see `_StudioWorkspaceFileIo._scheduleCanvasAutosave`, which
  /// calls this too after its own local write) — so a different device
  /// pointed at the same backend can later list and reopen this workspace.
  /// Fire-and-forget: a device with no server connectivity must keep
  /// editing locally without interruption, same as [_ensureWorkspaceFolder].
  void scheduleServerSync() {
    // Duration.zero means "don't sync at all", not "sync immediately". Tests
    // set it to stop the 1500ms timer leaking into their invariant check, and
    // they never assert on the upload — firing it eagerly instead would have
    // every suite attempting real network calls. This matches the behaviour
    // tests already relied on, where the timer simply never fired.
    if (_serverSyncDebounce == Duration.zero) {
      return;
    }
    _serverSyncTimer?.cancel();
    _serverSyncTimer = Timer(_serverSyncDebounce, () {
      unawaited(_syncToServer());
    });
  }

  Future<void> _syncToServer() async {
    if (!ref.mounted) return;
    final name = state.workspaceName;
    final slug = slugifyWorkspaceName(name);
    if (slug.isEmpty) return;
    // Read back the just-merged local cache rather than rebuilding the
    // payload here — it already holds the union of the 'workspace' section
    // (just written above) and whatever 'canvas' section the debounced
    // canvas autosave in `_StudioWorkspaceFileIo` most recently wrote into
    // this same key, so a workspace-only change (e.g. a rename) never syncs
    // a payload that's missing the canvas the server already had.
    final cached = ServerConfigService.getString(workspaceStorageKey);
    if (cached == null) return;
    Map<String, dynamic> config;
    try {
      final decoded = jsonDecode(cached);
      if (decoded is! Map) return;
      config = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }
    try {
      final client = ref.read(apiClientProvider);
      await client.syncWorkspace(slug: slug, name: name, config: config);
    } catch (e) {
      debugPrint('Failed to sync workspace to server: $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Backward-compat shim — consumed by many providers that call
// ref.read/watch(workspaceProvider). Route them to the new controller.
// ---------------------------------------------------------------------------

/// Legacy alias so existing consumers can be migrated incrementally.
/// New code should use [workspaceControllerProvider] directly.
final workspaceProvider = workspaceControllerProvider;

/// Legacy accessor for the notifier — use [workspaceControllerProvider.notifier].
@Deprecated('Use ref.read(workspaceControllerProvider.notifier) instead')
extension WorkspaceProviderLegacyExt on Ref {
  WorkspaceController get workspaceNotifier =>
      read(workspaceControllerProvider.notifier);
}

// ---------------------------------------------------------------------------
// Restore payload provider (legacy compatibility)
// ---------------------------------------------------------------------------

@riverpod
Map<String, dynamic> workspaceRestoreState(Ref ref) {
  return ref.watch(workspaceControllerProvider.notifier).buildRestorePayload();
}
