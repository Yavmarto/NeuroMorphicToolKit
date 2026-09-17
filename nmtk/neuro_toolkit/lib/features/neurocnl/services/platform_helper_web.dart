// ignore_for_file: deprecated_member_use

/// Web implementation using dart:html.
library;

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:neuro_toolkit/features/neurocnl/services/platform_download_result.dart';

Future<DownloadResult> downloadFile(
  String filename,
  String content,
  String mime,
) async {
  try {
    final blob = html.Blob([content], mime);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..style.display = 'none';
    final body = html.document.body;
    if (body == null) {
      html.Url.revokeObjectUrl(url);
      return const DownloadResult(
        status: DownloadStatus.fallback,
        message: 'Browser body is unavailable for file download.',
      );
    }

    body.append(anchor);
    anchor.click();
    anchor.remove();
    Future<void>.delayed(const Duration(seconds: 1), () {
      html.Url.revokeObjectUrl(url);
    });

    return const DownloadResult(status: DownloadStatus.downloaded);
  } catch (error) {
    return DownloadResult(
      status: DownloadStatus.failed,
      message: 'Automatic download failed: $error',
    );
  }
}

Future<DownloadResult> downloadBytes(
  String filename,
  Uint8List bytes,
  String mime,
) async {
  try {
    final blob = html.Blob([bytes], mime);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..style.display = 'none';
    final body = html.document.body;
    if (body == null) {
      html.Url.revokeObjectUrl(url);
      return const DownloadResult(
        status: DownloadStatus.fallback,
        message: 'Browser body is unavailable for file download.',
      );
    }

    body.append(anchor);
    anchor.click();
    anchor.remove();
    Future<void>.delayed(const Duration(seconds: 1), () {
      html.Url.revokeObjectUrl(url);
    });

    return const DownloadResult(status: DownloadStatus.downloaded);
  } catch (error) {
    return DownloadResult(
      status: DownloadStatus.failed,
      message: 'Automatic download failed: $error',
    );
  }
}

Future<void> copyToClipboard(String text) async {
  await html.window.navigator.clipboard?.writeText(text);
}

Future<bool> openUrl(String url) async {
  try {
    html.window.location.assign(url);
    return true;
  } catch (_) {
    return false;
  }
}

String? getOrigin() {
  return html.window.location.origin;
}
