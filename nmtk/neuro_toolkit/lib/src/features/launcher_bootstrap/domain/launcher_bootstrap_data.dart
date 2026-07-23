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
    this.suggestedInstallHost,
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
    String? suggestedInstallHost,
  }) {
    return LauncherBootstrapData._(
      isReady: false,
      bootstrapState: bootstrapState,
      controlApiService: controlApiService,
      setupMessage: message,
      suggestedInstallHost: suggestedInstallHost,
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

  /// The host/IP the user typed that turned out to be reachable but with no
  /// launcher server installed on it — a clean provisioning target. When
  /// set, the setup wizard should default to it (target: remote host)
  /// instead of "This machine." Distinct from [controlApiService], which in
  /// this case points at this machine's own orchestrator, not this host.
  final String? suggestedInstallHost;
}
