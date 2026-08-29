/// Native (macOS/Windows/Linux/iOS/Android) implementation.
library;

/// Selected by the conditional import in platform_helper.dart when
/// dart:html is NOT available.
import 'package:flutter/services.dart';

import 'package:neuro_toolkit/features/neurocnl/services/platform_download_result.dart';

Future<DownloadResult> downloadFile(
  String filename,
  String content,
  String mime,
) async {
  return const DownloadResult(
    status: DownloadStatus.fallback,
    message:
        'Native desktop downloads should use the file adapter save flow instead of browser-style download handling.',
  );
}

Future<DownloadResult> downloadBytes(
  String filename,
  Uint8List bytes,
  String mime,
) async {
  return const DownloadResult(
    status: DownloadStatus.fallback,
    message:
        'Native desktop downloads should use the file adapter save flow instead of browser-style download handling.',
  );
}

Future<void> copyToClipboard(String text) async {
  await Clipboard.setData(ClipboardData(text: text));
}

Future<bool> openUrl(String url) async {
  return false;
}

String? getOrigin() {
  // No browser origin on native.
  return null;
}
