import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final analytics = AnalyticsService();
  await analytics.init();

  final settings = SettingsProvider(analyticsService: analytics);
  await settings.init();
  final bootstrap = await LauncherControlBootstrapService().ensureReady();
  final controlApiService = ControlApiService(baseUri: bootstrap.baseUri);

  // Global error handlers for crash reporting
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    analytics.logCrash(details.exception, details.stack ?? StackTrace.empty);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    analytics.logCrash(error, stack);
    return true;
  };

  runApp(
    ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(analytics),
        settingsStateProvider.overrideWith((ref) => settings),
        launcherBootstrapStateProvider.overrideWithValue(bootstrap),
        controlApiServiceProvider.overrideWithValue(controlApiService),
      ],
      child: const NeuroToolkitApp(),
    ),
  );
}

class NeuroToolkitApp extends ConsumerWidget {
  const NeuroToolkitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsStateProvider);
    final router = ref.watch(goRouterProvider);

    return MaterialApp.router(
      title: 'NeuroToolkit',
      themeMode: settings.themeMode,
      theme: settings.isHighContrast
          ? AppTheme.highContrastLightTheme
          : AppTheme.lightTheme,
      darkTheme: settings.isHighContrast
          ? AppTheme.highContrastDarkTheme
          : AppTheme.darkTheme,
      routerConfig: router,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(settings.fontSizeFactor),
          ),
          child: child!,
        );
      },
    );
  }
}
