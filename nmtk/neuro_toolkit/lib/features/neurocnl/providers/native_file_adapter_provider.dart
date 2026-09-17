import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/services/file_adapter.dart';
import 'package:neuro_toolkit/features/neurocnl/services/file_picker_native_file_backend.dart';

final nativeFileAdapterProvider = Provider<FileAdapter>((ref) {
  return FileAdapter(FilePickerNativeFileBackend());
});
