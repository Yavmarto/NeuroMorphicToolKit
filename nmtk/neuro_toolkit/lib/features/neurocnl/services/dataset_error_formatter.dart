import 'dart:convert';

import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

/// Turns a dataset import/download failure into a user-facing message.
String describeDatasetActionError(Object e, {required String action}) {
  if (e is ApiException) {
    if (e.statusCode == 405) {
      return '$action failed: the backend does not support local dataset import yet. '
          'Restart suite_api or the neurocnl backend, then try again.';
    }
    // Try to surface the backend's human-readable `detail` field.
    try {
      final decoded = jsonDecode(e.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) {
          return '$action failed: ${detail.trim()}';
        }
      }
    } catch (_) {
      // body is not JSON — fall through.
    }
    final raw = e.body.trim();
    return raw.isNotEmpty
        ? '$action failed (HTTP ${e.statusCode}): $raw'
        : '$action failed (HTTP ${e.statusCode}).';
  }
  // Timed-out or network error: already has a descriptive toString.
  final msg = e.toString().trim();
  return msg.isNotEmpty
      ? '$action failed: $msg'
      : '$action failed. Check the server connection and try again.';
}
