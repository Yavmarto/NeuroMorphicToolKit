import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';

/// Result of the launcher bootstrap probe.
///
/// Either the app is [ready] and the main shell can be shown, or it
/// [needsSetup] and the setup/connect UI should be presented instead.
class LauncherBootstrapData {
  const LauncherBootstrapData._({
    required this.isReady,
    this.bootstrapState,
    this.controlApiService,
    this.setupMessage,
  });

  factory LauncherBootstrapData.ready({
    required LauncherBootstrapState bootstrapState,
    required ControlApiService controlApiService,
  }) {
    return LauncherBootstrapData._(
      isReady: true,
      bootstrapState: bootstrapState,
      controlApiService: controlApiService,
    );
  }

  factory LauncherBootstrapData.needsSetup({
    LauncherBootstrapState? bootstrapState,
    ControlApiService? controlApiService,
    String? message,
  }) {
    return LauncherBootstrapData._(
      isReady: false,
      bootstrapState: bootstrapState,
      controlApiService: controlApiService,
      setupMessage: message,
    );
  }

  /// Whether the backend is fully ready and the main app shell can be shown.
  final bool isReady;

  /// Populated when the launcher control API is reachable (even if not ready).
  final LauncherBootstrapState? bootstrapState;

  /// Populated when [bootstrapState] is not null and the API responded.
  final ControlApiService? controlApiService;

  /// Human-readable message shown in the setup/connect screen.
  final String? setupMessage;
}
