import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:neuro_toolkit/screens/settings.dart';
import 'package:neuro_toolkit/screens/first_run_setup_screen.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/screens/environment_editor.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';

GoRouter createGoRouter() {
  return GoRouter(
    initialLocation: '/workspace',
    routes: [
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
            redirect: (context, state) {
              final step = state.uri.queryParameters['step'];
              if (step != null && step.isNotEmpty) {
                return '/setup?step=$step';
              }
              return '/setup?step=backend';
            },
          ),
          GoRoute(
            path: '/setup',
            name: 'setup',
            builder: (context, state) => const InAppFirstRunSetupScreen(),
          ),
          GoRoute(
            path: '/environments',
            name: 'environments',
            builder: (context, state) => const EnvironmentEditorScreen(),
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
          GoRoute(
            path: '/module/jupyter',
            name: 'module-jupyter',
            builder: (context, state) =>
                const ToolViewScreen(initialModuleId: 'jupyter'),
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

    // Gate: Python not detected — unified first-run flow (own Scaffold).
    if (!provider.pythonAvailable && !provider.isLoading) {
      return const FirstRunSetupScreen(
        requirePython: true,
        requireLauncher: false,
      );
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
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Launcher Update Available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version of NeuroToolkit (${update.version}) is available.',
            ),
            const SizedBox(height: 16),
            Text(
              'Release Notes:',
              style: Zeta.of(context)
                  .textStyles
                  .bodyMedium
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            Text(releaseNotes),
          ],
        ),
        actions: [
          ZetaButton.text(
            onPressed: () {
              provider.dismissLauncherUpdate();
              Navigator.of(dialogContext).pop();
            },
            label: 'Later',
          ),
          ZetaButton(
            onPressed: () async {
              final url = Uri.parse(update.url);
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              }
            },
            label: 'Download Now',
          ),
        ],
      ),
    );
  }
}
