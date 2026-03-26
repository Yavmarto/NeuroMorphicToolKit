import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/routing/router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final analytics = AnalyticsService();
  await analytics.init();

  final settings = SettingsProvider();
  await settings.init();

  // Global error handlers
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    analytics.logCrash(details.exception, details.stack ?? StackTrace.empty);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    analytics.logCrash(error, stack);
    return true;
  };

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ModuleProvider()),
        ChangeNotifierProvider.value(value: settings),
        Provider.value(value: analytics),
      ],
      child: const NeuroToolkitApp(),
    ),
  );
}

class NeuroToolkitApp extends StatelessWidget {
  const NeuroToolkitApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'NeuroToolkit',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      routerConfig: goRouter,
    );
  }
}
