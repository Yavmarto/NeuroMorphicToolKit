import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
import 'package:neuro_toolkit/providers/command_provider.dart';

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
      setState(() {
        _bootstrapState = bootstrap;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _bootstrapState = null;
      _isLoading = false;
      _setupMessage = bootstrap.message;
    });
  }

  Uri? _configuredBaseUri(SettingsProvider settings) {
    final stored = settings.launcherControlApiBaseUrl?.trim() ?? '';
    if (stored.isNotEmpty) {
      return Uri.parse(stored);
    }
    final configured = ControlApiService.configuredBaseUrl.trim();
    if (configured.isNotEmpty) {
      return Uri.parse(configured);
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
    await ref
        .read(settingsStateProvider)
        .setLauncherControlApiBaseUrl(input);
    if (!mounted) {
      return;
    }
    await _bootstrap();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsStateProvider);
    final bootstrap = _bootstrapState;
    if (bootstrap != null) {
      return ProviderScope(
        overrides: [
          launcherBootstrapStateProvider.overrideWithValue(bootstrap),
          controlApiServiceProvider.overrideWithValue(
            ControlApiService(
              baseUri: bootstrap.baseUri,
              analyticsService: ref.read(analyticsServiceProvider),
            ),
          ),
        ],
        child: const NeuroToolkitApp(),
      );
    }

    return ShadApp(
      title: 'NeuroToolkit',
      theme: NmtkShadTheme.light,
      darkTheme: NmtkShadTheme.dark,
      materialThemeBuilder: (_, mTheme) {
        final isDark = mTheme.brightness == Brightness.dark;
        final b = isDark ? AppTheme.darkTheme : AppTheme.lightTheme;
        return settings.isHighContrast
            ? (isDark
                ? AppTheme.highContrastDarkTheme
                : AppTheme.highContrastLightTheme)
            : b;
      },
      themeMode: settings.themeMode,
      builder: (BuildContext ctx, Widget? child) {
        final commands = ref.watch(commandStateProvider);
        return NmtkShortcutScope(
          globalCommands: commands,
          child: MediaQuery(
            data: MediaQuery.of(ctx).copyWith(
              textScaler: TextScaler.linear(settings.fontSizeFactor),
            ),
            child: ShadToaster(child: child!),
          ),
        );
      },
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _isLoading
                  ? const _BootstrapLoadingView()
                  : _BootstrapSetupView(
                      controller: _controlApiController,
                      message: _setupMessage,
                      onRetry: _saveAndRetry,
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

    return ShadApp.router(
      title: 'NeuroToolkit',
      // Shadcn layer — controls Shadcn components suite-wide.
      theme: NmtkShadTheme.light,
      darkTheme: NmtkShadTheme.dark,
      // Material 3 layer — controls native Flutter widgets.
      materialThemeBuilder: (_, mTheme) {
        final isDark = mTheme.brightness == Brightness.dark;
        final b = isDark ? AppTheme.darkTheme : AppTheme.lightTheme;
        return settings.isHighContrast
            ? (isDark
                ? AppTheme.highContrastDarkTheme
                : AppTheme.highContrastLightTheme)
            : b;
      },
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: (BuildContext ctx, Widget? child) {
        final commands = ref.watch(commandStateProvider);
        // Apply font scaling and inject ShadToaster so NmtkToasts can find it
        // in the widget tree via ShadToaster.of(context).
        return NmtkShortcutScope(
          globalCommands: commands,
          child: MediaQuery(
            data: MediaQuery.of(ctx).copyWith(
              textScaler: TextScaler.linear(settings.fontSizeFactor),
            ),
            child: ShadToaster(child: child!),
          ),
        );
      },
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

class _BootstrapSetupView extends StatelessWidget {
  const _BootstrapSetupView({
    required this.controller,
    required this.message,
    required this.onRetry,
  });

  final TextEditingController controller;
  final String? message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return NmtkSurfaceCard(
      title: 'Launcher Server',
      subtitle: 'Connect this device to the launcher control API first.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NmtkShellReadinessStateView.fromState(
            NmtkShellReadinessState.error,
            message: message ??
                'Enter the host or IP address for the launcher control API.',
          ),
          const SizedBox(height: 16),
          ShadInputFormField(
            label: const Text('CONTROL API HOST IP'),
            controller: controller,
            placeholder: const Text('192.168.2.192'),
          ),
          const SizedBox(height: 8),
          Text(
            'Run `python3 scripts/launcher_control_service.py --host 0.0.0.0 --port 8090` on the host machine, then retry. Use `10.0.2.2` for an Android emulator or the host machine IP for a physical device.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          NmtkPrimaryButton(
            onPressed: onRetry,
            icon: Icons.wifi_find_rounded,
            label: 'Save & Retry',
          ),
        ],
      ),
    );
  }
}
