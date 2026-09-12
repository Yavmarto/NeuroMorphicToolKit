import 'package:flutter/foundation.dart';

/// Build-mode policy for the connect flow.
///
/// Release builds require app-account credentials (CEL-198). Debug and profile
/// builds probe the dev server and connect without a sign-in form (CEL-171,
/// restored for non-release in CEL-220).
abstract final class ConnectBuildPolicy {
  /// True only for release builds — debug/profile skip credential auth.
  static bool get requiresCredentialAuth => kReleaseMode;

  /// Default dev backend host baked into non-release builds. Override with
  /// `--dart-define=NMTK_DEV_SERVER_HOST=…` when building profile/debug APKs
  /// or macOS bundles for another machine.
  static const String defaultDevServerHost = String.fromEnvironment(
    'NMTK_DEV_SERVER_HOST',
    defaultValue: '192.168.2.90',
  );
}
