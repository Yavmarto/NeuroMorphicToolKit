import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neurocnl_studio/services/server_config_service.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/src/features/app/presentation/command_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // NeuroCNL workspaces may contain trained weight matrices that are far too
  // large for macOS UserDefaults. Migrate that cache before any launcher
  // preference write so an unrelated workspace cannot block Quick Connect.
  await ServerConfigService.initialize();

  final analytics = AnalyticsService();
  await analytics.init();

  // Global error handlers for crash reporting
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    analytics.logCrash(details.exception, details.stack ?? StackTrace.empty);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    analytics.logCrash(error, stack);
    return true;
  };

  final container = ProviderContainer(
    overrides: [
      analyticsServiceProvider.overrideWithValue(analytics),
    ],
  );

  // Await the settings to be loaded from SharedPreferences asynchronously
  await container.read(settingsProvider.future);

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const LauncherBootstrapHost(),
    ),
  );
}

/// Compatibility wrapper retained for existing launch and widget-test entry
/// points. The application itself now has one MaterialApp and provider graph.
class LauncherBootstrapHost extends StatelessWidget {
  const LauncherBootstrapHost({super.key});

  @override
  Widget build(BuildContext context) => const NeuroToolkitApp();
}

class NeuroToolkitApp extends ConsumerWidget {
  const NeuroToolkitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(settingsProvider);
    final settings = settingsState.value;
    if (settings == null) {
      return const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    final router = ref.watch(goRouterProvider);

    return NmtkZetaTheme.wrap(
      builder: (context, light, dark, mode) => MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'NeuroToolkit',
        theme:
            settings.isHighContrast ? AppTheme.highContrastLightTheme : light,
        darkTheme:
            settings.isHighContrast ? AppTheme.highContrastDarkTheme : dark,
        themeMode: settings.isHighContrast ? settings.themeMode : mode,
        routerConfig: router,
        builder: (BuildContext ctx, Widget? child) {
          final commands = ref.watch(commandStateProvider);
          return NmtkShortcutScope(
            globalCommands: commands,
            child: MediaQuery(
              data: MediaQuery.of(ctx).copyWith(
                textScaler: TextScaler.linear(settings.fontSizeFactor),
              ),
              child: child!,
            ),
          );
        },
      ),
    );
  }
}
