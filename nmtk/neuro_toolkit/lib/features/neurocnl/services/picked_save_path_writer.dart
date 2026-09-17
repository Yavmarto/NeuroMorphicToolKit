import 'dart:typed_data';

import 'package:neuro_toolkit/features/neurocnl/services/picked_save_path_writer_stub.dart'
    if (dart.library.io) 'picked_save_path_writer_io.dart'
    as impl;

Future<void> writePickedSavePathIfNeeded(String? path, Uint8List bytes) {
  return impl.writePickedSavePathIfNeeded(path, bytes);
}

/// Writes [bytes] straight to [path] with no picker dialog. Returns `false`
/// (never throws) if `path` is null/empty, on the web stub, or on any
/// platform write failure — see `picked_save_path_writer_io.dart` for why a
/// sandboxed-macOS failure after an app restart is an expected case here.
Future<bool> writeToPath(String? path, Uint8List bytes) {
  return impl.writeToPath(path, bytes);
}

/// Read-modify-write merge of the JSON object at [path] — see
/// `picked_save_path_writer_io.dart` for the full contract. Returns `false`
/// (never throws) on the web stub, a null/empty path, or any write failure.
Future<bool> mergeJsonFile(
  String? path,
  Map<String, Object?> Function(Map<String, Object?> current) merge,
) {
  return impl.mergeJsonFile(path, merge);
}
