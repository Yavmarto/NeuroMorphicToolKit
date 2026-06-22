import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
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

class LauncherBootstrapHost extends ConsumerStatefulWidget {
  const LauncherBootstrapHost({super.key});

  @override
  ConsumerState<LauncherBootstrapHost> createState() =>
      _LauncherBootstrapHostState();
}

class _LauncherBootstrapHostState extends ConsumerState<LauncherBootstrapHost> {
  /// Plain string — no controller shared with child widgets to avoid the
  /// ZetaTextFormField listener-leak bug (upstream zeta_flutter never calls
  /// removeListener in dispose). ServerSetupScreen owns its controller locally.
  String _controlApiInput = '';
  LauncherBootstrapState? _bootstrapState;
  ControlApiService? _controlApiService;
  bool _backendDeploymentReady = false;
  bool _isLoading = true;
  String? _setupMessage;

  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider).value;
    var saved = settings?.launcherControlApiBaseUrl?.trim() ?? '';
    if (saved.isNotEmpty) {
      final uri = Uri.tryParse(saved);
      if (uri != null && uri.host.isNotEmpty) {
        saved = uri.host;
      }
    }
    _controlApiInput = saved;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    final settings = ref.read(settingsProvider).value;
    final explicitBaseUri =
        _configuredBaseUri(settings?.launcherControlApiBaseUrl);
    if (_isMobilePlatform && explicitBaseUri == null) {
      setState(() {
        _bootstrapState = null;
        _controlApiService = null;
        _backendDeploymentReady = false;
        _isLoading = false;
        _setupMessage =
            'Set the launcher control API host before opening the workspace.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _setupMessage = null;
    });

    final bootstrap = await LauncherControlBootstrapService(
      explicitBaseUriOverride: explicitBaseUri,
    ).ensureReady();
    if (!mounted) {
      return;
    }

    if (bootstrap.canUseControlApi) {
      final controlApiService = ControlApiService(
        baseUri: bootstrap.baseUri,
        analyticsService: ref.read(analyticsServiceProvider),
      );
      try {
        final launcherSettings = await controlApiService.fetchSettings();
        if (!mounted) {
          return;
        }
        setState(() {
          _bootstrapState = bootstrap;
          _controlApiService = controlApiService;
          _backendDeploymentReady = launcherSettings.backendDeploymentReady;
          _isLoading = false;
          _setupMessage = launcherSettings.backendDeploymentReady
              ? null
              : 'Connect to another launcher server or set up a new one here.';
        });
      } catch (error) {
        setState(() {
          _bootstrapState = null;
          _controlApiService = null;
          _backendDeploymentReady = false;
          _isLoading = false;
          _setupMessage =
              'Preflight failed: could not load launcher settings: $error';
        });
      }
      return;
    }

    setState(() {
      _bootstrapState = null;
      _controlApiService = null;
      _backendDeploymentReady = false;
      _isLoading = false;
      _setupMessage = bootstrap.message;
    });
  }

  Uri? _configuredBaseUri(String? stored) {
    final configured = ControlApiService.configuredBaseUrl.trim();
    if (configured.isNotEmpty) {
      return Uri.parse(configured);
    }
    stored = stored?.trim() ?? '';
    if (stored.isNotEmpty) {
      return Uri.parse(stored);
    }
    return null;
  }

  Future<void> _saveAndRetry() async {
    var input = _controlApiInput.trim();
    if (input.isNotEmpty) {
      if (!input.startsWith('http://') && !input.startsWith('https://')) {
        input = 'http://$input';
      }
      final uri = Uri.tryParse(input);
      if (uri != null && !uri.hasPort) {
        input = '${uri.scheme}://${uri.host}:8091${uri.path}';
      }
    }
    await ref
        .read(settingsProvider.notifier)
        .setLauncherControlApiBaseUrl(input);
    if (!mounted) {
      return;
    }
    await _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final settingsState = ref.watch(settingsProvider);
    final settings = settingsState.value;

    if (settings == null) {
      return const Scaffold(body: Center(child: _BootstrapLoadingView()));
    }
    final bootstrap = _bootstrapState;
    final controlApiService = _controlApiService;
    if (bootstrap != null && _backendDeploymentReady) {
      return ProviderScope(
        overrides: [
          launcherBootstrapStateProvider.overrideWithValue(bootstrap),
          controlApiServiceProvider.overrideWithValue(controlApiService!),
        ],
        child: const NeuroToolkitApp(),
      );
    }

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
        home: _isLoading
            ? const Scaffold(body: Center(child: _BootstrapLoadingView()))
            : FirstRunSetupScreen(
                requirePython: false,
                requireLauncher: true,
                launcherMessage: _setupMessage,
                launcherInitialValue: _controlApiInput,
                onLauncherChanged: (v) => _controlApiInput = v ?? '',
                onLauncherConnect: _saveAndRetry,
                allowLauncherConnect: true,
                launcherSetupAvailable:
                    bootstrap != null && controlApiService != null,
                launcherSetupUnavailableMessage:
                    'Set the launcher control API host first. Once this device can reach a launcher server, you can provision a new backend from the same screen.',
                initialLauncherStep:
                    bootstrap != null && controlApiService != null
                        ? ServerSetupMode.setup
                        : ServerSetupMode.connect,
                onLauncherSetupCompleted: _bootstrap,
              ),
      ),
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

class _BootstrapLoadingView extends StatelessWidget {
  const _BootstrapLoadingView();

  @override
  Widget build(BuildContext context) {
    return NmtkShellReadinessStateView.fromState(
      NmtkShellReadinessState.warmingUp,
      message: 'Connecting to the launcher control API…',
    );
  }
}
