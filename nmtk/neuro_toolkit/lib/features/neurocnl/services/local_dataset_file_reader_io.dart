import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readLocalDatasetFile(String path) {
  return File(path).readAsBytes();
}

Future<bool> localDatasetFileExists(String path) {
  return File(path).exists();
}
