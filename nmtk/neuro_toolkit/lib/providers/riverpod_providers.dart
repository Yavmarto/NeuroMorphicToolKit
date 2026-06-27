import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:neuro_toolkit/routing/router.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/environment_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';

// Re-export generated Riverpod providers for convenience
export 'package:neuro_toolkit/src/features/app/presentation/app_notifier.dart'
    show appProvider;
export 'package:neuro_toolkit/src/features/module/presentation/module_notifier.dart'
    show moduleProvider;
export 'package:neuro_toolkit/src/features/workspace/presentation/workspace_notifier.dart'
    show workspaceProvider;
export 'package:neuro_toolkit/src/features/settings/presentation/settings_notifier.dart'
    show settingsProvider;
export 'package:neuro_toolkit/src/features/environment/presentation/environment_notifier.dart'
    show environmentProvider;
export 'package:neuro_toolkit/src/features/environment/presentation/environment_package_notifier.dart'
    show
        environmentPackageProvider,
        environmentExportProvider,
        EnvironmentPackageNotifier,
        EnvironmentExportNotifier;
export 'package:neuro_toolkit/src/features/environment/domain/environment_package_state.dart'
    show EnvironmentPackageState, EnvironmentExportState;
export 'package:neuro_toolkit/src/features/deployment/presentation/deployment_notifier.dart'
    show backendDeploymentProvider;
export 'package:neuro_toolkit/src/features/python_install/presentation/python_install_notifier.dart'
    show pythonInstallProvider, PythonInstallNotifier;
export 'package:neuro_toolkit/src/features/python_install/domain/python_install_state.dart'
    show PythonInstallState;
export 'package:neuro_toolkit/src/features/launcher_bootstrap/presentation/launcher_bootstrap_notifier.dart'
    show launcherBootstrapProvider, LauncherBootstrapNotifier;
export 'package:neuro_toolkit/src/features/launcher_bootstrap/domain/launcher_bootstrap_data.dart'
    show LauncherBootstrapData;

final analyticsServiceProvider = Provider<AnalyticsService>((ref) {
  throw UnimplementedError(
    'analyticsServiceProvider must be overridden at app bootstrap.',
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

final environmentApiServiceProvider = Provider<EnvironmentApiService>((ref) {
  return EnvironmentApiService(
    controlApi: ref.watch(controlApiServiceProvider),
  );
});

// The Teensy / PYNQ / Akida deploy providers were relocated to the Neurochip
// module frontend in ADR-claude/0007. They now live in
// `Neurochip/frontend/lib/providers/riverpod_providers.dart`.

final goRouterProvider = Provider<GoRouter>((ref) {
  final router = createGoRouter();
  ref.onDispose(router.dispose);
  return router;
});
