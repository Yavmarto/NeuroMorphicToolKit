import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<void> writePickedSavePathIfNeeded(String? path, Uint8List bytes) async {
  if (path == null || path.isEmpty) {
    return;
  }

  if (!Platform.isLinux && !Platform.isWindows) {
    return;
  }

  await File(path).writeAsBytes(bytes);
}

/// Writes [bytes] straight to [path], with no picker dialog involved.
///
/// Used by autosave to keep a previously opened/saved workspace file in sync
/// without re-prompting. On a sandboxed macOS build the process only holds
/// write access to a path for as long as the security-scoped grant from the
/// picker call that produced it is alive (i.e. for the rest of the current
/// app session) — there is no persisted bookmark, so this will throw on the
/// first attempt after a fresh app launch until the user re-opens/re-saves
/// via a picker in that new session. Callers must treat a `false` return as
/// an expected, silent no-op (fall back to whatever other persistence they
/// have), not an error to surface.
Future<bool> writeToPath(String? path, Uint8List bytes) async {
  if (path == null || path.isEmpty) {
    return false;
  }
  try {
    await File(path).writeAsBytes(bytes);
    return true;
  } catch (_) {
    return false;
  }
}

final Map<String, Future<void>> _pendingFileMerges = {};

/// Reads the JSON object at [path] (if any), applies [merge], and writes the
/// result back — mirroring `ServerConfigService.mergeJsonString`'s
/// read-modify-write contract, but against a file on disk instead of a
/// SharedPreferences key. This is what lets two independent autosave writers
/// (workspace state, canvas/pipeline state) each write through to the same
/// workspace file without one's write clobbering the other's most recent
/// section — same reason `mergeJsonString` exists for the local-storage
/// cache. Serialized per-path so two triggers landing close together can't
/// race a read-then-write over each other.
///
/// Never throws — see [writeToPath]'s doc comment on why a write failure
/// here (most commonly a macOS sandbox permission lapse after an app
/// restart) must be an expected, silent no-op.
Future<bool> mergeJsonFile(
  String? path,
  Map<String, Object?> Function(Map<String, Object?> current) merge,
) async {
  if (path == null || path.isEmpty) {
    return false;
  }
  final previous = _pendingFileMerges[path] ?? Future<void>.value();
  final completer = Completer<void>();
  _pendingFileMerges[path] = previous.then((_) => completer.future);
  await previous;
  try {
    var current = <String, Object?>{};
    try {
      final file = File(path);
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          current = Map<String, Object?>.from(decoded);
        }
      }
    } catch (_) {
      // Corrupt/unreadable file on disk — merge from empty rather than
      // blocking the write; the merge function still receives whatever
      // in-memory section it owns.
    }
    final merged = merge(current);
    final encoded = '${const JsonEncoder.withIndent('  ').convert(merged)}\n';
    await File(path).writeAsBytes(utf8.encode(encoded));
    return true;
  } catch (_) {
    return false;
  } finally {
    completer.complete();
  }
}
