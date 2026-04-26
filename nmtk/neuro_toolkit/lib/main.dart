import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
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

    return ShadApp.router(
      title: 'NeuroToolkit',
      // Shadcn layer — controls Shadcn components suite-wide.
      theme: NmtkShadTheme.light,
      darkTheme: NmtkShadTheme.dark,
      // Material 3 layer — controls native Flutter widgets.
      materialThemeBuilder: (_, __) => settings.isHighContrast
          ? AppTheme.highContrastDarkTheme
          : AppTheme.darkTheme,
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: (BuildContext ctx, Widget? child) {
        // Apply font scaling and inject ShadToaster so NmtkToasts can find it
        // in the widget tree via ShadToaster.of(context).
        return MediaQuery(
          data: MediaQuery.of(ctx).copyWith(
            textScaler: TextScaler.linear(settings.fontSizeFactor),
          ),
          child: ShadToaster(child: child!),
        );
      },
    );
  }
}
