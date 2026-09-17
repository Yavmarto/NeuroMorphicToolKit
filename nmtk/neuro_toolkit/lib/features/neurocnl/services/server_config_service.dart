import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/services/workspace_cache_storage.dart';

/// Lightweight persistence wrapper for feature workspace data.
///
/// NOTE: Requires the `shared_preferences` package in pubspec.yaml.
class ServerConfigService {
  ServerConfigService._();

  static const workspaceCacheKey = 'neurocnl_workspace_state_v1';
  static SharedPreferences? _prefs;
  static Future<SharedPreferences>? _initialization;
  static WorkspaceCacheStorage? _workspaceCacheStorage;
  static String? _workspaceCacheValue;
  static WorkspaceCacheStorage? _debugWorkspaceCacheStorage;
  static bool _hasDebugWorkspaceCacheStorage = false;

  static Future<SharedPreferences> _ensurePrefs() {
    final prefs = _prefs;
    if (prefs != null) {
      return Future<SharedPreferences>.value(prefs);
    }

    return _initialization ??= SharedPreferences.getInstance().then((
      prefs,
    ) async {
      _prefs = prefs;
      await _initializeWorkspaceCache(prefs);
      return prefs;
    });
  }

  static Future<void> _initializeWorkspaceCache(SharedPreferences prefs) async {
    try {
      final storage = _hasDebugWorkspaceCacheStorage
          ? _debugWorkspaceCacheStorage
          : createWorkspaceCacheStorage();
      _workspaceCacheStorage = storage;
      if (storage == null) {
        return;
      }

      final legacy = prefs.getString(workspaceCacheKey);
      if (legacy != null) {
        await storage.write(legacy);
        final migrated = await storage.read();
        if (migrated != legacy) {
          throw StateError('Workspace cache migration verification failed.');
        }
        final removed = await prefs.remove(workspaceCacheKey);
        if (!removed && prefs.containsKey(workspaceCacheKey)) {
          throw StateError('Legacy workspace cache could not be removed.');
        }
        _workspaceCacheValue = legacy;
        return;
      }

      _workspaceCacheValue = await storage.read();
    } on Object catch (error) {
      // Preserve the legacy value when migration cannot complete. The caller
      // must still be able to start and use the verified launcher service.
      _workspaceCacheStorage = null;
      _workspaceCacheValue = prefs.getString(workspaceCacheKey);
      debugPrint(
        'Workspace cache migration deferred '
        '(${error.runtimeType}).',
      );
    }
  }

  /// Must be awaited before any other access.
  static Future<void> initialize() async {
    await _ensurePrefs();
  }

  /// The [SharedPreferences] instance (available after [initialize]).
  static SharedPreferences get instance =>
      _prefs ??
      (throw StateError(
        'ServerConfigService.initialize() must complete before instance access.',
      ));

  /// Generic method to save a string to disk (e.g. JSON).
  static Future<void> setString(String key, String value) async {
    final prefs = await _ensurePrefs();
    if (key == workspaceCacheKey && _workspaceCacheStorage != null) {
      await _workspaceCacheStorage!.write(value);
      _workspaceCacheValue = value;
      return;
    }
    await prefs.setString(key, value);
  }

  /// Generic method to retrieve a string from disk.
  static String? getString(String key) {
    if (key == workspaceCacheKey && _workspaceCacheStorage != null) {
      return _workspaceCacheValue;
    }
    return _prefs?.getString(key);
  }

  static final Map<String, Future<void>> _pendingMerges = {};

  /// Atomically read-modify-write the JSON object stored at [key]: decodes
  /// whatever is currently there (or `{}` if absent/malformed), passes it to
  /// [merge], and writes the result back — serialized per key so two
  /// independent callers writing to the same key can't race a read against
  /// each other's write and silently drop one's update. Each caller only
  /// needs to know which top-level fields it owns; anything else in
  /// [merge]'s input is whatever the other writer(s) most recently wrote.
  static Future<void> mergeJsonString(
    String key,
    Map<String, Object?> Function(Map<String, Object?> current) merge,
  ) {
    final previous = _pendingMerges[key] ?? Future<void>.value();
    final next = previous.catchError((_) {}).then((_) async {
      final prefs = await _ensurePrefs();
      Map<String, Object?> current = {};
      final cachedRaw = getString(key);
      if (cachedRaw != null) {
        try {
          final decoded = jsonDecode(cachedRaw);
          if (decoded is Map) current = Map<String, Object?>.from(decoded);
        } catch (_) {
          // Malformed cached JSON — start from an empty object.
        }
      }
      final encoded = jsonEncode(merge(current));
      if (key == workspaceCacheKey && _workspaceCacheStorage != null) {
        await _workspaceCacheStorage!.write(encoded);
        _workspaceCacheValue = encoded;
      } else {
        await prefs.setString(key, encoded);
      }
    });
    _pendingMerges[key] = next;
    return next;
  }

  /// Reset cached prefs between frontend tests.
  static void debugResetForTests() {
    _prefs = null;
    _initialization = null;
    _workspaceCacheStorage = null;
    _workspaceCacheValue = null;
    _debugWorkspaceCacheStorage = null;
    _hasDebugWorkspaceCacheStorage = false;
    _pendingMerges.clear();
  }

  @visibleForTesting
  static void debugUseWorkspaceCacheStorage(WorkspaceCacheStorage? storage) {
    _debugWorkspaceCacheStorage = storage;
    _hasDebugWorkspaceCacheStorage = true;
  }
}
