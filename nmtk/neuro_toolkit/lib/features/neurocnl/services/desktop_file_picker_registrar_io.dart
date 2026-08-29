import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';

bool registerDesktopFilePicker(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.linux:
      FilePickerLinux.registerWith();
      return true;
    case TargetPlatform.windows:
      FilePickerWindows.registerWith();
      return true;
    case TargetPlatform.macOS:
      FilePickerMacOS.registerWith();
      return true;
    case TargetPlatform.android:
    case TargetPlatform.fuchsia:
    case TargetPlatform.iOS:
      return false;
  }
}
