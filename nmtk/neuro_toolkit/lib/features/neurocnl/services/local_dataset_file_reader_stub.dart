import 'dart:typed_data';

Future<Uint8List> readLocalDatasetFile(String path) {
  throw UnsupportedError(
    'Local dataset files cannot be read on this platform. '
    'Open this workspace in the desktop app and select the dataset again.',
  );
}

Future<bool> localDatasetFileExists(String path) async => false;
