import 'dart:typed_data';

import 'package:neuro_toolkit/features/neurocnl/services/local_dataset_file_reader_stub.dart'
    if (dart.library.io) 'local_dataset_file_reader_io.dart'
    as impl;

typedef LocalDatasetRead = Future<Uint8List> Function(String path);
typedef LocalDatasetExists = Future<bool> Function(String path);

Future<Uint8List> readLocalDatasetFile(String path) {
  return impl.readLocalDatasetFile(path);
}

Future<bool> localDatasetFileExists(String path) {
  return impl.localDatasetFileExists(path);
}
