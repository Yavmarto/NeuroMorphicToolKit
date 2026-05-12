import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:neuro_toolkit/screens/settings.dart';
import 'package:neuro_toolkit/screens/python_setup.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/screens/onboarding.dart';
import 'package:neuro_toolkit/screens/backend_setup.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/app_provider.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';

GoRouter createGoRouter(AppProvider appProvider) {
  return GoRouter(
    initialLocation: '/workspace',
    refreshListenable: appProvider,
    redirect: (context, state) {
      if (!appProvider.isInitialized) return null;
      if (!appProvider.hasSeenOnboarding && state.uri.path != '/onboarding') {
        return '/onboarding';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      ShellRoute(
        builder: (context, state, child) => MainScreen(child: child),
        routes: [
          // Root redirects to workspace — handles any legacy deep links.
          GoRoute(
            path: '/',
            redirect: (context, state) => '/workspace',
          ),
          GoRoute(
            path: '/workspace',
            name: 'workspace',
            builder: (context, state) {
              final moduleId = state.uri.queryParameters['moduleId'];
              return ToolViewScreen(initialModuleId: moduleId);
            },
          ),
          GoRoute(
            path: '/tool/:moduleId',
            redirect: (context, state) {
              final moduleId = state.pathParameters['moduleId']!;
              return '/workspace?moduleId=$moduleId';
            },
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: '/backend-setup',
            name: 'backend-setup',
            builder: (context, state) => const BackendSetupScreen(),
          ),
          // Native module routes currently delegate to the workspace surface.
          // This keeps deep links working even when feature wrapper packages
          // are absent from the checkout.
          GoRoute(
            path: '/module/neurocnl',
            name: 'module-neurocnl',
            builder: (context, state) =>
                const ToolViewScreen(initialModuleId: 'neurocnl'),
          ),
          GoRoute(
            path: '/module/neurosim',
            redirect: (context, state) =>
                '/module/neurocnl/canvas${state.uri.hasQuery ? '?${state.uri.query}' : ''}',
          ),
          GoRoute(
            path: '/module/neurochip',
            name: 'module-neurochip',
            builder: (context, state) =>
                const ToolViewScreen(initialModuleId: 'Neurochip'),
          ),
          GoRoute(
            path: '/module/neurobench',
            name: 'module-neurobench',
            builder: (context, state) =>
                const ToolViewScreen(initialModuleId: 'Neurobench'),
          ),
          GoRoute(
            path: '/module/neurosense',
            redirect: (context, state) => '/module/neurocnl',
          ),
          GoRoute(
            path: '/module/neurohub',
            name: 'module-neurohub',
            builder: (context, state) =>
                const ToolViewScreen(initialModuleId: 'Neurohub'),
          ),
          // Hardware deploy routes (/deploy/akida, /deploy/pynq,
          // /deploy/teensy) were removed when the deploy UIs were relocated
          // to the Neurochip module frontend in ADR-claude/0007. Reach them
          // by opening the Neurochip module workspace.
        ],
      ),
    ],
  );
}

// ---------------------------------------------------------------------------
// MainScreen — thin shell wrapper that gates the app on Python / bootstrap
// readiness. Navigation chrome is provided by NmtkDesktopScaffold inside
// ToolViewScreen; this widget only renders its own Scaffold for error/gate
// states that appear before the workspace is reachable.
// ---------------------------------------------------------------------------

class MainScreen extends ConsumerStatefulWidget {
  final Widget child;
  const MainScreen({super.key, required this.child});

  @override
  ConsumerState<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends ConsumerState<MainScreen> {
  /// Tracks whether the launcher-update dialog is currently queued/showing so
  /// we don't stack duplicate dialogs on every rebuild triggered by the 3s
  /// refresh timer.
  bool _updateDialogQueued = false;

  @override
  Widget build(BuildContext context) {
    final provider = ref.watch(moduleStateProvider);
    final backendDeployment = ref.watch(backendDeploymentStateProvider);
    final bootstrapState = ref.watch(launcherBootstrapStateProvider);

    // Queue the launcher-update dialog exactly once per available update.
    if (provider.pendingLauncherUpdate != null && !_updateDialogQueued) {
      _updateDialogQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _showLauncherUpdateDialog(context, provider);
        }
      });
    }
    if (provider.pendingLauncherUpdate == null) {
      _updateDialogQueued = false;
    }

    // Gate: Python not detected — show full-screen setup guide (own Scaffold).
    if (!provider.pythonAvailable && !provider.isLoading) {
      return const PythonSetupScreen();
    }

    // Gate: launcher control API could not start — show error Scaffold.
    if (bootstrapState.status == LauncherBootstrapStatus.preflightFailed) {
      return Scaffold(
        appBar: AppBar(title: const Text('NeuroToolkit')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: NmtkShellReadinessStateView.fromState(
                NmtkShellReadinessState.error,
                message: bootstrapState.message ??
                    'Preflight failed: launcher control API could not start.',
              ),
            ),
          ),
        ),
      );
    }

    if (!backendDeployment.isLoading && !backendDeployment.isReady) {
      return const BackendSetupScreen();
    }

    // Normal operation: the child route provides its own chrome via
    // NmtkDesktopScaffold (ToolViewScreen) or is a content-only widget
    // (SettingsScreen). No extra Scaffold wrapper here.
    return widget.child;
  }

  void _showLauncherUpdateDialog(
    BuildContext context,
    ModuleProvider provider,
  ) {
    final update = provider.pendingLauncherUpdate;
    if (update == null) return;
    final releaseNotes = update.releaseNotes.trim().isEmpty
        ? 'No published release notes were found for this version.'
        : update.releaseNotes;
    showShadDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => ShadDialog(
        title: const Text('Launcher Update Available'),
        actions: [
          ShadButton.ghost(
            onPressed: () {
              provider.dismissLauncherUpdate();
              Navigator.of(dialogContext).pop();
            },
            child: const Text('Later'),
          ),
          ShadButton(
            onPressed: () async {
              final url = Uri.parse(update.url);
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              }
            },
            child: const Text('Download Now'),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version of NeuroToolkit (${update.version}) is available.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Release Notes:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(releaseNotes),
          ],
        ),
      ),
    );
  }
}
