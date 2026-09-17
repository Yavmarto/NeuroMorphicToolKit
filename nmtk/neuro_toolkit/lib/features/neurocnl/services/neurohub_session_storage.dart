import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class NeurohubTokenStorage {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> delete();
}

class PlatformNeurohubTokenStorage implements NeurohubTokenStorage {
  const PlatformNeurohubTokenStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const _tokenKey = 'neurohub.githubAccessToken.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _tokenKey);

  @override
  Future<void> write(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> delete() => _storage.delete(key: _tokenKey);
}

abstract class NeurohubExternalLinkLauncher {
  Future<bool> open(String url);
}
