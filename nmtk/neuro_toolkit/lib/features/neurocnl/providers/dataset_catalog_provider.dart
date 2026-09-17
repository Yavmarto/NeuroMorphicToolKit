import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/dataset_catalog.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

final datasetCatalogProvider =
    AsyncNotifierProvider<DatasetCatalogNotifier, DatasetCatalogList>(
      DatasetCatalogNotifier.new,
    );

class DatasetCatalogNotifier extends AsyncNotifier<DatasetCatalogList> {
  final Map<String, DatasetServerStatus> _localOverrides = {};
  final Map<String, double> _progressOverrides = {};
  int _fetchSequence = 0;

  @override
  Future<DatasetCatalogList> build() async {
    ref.watch(apiClientProvider);
    return _fetch();
  }

  Future<DatasetCatalogList> _fetch() async {
    final client = ref.read(apiClientProvider);
    final list = await client.listDatasets();
    if (_localOverrides.isEmpty && _progressOverrides.isEmpty) {
      return list;
    }
    final mergedDatasets = list.datasets
        .map((entry) {
          var e = entry;
          if (_localOverrides.containsKey(entry.id)) {
            e = e.copyWith(status: _localOverrides[entry.id]);
          }
          if (_progressOverrides.containsKey(entry.id)) {
            e = e.copyWith(downloadProgress: _progressOverrides[entry.id]);
          }
          return e;
        })
        .toList(growable: false);
    final mergedFolders = list.folders
        .map(
          (folder) => DatasetFolder(
            folderName: folder.folderName,
            folderPath: folder.folderPath,
            description: folder.description,
            files: folder.files
                .map((entry) {
                  var e = entry;
                  if (_localOverrides.containsKey(entry.id)) {
                    e = e.copyWith(status: _localOverrides[entry.id]);
                  }
                  if (_progressOverrides.containsKey(entry.id)) {
                    e = e.copyWith(
                      downloadProgress: _progressOverrides[entry.id],
                    );
                  }
                  return e;
                })
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
    return DatasetCatalogList(
      firebaseAvailable: list.firebaseAvailable,
      datasets: mergedDatasets,
      folders: mergedFolders,
    );
  }

  Future<void> refresh() async {
    final sequence = _nextFetchSequence();
    state = const AsyncLoading();
    final next = await _fetch();
    if (!_shouldApplyFetch(sequence)) return;
    state = AsyncData(next);
  }

  void _setLocalStatus(String id, DatasetServerStatus status) {
    _localOverrides[id] = status;
    _pushState();
  }

  void _setProgress(String id, double? progress) {
    if (progress == null) {
      _progressOverrides.remove(id);
    } else {
      _progressOverrides[id] = progress;
    }
    _pushState();
  }

  void _pushState() {
    final current = state.value;
    if (current == null) return;

    final mergedDatasets = current.datasets
        .map((entry) {
          var e = entry;
          if (_localOverrides.containsKey(entry.id)) {
            e = e.copyWith(status: _localOverrides[entry.id]);
          }
          if (_progressOverrides.containsKey(entry.id)) {
            e = e.copyWith(downloadProgress: _progressOverrides[entry.id]);
          }
          return e;
        })
        .toList(growable: false);

    final mergedFolders = current.folders
        .map(
          (folder) => DatasetFolder(
            folderName: folder.folderName,
            folderPath: folder.folderPath,
            description: folder.description,
            files: folder.files
                .map((entry) {
                  var e = entry;
                  if (_localOverrides.containsKey(entry.id)) {
                    e = e.copyWith(status: _localOverrides[entry.id]);
                  }
                  if (_progressOverrides.containsKey(entry.id)) {
                    e = e.copyWith(
                      downloadProgress: _progressOverrides[entry.id],
                    );
                  }
                  return e;
                })
                .toList(growable: false),
          ),
        )
        .toList(growable: false);

    state = AsyncData(
      DatasetCatalogList(
        firebaseAvailable: current.firebaseAvailable,
        datasets: mergedDatasets,
        folders: mergedFolders,
      ),
    );
  }

  /// Fetches and updates state without transitioning to [AsyncLoading] first.
  /// Used for background polling so the UI is not disrupted.
  Future<void> _softRefresh() async {
    final sequence = _nextFetchSequence();
    try {
      final next = await _fetch();
      if (!_shouldApplyFetch(sequence)) return;
      state = AsyncData(next);
    } catch (e) {
      debugPrint('Dataset catalog background poll failed: $e');
    }
  }

  int _nextFetchSequence() => ++_fetchSequence;

  bool _shouldApplyFetch(int sequence) =>
      ref.mounted && sequence == _fetchSequence;

  Future<DatasetEntry> importFromDevice(OpenedBinaryFile file) async {
    final client = ref.read(apiClientProvider);
    final entry = await client.importLocalDataset(
      filename: file.name,
      bytes: file.bytes,
      serverPath: file.path,
    );
    await refresh();
    return entry;
  }

  Future<String> downloadToServer(String id) async {
    _setLocalStatus(id, DatasetServerStatus.downloading);
    _setProgress(id, 0.0);

    // Poll the catalog every second so download_progress updates are visible.
    final pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (ref.mounted && state.value != null) {
        _softRefresh();
      }
    });

    try {
      final client = ref.read(apiClientProvider);
      final localPath = await client.triggerAndWaitForDownload(id);
      pollTimer.cancel();
      _localOverrides.remove(id);
      _progressOverrides.remove(id);
      await refresh();
      return localPath;
    } catch (e) {
      pollTimer.cancel();
      _setLocalStatus(id, DatasetServerStatus.error);
      _progressOverrides.remove(id);
      rethrow;
    }
  }
}
