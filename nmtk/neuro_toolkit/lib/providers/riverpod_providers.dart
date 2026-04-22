import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:neuro_toolkit/providers/akida_deploy_provider.dart';
import 'package:neuro_toolkit/providers/app_provider.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/pynq_deploy_provider.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/providers/teensy_deploy_provider.dart';
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

final teensyDeployStateProvider =
    ChangeNotifierProvider<TeensyDeployProvider>((ref) {
  return TeensyDeployProvider();
});

final pynqDeployStateProvider =
    ChangeNotifierProvider<PynqDeployProvider>((ref) {
  return PynqDeployProvider();
});

final akidaDeployStateProvider =
    ChangeNotifierProvider<AkidaDeployProvider>((ref) {
  return AkidaDeployProvider();
});

final goRouterProvider = Provider<GoRouter>((ref) {
  final appState = ref.read(appStateProvider);
  final router = createGoRouter(appState);
  ref.onDispose(router.dispose);
  return router;
});
