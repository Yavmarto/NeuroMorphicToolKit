import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:neuro_toolkit/providers/app_provider.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/providers/workspace_provider.dart';
import 'package:neuro_toolkit/routing/router.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';

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

final appStateProvider = ChangeNotifierProvider<AppProvider>((ref) {
  return AppProvider();
});

final moduleStateProvider = ChangeNotifierProvider<ModuleProvider>((ref) {
  final settings = ref.read(settingsStateProvider);
  return ModuleProvider()..updateSettingsProvider(settings);
});

final workspaceStateProvider = ChangeNotifierProvider<WorkspaceProvider>((ref) {
  return WorkspaceProvider();
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
