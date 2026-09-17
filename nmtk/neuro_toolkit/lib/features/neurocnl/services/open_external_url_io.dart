import 'dart:io';

/// Hands [url] to the OS default browser via the `open` command. macOS-only
/// today (matches this app's current desktop target) — returns `false`
/// without side effects on any other platform.
Future<bool> openExternalUrlImpl(String url) async {
  if (!Platform.isMacOS) {
    return false;
  }
  try {
    final result = await Process.run('open', [url]);
    return result.exitCode == 0;
  } catch (_) {
    return false;
  }
}
