import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the GitHub access token obtained from the Neurohub device flow.
///
/// Neurohub's device-flow session store is deliberately in-memory and
/// ephemeral (see `neurohub/app/routers/github_auth.py`), so the token must
/// be kept client-side for it to survive an app restart. This storage mirrors
/// how the launcher persists its own session token: written to the platform
/// secure store, never to plaintext app data.
abstract class GithubTokenStorage {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> delete();
}

/// Default [GithubTokenStorage] backed by the platform secure store.
class SecureGithubTokenStorage implements GithubTokenStorage {
  const SecureGithubTokenStorage({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  static const String tokenKey = 'neurohub.githubAccessToken.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: tokenKey);

  @override
  Future<void> write(String token) =>
      _storage.write(key: tokenKey, value: token);

  @override
  Future<void> delete() => _storage.delete(key: tokenKey);
}
