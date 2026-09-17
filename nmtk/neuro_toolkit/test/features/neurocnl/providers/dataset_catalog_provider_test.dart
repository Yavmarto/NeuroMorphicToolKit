import 'dart:async';
import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';
import 'package:neuro_toolkit/features/neurocnl/models/dataset_catalog.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/dataset_catalog_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

void main() {
  late _RecordingApiClient api;
  late ProviderContainer container;

  setUp(() {
    api = _RecordingApiClient();
    container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
  });

  tearDown(() => container.dispose());

  test('build loads datasets from the API', () async {
    api.catalog = const DatasetCatalogList(
      firebaseAvailable: true,
      datasets: [
        DatasetEntry(
          id: 'nmnist',
          label: 'N-MNIST',
          description: 'Event-based MNIST',
          storagePath: 'datasets/nmnist/nmnist.h5',
          status: DatasetServerStatus.notDownloaded,
        ),
      ],
      folders: [
        DatasetFolder(
          folderName: 'nmnist',
          folderPath: 'datasets/nmnist/',
          description: 'Event-based MNIST',
          files: [
            DatasetEntry(
              id: 'nmnist',
              label: 'N-MNIST',
              description: 'Event-based MNIST',
              storagePath: 'datasets/nmnist/nmnist.h5',
              status: DatasetServerStatus.notDownloaded,
            ),
          ],
        ),
      ],
    );

    final list = await container.read(datasetCatalogProvider.future);
    expect(list.datasets, hasLength(1));
    expect(list.datasets.first.label, 'N-MNIST');
    expect(list.folders, hasLength(1));
    expect(list.folders.first.folderName, 'nmnist');
    expect(list.folders.first.files, hasLength(1));
    expect(api.listCalls, 1);
  });

  test('importFromDevice registers a ready local dataset', () async {
    api.catalog = const DatasetCatalogList(
      firebaseAvailable: false,
      datasets: [],
      folders: [],
    );
    api.importResult = const DatasetEntry(
      id: 'local-events-aedat',
      label: 'events.aedat',
      description: 'Imported from this device (events.aedat).',
      storagePath: 'local://events.aedat',
      folderPath: 'local/',
      status: DatasetServerStatus.ready,
      localPath: '/data/local/events.aedat',
      source: 'local',
      format: 'aedat',
    );

    await container.read(datasetCatalogProvider.future);
    final entry = await container
        .read(datasetCatalogProvider.notifier)
        .importFromDevice(
          OpenedBinaryFile(
            name: 'events.aedat',
            bytes: Uint8List.fromList(<int>[1, 2, 3]),
            path: '/tmp/events.aedat',
          ),
        );

    expect(api.importCalls, 1);
    expect(entry.isReady, isTrue);
    expect(entry.source, 'local');
  });

  test('downloadToServer returns the server path', () async {
    api.catalog = const DatasetCatalogList(
      firebaseAvailable: true,
      datasets: [
        DatasetEntry(
          id: 'nmnist',
          label: 'N-MNIST',
          description: 'Event-based MNIST',
          storagePath: 'datasets/nmnist/nmnist.h5',
          status: DatasetServerStatus.notDownloaded,
        ),
      ],
    );
    api.downloadLocalPath = '/data/datasets/nmnist/nmnist.h5';

    await container.read(datasetCatalogProvider.future);
    final path = await container
        .read(datasetCatalogProvider.notifier)
        .downloadToServer('nmnist');

    expect(path, '/data/datasets/nmnist/nmnist.h5');
    expect(api.downloadCalls, 1);
  });

  test(
    'stale polling refresh does not overwrite ready state after download',
    () async {
      const notDownloadedCatalog = DatasetCatalogList(
        firebaseAvailable: true,
        datasets: [
          DatasetEntry(
            id: 'nmnist',
            label: 'N-MNIST',
            description: 'Event-based MNIST',
            storagePath: 'datasets/nmnist/nmnist.h5',
            status: DatasetServerStatus.notDownloaded,
          ),
        ],
      );
      const readyCatalog = DatasetCatalogList(
        firebaseAvailable: true,
        datasets: [
          DatasetEntry(
            id: 'nmnist',
            label: 'N-MNIST',
            description: 'Event-based MNIST',
            storagePath: 'datasets/nmnist/nmnist.h5',
            status: DatasetServerStatus.ready,
            localPath: '/data/datasets/nmnist/nmnist.h5',
            downloadedAt: '2026-06-05T00:00:00Z',
          ),
        ],
      );

      final stalePollCompleter = Completer<DatasetCatalogList>();
      api.listDatasetHandler = () {
        switch (api.listCalls) {
          case 1:
            return Future.value(notDownloadedCatalog);
          case 2:
            return stalePollCompleter.future;
          case 3:
            return Future.value(readyCatalog);
          default:
            return Future.value(readyCatalog);
        }
      };
      api.triggerAndWaitHandler = (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 1100));
        return '/data/datasets/nmnist/nmnist.h5';
      };

      await container.read(datasetCatalogProvider.future);
      final downloadFuture = container
          .read(datasetCatalogProvider.notifier)
          .downloadToServer('nmnist');

      expect(await downloadFuture, '/data/datasets/nmnist/nmnist.h5');

      stalePollCompleter.complete(notDownloadedCatalog);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(datasetCatalogProvider).requireValue;
      expect(state.datasets.single.status, DatasetServerStatus.ready);
      expect(
        state.datasets.single.localPath,
        '/data/datasets/nmnist/nmnist.h5',
      );
    },
  );
}

class _RecordingApiClient extends ApiClient {
  _RecordingApiClient() : super(baseUrl: 'http://test');

  DatasetCatalogList catalog = const DatasetCatalogList(
    firebaseAvailable: false,
    datasets: [],
    folders: [],
  );
  String? downloadLocalPath;
  DatasetEntry? importResult;
  Future<DatasetCatalogList> Function()? listDatasetHandler;
  Future<String> Function(String datasetId)? triggerAndWaitHandler;
  int listCalls = 0;
  int downloadCalls = 0;
  int importCalls = 0;

  @override
  Future<DatasetCatalogList> listDatasets() async {
    listCalls += 1;
    if (listDatasetHandler != null) {
      return listDatasetHandler!();
    }
    return catalog;
  }

  @override
  Future<DatasetEntry> importLocalDataset({
    required String filename,
    required Uint8List bytes,
    String? serverPath,
  }) async {
    importCalls += 1;
    return importResult!;
  }

  @override
  Future<String> triggerAndWaitForDownload(String datasetId) async {
    downloadCalls += 1;
    if (triggerAndWaitHandler != null) {
      return triggerAndWaitHandler!(datasetId);
    }
    return downloadLocalPath!;
  }
}
