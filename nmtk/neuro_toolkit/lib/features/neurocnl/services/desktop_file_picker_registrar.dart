import 'package:flutter/foundation.dart';

import 'package:neuro_toolkit/features/neurocnl/services/desktop_file_picker_registrar_stub.dart'
    if (dart.library.io) 'desktop_file_picker_registrar_io.dart'
    as impl;

bool registerDesktopFilePicker(TargetPlatform platform) {
  return impl.registerDesktopFilePicker(platform);
}
