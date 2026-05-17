import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:neuro_toolkit/providers/app_provider.dart';
import 'package:neuro_toolkit/providers/backend_deployment_provider.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/providers/workspace_provider.dart';
import 'package:neuro_toolkit/routing/router.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
import 'package:neuro_toolkit/services/preferences_service.dart';

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  throw UnimplementedError(
    'analyticsServiceProvider must be overridden at app bootstrap.',
  );
});

final settingsStateProvider = ChangeNotifierProvider<SettingsProvider>((ref) {
  throw UnimplementedError(
    'settingsStateProvider must be overridden at app bootstrap.',
  );
});

final launcherBootstrapStateProvider = Provider<LauncherBootstrapState>((ref) {
  return LauncherBootstrapState.ready(ControlApiService.resolveBaseUri());
});

final controlApiServiceProvider = Provider<ControlApiService>((ref) {
  final bootstrapState = ref.watch(launcherBootstrapStateProvider);
  return ControlApiService(
    baseUri: bootstrapState.baseUri,
    analyticsService: ref.watch(analyticsServiceProvider),
  );
});

/// Provides the [PreferencesService] instance.
///
/// Override at bootstrap (or in tests) to inject a custom instance:
/// ```dart
/// preferencesServiceProvider.overrideWithValue(
///   PreferencesService(basePath: tempDir.path),
/// )
/// ```
final preferencesServiceProvider = Provider<PreferencesService>((ref) {
  return PreferencesService();
});

final appStateProvider = ChangeNotifierProvider<AppProvider>((ref) {
  return AppProvider(preferencesService: ref.read(preferencesServiceProvider));
});

final moduleStateProvider = ChangeNotifierProvider<ModuleProvider>((ref) {
  final settings = ref.read(settingsStateProvider);
  final controlApiService = ref.read(controlApiServiceProvider);
  final bootstrapState = ref.read(launcherBootstrapStateProvider);
  return ModuleProvider(
    controlApiService: controlApiService,
    bootstrapState: bootstrapState,
  )..updateSettingsProvider(settings);
});

final workspaceStateProvider = ChangeNotifierProvider<WorkspaceProvider>((ref) {
  return WorkspaceProvider(
    controlApiService: ref.read(controlApiServiceProvider),
    bootstrapState: ref.read(launcherBootstrapStateProvider),
  );
});

final backendDeploymentStateProvider =
    ChangeNotifierProvider<BackendDeploymentProvider>((ref) {
  return BackendDeploymentProvider(
    controlApiService: ref.read(controlApiServiceProvider),
  );
});

// The Teensy / PYNQ / Akida deploy providers were relocated to the Neurochip
// module frontend in ADR-claude/0007. They now live in
// `Neurochip/frontend/lib/providers/riverpod_providers.dart`.

final goRouterProvider = Provider<GoRouter>((ref) {
  final appState = ref.read(appStateProvider);
  final router = createGoRouter(appState);
  ref.onDispose(router.dispose);
  return router;
});
