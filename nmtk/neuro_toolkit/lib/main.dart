import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/app_provider.dart';
import 'package:neuro_toolkit/routing/router.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppProvider()),
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
