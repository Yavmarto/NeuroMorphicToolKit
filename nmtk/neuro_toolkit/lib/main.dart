import 'dart:async';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/src/features/app/presentation/command_provider.dart';
import 'package:neuro_toolkit/screens/first_run_setup_screen.dart';
import 'package:neuro_toolkit/screens/server_setup.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

/// Root widget that runs the launcher bootstrap probe and either routes into
/// the main app shell or shows the connect/setup flow.
///
/// All bootstrap state is owned by [launcherBootstrapProvider]; this widget
/// has zero [setState] calls and delegates every side-effect to the notifier.
class LauncherBootstrapHost extends ConsumerWidget {
  const LauncherBootstrapHost({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(settingsProvider);
    final settings = settingsState.value;

    if (settings == null) {
      return const Scaffold(body: Center(child: _BootstrapLoadingView()));
    }

    final bootstrapAsync = ref.watch(launcherBootstrapProvider);

    return NmtkZetaTheme.wrap(
      builder: (context, light, dark, mode) => MaterialApp(
        title: 'NeuroToolkit',
        theme:
            settings.isHighContrast ? AppTheme.highContrastLightTheme : light,
        darkTheme:
            settings.isHighContrast ? AppTheme.highContrastDarkTheme : dark,
        themeMode: settings.isHighContrast ? settings.themeMode : mode,
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
        // Wrapped here (inside `home`) rather than in the `builder` above --
        // `home`'s widget becomes the Navigator's initial route page, a
        // descendant of that Navigator's Overlay. `builder`'s `child` IS the
        // Navigator, so a SelectionArea there sits ABOVE the Overlay, and
        // SelectableRegion's `Overlay.of(context)` ancestor lookup fails
        // ("No Overlay widget found").
        home: SelectionArea(
          child: bootstrapAsync.when(
            loading: () => Scaffold(
              body: Center(
                child: _BootstrapLoadingView(
                  targetHost: settings.launcherControlApiBaseUrl,
                ),
              ),
            ),
            error: (_, __) => _buildSetupScreen(ref, null),
            data: (data) {
              if (data.isReady) {
                // Hand off to the main app shell inside a new ProviderScope that
                // injects the resolved bootstrap state and control API service.
                return ProviderScope(
                  overrides: [
                    launcherBootstrapStateProvider
                        .overrideWithValue(data.bootstrapState!),
                    controlApiServiceProvider
                        .overrideWithValue(data.controlApiService!),
                  ],
                  child: const NeuroToolkitApp(),
                );
              }
              return _buildSetupScreen(ref, data);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSetupScreen(WidgetRef ref, LauncherBootstrapData? data) {
    final controlApiInput = data?.suggestedInstallHost ??
        data?.controlApiService?.baseUri.host ??
        '';
    return FirstRunSetupScreen(
      requirePython: false,
      requireLauncher: true,
      launcherMessage: data?.setupMessage,
      launcherInitialValue: controlApiInput,
      onLauncherConnect: (host) =>
          ref.read(launcherBootstrapProvider.notifier).saveAndRetry(host),
      allowLauncherConnect: true,
      launcherSetupAvailable:
          data?.bootstrapState != null && data?.controlApiService != null,
      launcherSetupUnavailableMessage:
          'Set the launcher control API host first. Once this device can reach a '
          'launcher server, you can provision a new backend from the same screen.',
      initialLauncherStep:
          data?.bootstrapState != null && data?.controlApiService != null
              ? ServerSetupMode.setup
              : ServerSetupMode.connect,
      launcherSetupInitialHost: data?.suggestedInstallHost,
      onLauncherSetupCompleted: () =>
          ref.read(launcherBootstrapProvider.notifier).saveAndRetry(''),
    );
  }
}

class NeuroToolkitApp extends ConsumerWidget {
  const NeuroToolkitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsState = ref.watch(settingsProvider);
    final settings = settingsState.value;
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final router = ref.watch(goRouterProvider);

    return NmtkZetaTheme.wrap(
      builder: (context, light, dark, mode) => MaterialApp.router(
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

/// Shows elapsed time and the target host while `_runBootstrap()` polls —
/// that probe is bounded (up to ~20s per attempt, occasionally two attempts
/// back to back) but a single static message for the whole wait reads as
/// frozen. Ticking seconds makes an already-bounded wait legible instead.
class _BootstrapLoadingView extends StatefulWidget {
  const _BootstrapLoadingView({this.targetHost});

  final String? targetHost;

  @override
  State<_BootstrapLoadingView> createState() => _BootstrapLoadingViewState();
}

class _BootstrapLoadingViewState extends State<_BootstrapLoadingView> {
  late final Timer _timer;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _elapsedSeconds++);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.targetHost?.trim();
    final base = target != null && target.isNotEmpty
        ? 'Connecting to $target…'
        : 'Connecting to the launcher control API…';
    final message = _elapsedSeconds < 15
        ? '$base ($_elapsedSeconds s)'
        : '$base ($_elapsedSeconds s)\n\nFirst-time connections can take up '
            'to a minute while the server checks itself and starts up.';
    return NmtkShellReadinessStateView.fromState(
      NmtkShellReadinessState.warmingUp,
      message: message,
    );
  }
}
