import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/dataset_catalog.dart';

void main() {
  test('DatasetServerStatus maps API values', () {
    expect(DatasetServerStatus.fromApi('ready'), DatasetServerStatus.ready);
    expect(
      DatasetServerStatus.fromApi('downloading'),
      DatasetServerStatus.downloading,
    );
    expect(DatasetServerStatus.fromApi('error'), DatasetServerStatus.error);
    expect(
      DatasetServerStatus.fromApi('not_downloaded'),
      DatasetServerStatus.notDownloaded,
    );
  });

  test('DatasetCatalogList parses list response', () {
    final list = DatasetCatalogList.fromJson({
      'firebase_available': true,
      'datasets': [
        {
          'id': 'nmnist',
          'label': 'N-MNIST',
          'description': 'Event-based MNIST',
          'storage_path': 'datasets/nmnist/nmnist.h5',
          'status': 'ready',
          'local_path': '/data/datasets/nmnist/nmnist.h5',
        },
      ],
    });

    expect(list.firebaseAvailable, isTrue);
    expect(list.datasets, hasLength(1));
    expect(list.datasets.first.isReady, isTrue);
    expect(list.datasets.first.localPath, '/data/datasets/nmnist/nmnist.h5');
  });

  test('findEntryById resolves entries from folders and flat datasets', () {
    const folderEntry = DatasetEntry(
      id: 'folder-dataset',
      label: 'Folder Dataset',
      description: 'Inside a folder',
      storagePath: 'datasets/folder/data.h5',
      status: DatasetServerStatus.ready,
    );
    const flatEntry = DatasetEntry(
      id: 'flat-dataset',
      label: 'Flat Dataset',
      description: 'Top-level dataset',
      storagePath: 'datasets/flat/data.h5',
      status: DatasetServerStatus.ready,
    );
    const list = DatasetCatalogList(
      firebaseAvailable: true,
      datasets: [flatEntry],
      folders: [
        DatasetFolder(
          folderName: 'folder',
          folderPath: 'datasets/folder/',
          description: 'Folder',
          files: [folderEntry],
        ),
      ],
    );

    expect(list.findEntryById('folder-dataset'), same(folderEntry));
    expect(list.findEntryById('flat-dataset'), same(flatEntry));
    expect(list.findEntryById('missing'), isNull);
  });
}
