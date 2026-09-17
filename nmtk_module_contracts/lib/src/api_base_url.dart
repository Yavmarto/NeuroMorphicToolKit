import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Resolves the base URL for NMTK module API clients from dart-define values.
///
/// Priority order:
///   1. `SUITE_API_URL` dart-define — overrides everything (suite-level proxy)
///   2. `API_BASE_URL` dart-define — per-module override
///   3. Web build — returns relative [apiPath] (same-origin)
///   4. Android emulator — `http://10.0.2.2:<defaultPort><apiPath>`
///   5. Default — `http://localhost:<defaultPort><apiPath>`
///
/// API key is read from the `API_KEY` dart-define.
///
/// Usage in a service constructor:
/// ```dart
/// ApiClient() : _baseUrl = NmtkApiBaseUrl.resolve(
///   apiPath: '/api/neurobench',
///   defaultPort: 8003,
/// );
/// ```
abstract final class NmtkApiBaseUrl {
  /// Returns the resolved HTTP base URL for [apiPath] at [defaultPort].
  ///
  /// [isWebOverride] and [platformOverride] exist for testing only.
  static String resolve({
    required String apiPath,
    required int defaultPort,
    bool? isWebOverride,
    TargetPlatform? platformOverride,
  }) {
    const suiteUrl = String.fromEnvironment('SUITE_API_URL');
    if (suiteUrl.isNotEmpty) return '$suiteUrl$apiPath';

    const apiUrl = String.fromEnvironment('API_BASE_URL');
    if (apiUrl.isNotEmpty) return '$apiUrl$apiPath';

    final isWeb = isWebOverride ?? kIsWeb;
    if (isWeb) return apiPath;

    final platform = platformOverride ?? defaultTargetPlatform;
    if (platform == TargetPlatform.android) {
      return 'http://10.0.2.2:$defaultPort$apiPath';
    }

    return 'http://localhost:$defaultPort$apiPath';
  }

  /// API key from the `API_KEY` dart-define. Empty string if not set.
  static String get apiKey => const String.fromEnvironment('API_KEY');
}
