import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/app_provider.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/providers/teensy_deploy_provider.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/routing/router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final analytics = AnalyticsService();
  await analytics.init();

  final settings = SettingsProvider();
  await settings.init();

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
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProxyProvider<SettingsProvider, ModuleProvider>(
          create: (_) => ModuleProvider()..updateSettingsProvider(settings),
          update: (_, settings, moduleProvider) {
            return moduleProvider!..updateSettingsProvider(settings);
          },
        ),
        Provider.value(value: analytics),
        ChangeNotifierProvider(create: (_) => TeensyDeployProvider()),
      ],
      child: const NeuroToolkitApp(),
    ),
  );
}

class NeuroToolkitApp extends StatelessWidget {
  const NeuroToolkitApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return MaterialApp.router(
      title: 'NeuroToolkit',
      themeMode: settings.themeMode,
      theme: settings.isHighContrast
          ? AppTheme.highContrastLightTheme
          : AppTheme.lightTheme,
      darkTheme: settings.isHighContrast
          ? AppTheme.highContrastDarkTheme
          : AppTheme.darkTheme,
      routerConfig: goRouter,
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
