import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_hdf5_tree.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canonical_doc_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart' as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/nir_import_state.dart';

import 'package:http/http.dart' as http;
export 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/nir_import_state.dart';

part 'nir_import_provider.g.dart';

// State is now imported from '../src/features/studio/domain/nir_import_state.dart'

class LatestFileBackedNirImportIdController extends Notifier<String> {
  @override
  String build() => '';

  void setImportId(String importId) {
    state = importId;
  }

  void clear() {
    state = '';
  }

  /// Re-mints an `import_id` from the active file's cached `.nir` bytes.
  ///
  /// `import_id` only lives in this runtime provider — it's never written
  /// into the saved workspace file — so it's lost on every app restart.
  /// The raw bytes it points to *are* persisted, in
  /// [WorkspaceFile.nirArtifactCache], so on workspace restore we replay the
  /// same best-effort `/nir/import` call the manual import flow makes
  /// (see [NirImportController.inspectFile]) to recover a working id without
  /// requiring the user to re-import the file by hand.
  Future<void> restoreFromWorkspaceCache() async {
    final activeFile = ref.read(workspaceProvider).activeFile;
    final cache = activeFile?.nirArtifactCache;
    if (cache == null) {
      return;
    }
    final cnlText = activeFile?.canonicalDocument?.cnlText ?? '';
    if (!cache.isValidForContent(cnlText)) {
      // Stale cache from before a CNL edit — don't bake in weights that no
      // longer match the current architecture.
      return;
    }
    try {
      final apiClient = ref.read(canvas_sync.apiClientProvider);
      final importResponse = await apiClient.importNirBytes(cache.payloadBytes);
      if (importResponse.importId.isNotEmpty) {
        setImportId(importResponse.importId);
      }
    } catch (e) {
      // importId stays whatever it was (likely empty) — notebook generation
      // degrades gracefully to placeholder weights, same as today.
      debugPrint('Failed to restore NIR import_id from workspace cache: $e');
    }
  }
}

final latestFileBackedNirImportIdProvider =
    NotifierProvider<LatestFileBackedNirImportIdController, String>(
      LatestFileBackedNirImportIdController.new,
    );

@riverpod
class NirImportController extends _$NirImportController {
  @override
  NirImportState build() {
    // Reactively rebuild the NIR tree whenever the canonical document changes
    // (including a file switch — CanonicalDocController re-seeds on that),
    // unless the user has an uploaded .nir file open for inspection (which
    // takes priority until dismissed or explicitly applied).
    ref.listen<AsyncValue<CanonicalEditorDocument?>>(canonicalDocProvider, (
      _,
      next,
    ) {
      final doc = next.value;
      if (doc == null) return;
      if (_currentSource == NirSource.file) return;
      _syncFromIr(doc.irJson);
    });

    // An uploaded-for-inspection .nir file is session-local UI state, not
    // tied to any one workspace file — drop it on file switch so a stale
    // inspection tree doesn't linger over the newly-active document.
    ref.listen<String?>(workspaceProvider.select((w) => w.activeFileId), (
      previous,
      next,
    ) {
      if (previous != next) {
        if (_currentSource == NirSource.file) {
          _setState(const NirImportState.idle());
        }
        ref.read(latestFileBackedNirImportIdProvider.notifier).clear();
      }
    });

    // React to pipeline generation.
    ref.listen<String?>(
      pipelineProvider.select((p) => p.generateResult?.nirCode),
      (previous, next) {
        if (next != null && next.isNotEmpty && next != previous) {
          syncFromPipelineNirCode(next);
        }
      },
    );

    // Seed from the canonical document if available.
    final currentDoc = ref.read(canonicalDocProvider).value;
    if (currentDoc != null) {
      // Use the IR JSON to build an initial NIR tree.
      // We can't call _syncFromIr (it mutates state), so inline the logic.
      final initial = _buildFromIr(currentDoc.irJson);
      if (initial != null) return initial;
    }

    return const NirImportState.idle();
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  NirSource get _currentSource => switch (state) {
    NirImportIdle() => NirSource.none,
    NirImportLoading(:final source) => source,
    NirImportLoaded(:final source) => source,
    NirImportError(:final source) => source,
  };

  void _setState(NirImportState next) {
    state = next;
  }

  (String?, int?) _captureActiveDocumentToken() {
    final activeFile = ref.read(workspaceProvider).activeFile;
    return (activeFile?.id, activeFile?.revision);
  }

  bool _matchesActiveDocument(String? fileId, int? revision) {
    if (fileId == null || revision == null) return true;
    final activeFile = ref.read(workspaceProvider).activeFile;
    return activeFile?.id == fileId && activeFile?.revision == revision;
  }

  NirImportState? _buildFromIr(Map<String, dynamic> irJson) {
    if (irJson.isEmpty) return null;
    try {
      final children = irJson.entries.map((e) {
        final v = e.value;
        if (v is Map<String, dynamic>) {
          return NirHdf5Group(
                name: e.key,
                attrs: const {},
                children: v.entries
                    .map(
                      (e2) =>
                          NirHdf5Dataset(
                                name: e2.key,
                                attrs: const {},
                                shape: const [],
                                dtype: 'json',
                                preview: [e2.value.toString()],
                              )
                              as NirHdf5Node,
                    )
                    .toList(),
              )
              as NirHdf5Node;
        }
        return NirHdf5Dataset(
              name: e.key,
              attrs: const {},
              shape: const [],
              dtype: 'json',
              preview: [v.toString()],
            )
            as NirHdf5Node;
      }).toList();

      final result = NirInspectResult(
        fileName: 'canonical (live)',
        fileSizeBytes: 0,
        root: NirHdf5Group(name: '/', attrs: const {}, children: children),
      );
      return NirImportState.loaded(result: result, source: NirSource.canvas);
    } catch (e) {
      debugPrint('Failed to build HDF5 tree from live IR JSON: $e');
      return null;
    }
  }

  void _syncFromIr(Map<String, dynamic> irJson) {
    final next = _buildFromIr(irJson);
    if (next == null) return;
    _setState(next);
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Called by the NIR tab whenever [GenerateResult.nirCode] changes.
  void syncFromPipelineNirCode(String nirCode) {
    if (_currentSource == NirSource.file ||
        _currentSource == NirSource.canvas) {
      return;
    }
    if (nirCode.isEmpty) return;
    try {
      final result = NirInspectResult.fromNirCodeJson(nirCode);
      _setState(
        NirImportState.loaded(result: result, source: NirSource.pipeline),
      );
    } catch (e) {
      debugPrint('Failed to parse pipeline NIR code: $e');
    }
  }

  /// Export the current canvas graph to a .nir file and inspect its HDF5 tree.
  Future<void> syncFromCanvas(CanvasGraph canvasGraph) async {
    if (_currentSource == NirSource.file) return;
    final (runFileId, runRevision) = _captureActiveDocumentToken();
    _setState(const NirImportState.loading(source: NirSource.canvas));
    try {
      final apiClient = ref.read(canvas_sync.apiClientProvider);
      final nirBytes = await apiClient.exportNirBytes(canvasGraph);

      final studioApi = ref.read(apiClientProvider);
      final uri = Uri.parse('${studioApi.baseUrl}/nir/inspect');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            nirBytes,
            filename: 'canvas.nir',
          ),
        );
      final streamed = await studioApi.rawHttpClient.send(request);
      final body = await streamed.stream.bytesToString();

      if (!_matchesActiveDocument(runFileId, runRevision)) return;

      if (streamed.statusCode != 200) {
        _setState(
          NirImportState.loaded(
            result: NirInspectResult(
              fileName: 'canvas (exported)',
              fileSizeBytes: nirBytes.length,
              root: const NirHdf5Group(name: '/', attrs: {}, children: []),
            ),
            source: NirSource.canvas,
          ),
        );
        return;
      }

      final result = NirInspectResult.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );
      _setState(
        NirImportState.loaded(result: result, source: NirSource.canvas),
      );
    } catch (e) {
      if (!_matchesActiveDocument(runFileId, runRevision)) return;
      _setState(
        NirImportState.error(error: e.toString(), source: NirSource.canvas),
      );
    }
  }

  /// Upload a .nir file: inspect its HDF5 tree AND translate back to CNL +
  /// canvas graph for bidirectional write-back.
  Future<void> inspectFile(String fileName, Uint8List bytes) async {
    final (runFileId, runRevision) = _captureActiveDocumentToken();
    _setState(const NirImportState.loading(source: NirSource.file));
    try {
      final studioApi = ref.read(apiClientProvider);
      final uri = Uri.parse('${studioApi.baseUrl}/nir/inspect');
      final request = http.MultipartRequest('POST', uri)
        ..files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: fileName),
        );
      final streamed = await studioApi.rawHttpClient.send(request);
      final body = await streamed.stream.bytesToString();

      if (!_matchesActiveDocument(runFileId, runRevision)) return;

      if (streamed.statusCode != 200) {
        final decoded = jsonDecode(body);
        final detail = decoded is Map<String, dynamic>
            ? (decoded['detail'] ?? 'Inspect failed.')
            : 'Inspect failed.';
        _setState(
          NirImportState.error(
            error: detail.toString(),
            source: NirSource.file,
          ),
        );
        return;
      }

      final result = NirInspectResult.fromJson(
        jsonDecode(body) as Map<String, dynamic>,
      );

      // Best-effort: also register the upload with `/nir/import` to obtain
      // an `import_id` handle to the real trained weights. This is used
      // later by notebook generation to bake in the real weights instead of
      // placeholder/untrained ones. Failure here must not block the
      // inspect/canonical-doc flow above — it just means the notebook will
      // fall back to placeholder weights (with an honest warning).
      String importId = '';
      try {
        final apiClient = ref.read(canvas_sync.apiClientProvider);
        final importResponse = await apiClient.importNirBytes(bytes);
        if (!_matchesActiveDocument(runFileId, runRevision)) return;
        importId = importResponse.importId;
        if (importId.isNotEmpty) {
          ref
              .read(latestFileBackedNirImportIdProvider.notifier)
              .setImportId(importId);
        }
      } catch (e) {
        // importId stays empty, notebook generation degrades gracefully to
        // placeholder weights.
        debugPrint('Failed to register NIR upload for import: $e');
      }

      _setState(
        NirImportState.loaded(
          result: result,
          source: NirSource.file,
          rawBytes: bytes,
          importId: importId,
        ),
      );
    } catch (e) {
      if (!_matchesActiveDocument(runFileId, runRevision)) return;
      _setState(
        NirImportState.error(error: e.toString(), source: NirSource.file),
      );
    }
  }

  /// Mark the file-import side effects (e.g. preflight) as consumed.
  void markWriteBackConsumed() {
    final s = state;
    if (s is NirImportLoaded) {
      _setState(s.copyWith(writeBackConsumed: true));
    }
  }

  void reset() {
    _setState(const NirImportState.idle());
    ref.read(latestFileBackedNirImportIdProvider.notifier).clear();
    ref.read(canvasControllerProvider.notifier).resetGraph();
    ref.read(canonicalDocControllerProvider.notifier).clear();
  }

  /// Clear only the NIR import state — does not touch canvas or canonical doc.
  /// Used by canvas "clear all" which handles those surfaces itself.
  void clearStateOnly() => _setState(const NirImportState.idle());
}

/// Backward-compat alias consumed by all existing widgets/providers.
final nirImportProvider = nirImportControllerProvider;
