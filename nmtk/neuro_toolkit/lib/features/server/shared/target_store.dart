import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class ConnectSecretStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformConnectSecretStorage implements ConnectSecretStorage {
  const PlatformConnectSecretStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// One server this app has logged into: enough to auto-reconnect on app
/// open. There is no shared `adminToken` bearer secret here (see the CEL-25
/// plan document) — every client, including a second device, logs in
/// independently against `/api/launcher/auth/login`.
class ConnectTarget {
  const ConnectTarget({
    required this.host,
    required this.appUsername,
    this.sessionToken = '',
    this.credential = '',
    this.updatedAt,
  });

  final String host;
  final String appUsername;

  /// The live session token from the most recent login. Not what reconnect
  /// replays — the backend's login endpoint only accepts a password.
  final String sessionToken;

  /// The app password this client logged in with. Persisted in secure
  /// storage so `ConnectService.reconnect` can re-login on app open without
  /// re-prompting. Kept out of [toJson] so it never reaches plain prefs.
  final String credential;

  final DateTime? updatedAt;

  ConnectTarget copyWith({
    String? sessionToken,
    String? credential,
    DateTime? updatedAt,
  }) => ConnectTarget(
    host: host,
    appUsername: appUsername,
    sessionToken: sessionToken ?? this.sessionToken,
    credential: credential ?? this.credential,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, dynamic> toJson() => {
    'host': host,
    'appUsername': appUsername,
    'updatedAt': updatedAt?.toIso8601String(),
  };

  static ConnectTarget fromJson(
    Map<String, dynamic> json, {
    String sessionToken = '',
    String credential = '',
  }) => ConnectTarget(
    host: json['host'] as String? ?? '',
    appUsername: json['appUsername'] as String? ?? '',
    sessionToken: sessionToken,
    credential: credential,
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
  );
}

/// Persists which servers this app has logged into: a trimmed, renamed
/// replacement for `deployment_persistence.dart` scoped to connect-only
/// state. Host/username are plain prefs; the session token and the app
/// credential (password) are the secrets, kept in secure storage.
class TargetStore {
  TargetStore({
    required SharedPreferences preferences,
    ConnectSecretStorage secureStorage = const PlatformConnectSecretStorage(),
  }) : _preferences = preferences,
       _secureStorage = secureStorage;

  static const _targetsKey = 'connect.targets.v1';
  static const _tokenPrefix = 'connect.sessionToken.v1.';
  static const _credentialPrefix = 'connect.credential.v1.';

  final SharedPreferences _preferences;
  final ConnectSecretStorage _secureStorage;

  Future<List<ConnectTarget>> loadTargets() async {
    final entries = _loadEntries();
    final targets = <ConnectTarget>[];
    for (final entry in entries) {
      final host = entry['host'] as String? ?? '';
      if (host.isEmpty) continue;
      final token = await _secureStorage.read('$_tokenPrefix$host') ?? '';
      final credential =
          await _secureStorage.read('$_credentialPrefix$host') ?? '';
      targets.add(
        ConnectTarget.fromJson(
          entry,
          sessionToken: token,
          credential: credential,
        ),
      );
    }
    return targets;
  }

  /// The most recently used target, for auto-reconnect on app open.
  Future<ConnectTarget?> loadLastTarget() async {
    final targets = await loadTargets();
    if (targets.isEmpty) return null;
    targets.sort((a, b) {
      final aAt = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
    return targets.first;
  }

  /// Host-only lookup for debug/profile auto-connect (CEL-226).
  ///
  /// Reads plain prefs only — no keychain/Keystore round-trip — so mobile
  /// cold start does not block on secure storage before the health probe.
  Future<String?> loadLastHost() async {
    final entries = _loadEntries();
    if (entries.isEmpty) return null;
    entries.sort((a, b) {
      final aAt =
          DateTime.tryParse(a['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bAt =
          DateTime.tryParse(b['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
    final host = entries.first['host'] as String? ?? '';
    return host.isEmpty ? null : host;
  }

  Future<void> saveTarget(ConnectTarget target) async {
    final withTimestamp = target.copyWith(updatedAt: DateTime.now());
    final entries = _loadEntries();
    final index = entries.indexWhere(
      (entry) => entry['host'] == withTimestamp.host,
    );
    final entry = withTimestamp.toJson();
    if (index == -1) {
      entries.add(entry);
    } else {
      entries[index] = entry;
    }
    await _preferences.setString(_targetsKey, jsonEncode(entries));
    if (withTimestamp.sessionToken.isNotEmpty) {
      await _secureStorage.write(
        '$_tokenPrefix${withTimestamp.host}',
        withTimestamp.sessionToken,
      );
    }
    if (withTimestamp.credential.isNotEmpty) {
      await _secureStorage.write(
        '$_credentialPrefix${withTimestamp.host}',
        withTimestamp.credential,
      );
    }
  }

  Future<void> forgetTarget(String host) async {
    final entries = _loadEntries()
        .where((entry) => entry['host'] != host)
        .toList();
    await _preferences.setString(_targetsKey, jsonEncode(entries));
    await _secureStorage.delete('$_tokenPrefix$host');
    await _secureStorage.delete('$_credentialPrefix$host');
  }

  List<Map<String, dynamic>> _loadEntries() {
    final raw = _preferences.getString(_targetsKey);
    if (raw == null || raw.isEmpty) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List<dynamic>) return [];
    return decoded.whereType<Map<String, dynamic>>().toList();
  }
}
