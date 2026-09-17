import 'dart:typed_data';

Future<void> writePickedSavePathIfNeeded(String? path, Uint8List bytes) async {}

Future<bool> writeToPath(String? path, Uint8List bytes) async => false;

Future<bool> mergeJsonFile(
  String? path,
  Map<String, Object?> Function(Map<String, Object?> current) merge,
) async => false;
