import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/local_dataset_file_reader.dart';

class DatasetPreparationException implements Exception {
  const DatasetPreparationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One node whose client-local dataset was freshly uploaded during
/// [DatasetGenerationPreparer.prepare]. Callers use this to write the durable
/// server path back into the real, persisted canvas state -- `prepare()`
/// itself only ever mutates a throwaway JSON copy for the in-flight request.
class DatasetUploadRemap {
  const DatasetUploadRemap({
    required this.phase,
    required this.nodeId,
    required this.serverPath,
  });

  final PipelinePhaseId phase;
  final String nodeId;
  final String serverPath;
}

/// Promotes each freshly-uploaded dataset's *persisted* canvas reference
/// from a client-local path to the durable server path the upload just
/// produced. Without this, every device re-uploads from scratch (or fails
/// outright if it doesn't have the file locally) even after another device
/// already left a durable copy on the server. Shared by every call site of
/// [DatasetGenerationPreparer.prepare] (Run, Notebook step, notebook
/// generation) so they can't drift out of sync with each other.
void applyDatasetUploadRemaps(WidgetRef ref, List<DatasetUploadRemap> uploads) {
  final notifier = ref.read(canvasProvider.notifier);
  for (final remap in uploads) {
    notifier.updatePipelineDagNodeParams(remap.phase, remap.nodeId, {
      'dataset_path': remap.serverPath,
      kDatasetPathScopeKey: kServerDatasetPathScope,
    });
  }
}

class DatasetPreparationResult {
  const DatasetPreparationResult({required this.phases, required this.uploads});

  /// The phases JSON to send to the backend for this one request, with every
  /// client-scoped dataset node's `dataset_path` substituted for the fresh
  /// server path.
  final Map<String, dynamic> phases;

  /// Nodes that were freshly uploaded this call, for the caller to persist
  /// back into `canvasProvider` (see [DatasetUploadRemap]).
  final List<DatasetUploadRemap> uploads;
}

/// Resolves client-local dataset references immediately before training or
/// notebook generation, uploading any not-yet-server-resident file. Uploaded
/// nodes are reported back via [DatasetPreparationResult.uploads] so the
/// caller can promote the *persisted* canvas state from a client-local path
/// to a durable server one -- without that, every device re-uploads from
/// scratch (or fails outright if it doesn't have the file locally), even
/// though the previous device's upload already left a durable copy on the
/// server.
class DatasetGenerationPreparer {
  DatasetGenerationPreparer({
    required this.apiClient,
    LocalDatasetRead? readFile,
  }) : readFile = readFile ?? readLocalDatasetFile;

  final ApiClient apiClient;
  final LocalDatasetRead readFile;

  Future<DatasetPreparationResult> prepare(PipelinePhases phases) async {
    final prepared =
        jsonDecode(jsonEncode(phases.toJson())) as Map<String, dynamic>;
    final uploadsByPath = <String, Future<String>>{};
    final remaps = <DatasetUploadRemap>[];

    for (final phaseName in const <String>['train', 'eval', 'infer']) {
      final phase = prepared[phaseName] as Map<String, dynamic>?;
      final nodes = phase?['nodes'] as List<dynamic>? ?? const <dynamic>[];
      for (final rawNode in nodes) {
        final node = rawNode as Map<String, dynamic>;
        final type = node['type'] as String? ?? '';
        final parameters =
            node['parameters'] as Map<String, dynamic>? ?? <String, dynamic>{};
        node['parameters'] = parameters;

        final scope = parameters.remove(kDatasetPathScopeKey);
        final fileNameValue = parameters.remove(kDatasetFileNameKey);
        if (scope != kClientDatasetPathScope ||
            (type != PipelineDagNodeType.dataLoader.name &&
                type != PipelineDagNodeType.testLoader.name)) {
          continue;
        }

        final format = parameters['format'] as String? ?? '';
        if (format != 'pt' && format != 'npy') {
          parameters['dataset_path'] = '';
          continue;
        }

        final path = (parameters['dataset_path'] as String? ?? '').trim();
        final fileName = (fileNameValue as String? ?? '').trim();
        if (path.isEmpty || fileName.isEmpty) {
          throw DatasetPreparationException(
            "Dataset node '${node['id']}' has no readable local file. "
            'Choose the dataset again, then regenerate the notebook.',
          );
        }

        final nodeId = node['id'] as String;
        final serverPath = await uploadsByPath.putIfAbsent(
          path,
          () => _upload(path: path, fileName: fileName, nodeId: nodeId),
        );
        parameters['dataset_path'] = serverPath;
        remaps.add(
          DatasetUploadRemap(
            phase: PipelinePhaseId.values.byName(phaseName),
            nodeId: nodeId,
            serverPath: serverPath,
          ),
        );
      }
    }

    return DatasetPreparationResult(phases: prepared, uploads: remaps);
  }

  Future<String> _upload({
    required String path,
    required String fileName,
    required String nodeId,
  }) async {
    final Uint8List bytes;
    try {
      bytes = await readFile(path);
    } on Object catch (_) {
      throw DatasetPreparationException(
        "Dataset '$fileName' for node '$nodeId' is no longer readable at "
        "'$path'. Choose the file again, then regenerate the notebook. "
        'The file may have moved or its permission may have expired.',
      );
    }
    if (bytes.isEmpty) {
      throw DatasetPreparationException(
        "Dataset '$fileName' for node '$nodeId' is empty. "
        'Choose a non-empty file, then regenerate the notebook.',
      );
    }
    try {
      return await apiClient.uploadRawDatasetFile(
        filename: fileName,
        bytes: bytes,
      );
    } on Object catch (_) {
      throw DatasetPreparationException(
        "Could not upload dataset '$fileName' while generating the notebook. "
        'Check the server connection and try Generate again.',
      );
    }
  }
}
