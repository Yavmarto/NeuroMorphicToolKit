import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
import 'package:neuro_toolkit/providers/command_provider.dart';
import 'package:neuro_toolkit/screens/server_setup.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final analytics = AnalyticsService();
  await analytics.init();

  final settings = SettingsProvider(analyticsService: analytics);
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
    ProviderScope(
      overrides: [
        analyticsServiceProvider.overrideWithValue(analytics),
        settingsStateProvider.overrideWith((ref) => settings),
      ],
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
  final TextEditingController _controlApiController = TextEditingController();
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
    final settings = ref.read(settingsStateProvider);
    var saved = settings.launcherControlApiBaseUrl?.trim() ?? '';
    if (saved.isNotEmpty) {
      final uri = Uri.tryParse(saved);
      if (uri != null && uri.host.isNotEmpty) {
        saved = uri.host;
      }
    }
    _controlApiController.text = saved;
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _controlApiController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final settings = ref.read(settingsStateProvider);
    final explicitBaseUri = _configuredBaseUri(settings);
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

  Uri? _configuredBaseUri(SettingsProvider settings) {
    final configured = ControlApiService.configuredBaseUrl.trim();
    if (configured.isNotEmpty) {
      return Uri.parse(configured);
    }
    final stored = settings.launcherControlApiBaseUrl?.trim() ?? '';
    if (stored.isNotEmpty) {
      return Uri.parse(stored);
    }
    return null;
  }

  Future<void> _saveAndRetry() async {
    var input = _controlApiController.text.trim();
    if (input.isNotEmpty) {
      if (!input.startsWith('http://') && !input.startsWith('https://')) {
        input = 'http://$input';
      }
      final uri = Uri.tryParse(input);
      if (uri != null && !uri.hasPort) {
        input = '${uri.scheme}://${uri.host}:8090${uri.path}';
      }
    }
    await ref.read(settingsStateProvider).setLauncherControlApiBaseUrl(input);
    if (!mounted) {
      return;
    }
    await _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStateProvider);
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
        theme: settings.isHighContrast ? AppTheme.highContrastLightTheme : light,
        darkTheme: settings.isHighContrast ? AppTheme.highContrastDarkTheme : dark,
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
        home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _isLoading
                  ? const _BootstrapLoadingView()
                  : bootstrap != null && controlApiService != null
                      ? ProviderScope(
                          overrides: [
                            launcherBootstrapStateProvider
                                .overrideWithValue(bootstrap),
                            controlApiServiceProvider
                                .overrideWithValue(controlApiService),
                          ],
                          child: ServerSetupScreen(
                            controller: _controlApiController,
                            message: _setupMessage,
                            onConnect: _saveAndRetry,
                            setupAvailable: true,
                            initialMode: ServerSetupMode.setup,
                            onSetupCompleted: _bootstrap,
                          ),
                        )
                      : ServerSetupScreen(
                          controller: _controlApiController,
                          message: _setupMessage,
                          onConnect: _saveAndRetry,
                          setupAvailable: false,
                          setupUnavailableMessage:
                              'Set the launcher control API host first. Once this device can reach a launcher server, you can provision a new backend from the same screen.',
                        ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class NeuroToolkitApp extends ConsumerWidget {
  const NeuroToolkitApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsStateProvider);
    final router = ref.watch(goRouterProvider);

    return NmtkZetaTheme.wrap(
      builder: (context, light, dark, mode) => MaterialApp.router(
        title: 'NeuroToolkit',
        theme: settings.isHighContrast ? AppTheme.highContrastLightTheme : light,
        darkTheme: settings.isHighContrast ? AppTheme.highContrastDarkTheme : dark,
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
