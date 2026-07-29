import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:neuro_toolkit/screens/backend_setup.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/screens/environment_editor.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';

GoRouter createGoRouter({String initialLocation = '/workspace'}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        // SelectionArea belongs here, not in MaterialApp.router's own
        // `builder` -- this callback runs inside the Navigator's page/Overlay
        // machinery, so SelectionArea ends up a descendant of the Overlay
        // (required by SelectableRegion). Wrapping the Navigator itself from
        // outside (as MaterialApp.router's `builder` would) puts it above
        // the Overlay instead, which throws "No Overlay widget found".
        builder: (context, state, child) =>
            SelectionArea(child: MainScreen(child: child)),
        routes: [
          // Root redirects to workspace — handles any legacy deep links.
          GoRoute(path: '/', redirect: (context, state) => '/workspace'),
          GoRoute(
            path: '/workspace',
            name: 'workspace',
            builder: (context, state) {
              final moduleId =
                  state.uri.queryParameters['moduleId'] ?? 'neurocnl';
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
            builder: (context, state) => const InAppBackendSetupScreen(),
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
            name: 'module-neurosense',
            builder: (context, state) =>
                const ToolViewScreen(initialModuleId: 'Neurosense'),
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
// MainScreen — thin shell wrapper that gates the app on backend readiness.
// Navigation chrome is provided by NmtkDesktopScaffold inside
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
    final bootstrapAsync = ref.watch(launcherBootstrapProvider);
    final bootstrapData = bootstrapAsync.value;
    if (bootstrapAsync.isLoading && bootstrapData == null) {
      final targetHost =
          ref.watch(settingsProvider).value?.launcherControlApiBaseUrl;
      return Scaffold(
        body: Center(
          child: _LauncherBootstrapLoadingView(targetHost: targetHost),
        ),
      );
    }
    if (bootstrapAsync.hasError || bootstrapData == null) {
      return _buildSetupScreen(
        context,
        message: 'Preflight failed while checking the launcher host. '
            'Confirm the address and try again.',
      );
    }
    if (!bootstrapData.isReady) {
      return _buildSetupScreen(
        context,
        message: bootstrapData.setupMessage,
        initialHost: bootstrapData.suggestedInstallHost,
      );
    }

    final moduleStateAsync = ref.watch(moduleProvider);
    final moduleState = moduleStateAsync.value;
    final bootstrapState = ref.watch(launcherBootstrapStateProvider);

    // If still loading and we have no value, show a loader
    if (moduleState == null && moduleStateAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('NeuroToolkit')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (moduleState != null) {
      // Queue the launcher-update dialog exactly once per available update.
      if (moduleState.pendingLauncherUpdate != null && !_updateDialogQueued) {
        _updateDialogQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showLauncherUpdateDialog(context, ref);
          }
        });
      }
      if (moduleState.pendingLauncherUpdate == null) {
        _updateDialogQueued = false;
      }
    }

    // Gate: launcher control API could not start — show error Scaffold.
    if (bootstrapState.status == LauncherBootstrapStatus.preflightFailed) {
      return _buildSetupScreen(
        context,
        message: bootstrapState.message ??
            'Preflight failed: launcher control API could not start.',
      );
    }

    // Normal operation: the child route provides its own chrome via
    // NmtkDesktopScaffold (ToolViewScreen). No extra Scaffold wrapper here.
    return widget.child;
  }

  Widget _buildSetupScreen(
    BuildContext context, {
    String? message,
    String? initialHost,
  }) {
    final notifier = ref.read(launcherBootstrapProvider.notifier);
    return BackendSetupScreen(
      message: message,
      initialHost: initialHost,
      onQuickConnect: (input) async {
        final error = await notifier.connectToLauncher(input);
        if (error == null) {
          await _refreshServerBackedProviders();
        }
        return error;
      },
      onQuickConnectSuccess: () {
        try {
          context.go('/workspace');
        } on Object catch (error) {
          unawaited(notifier.recordRouteHandoffFailure(error));
        }
      },
      onDeploymentReady: (target) async {
        await notifier.connectToDeploymentTarget(target);
        await _refreshServerBackedProviders();
      },
    );
  }

  Future<void> _refreshServerBackedProviders() async {
    ref.invalidate(controlApiServiceProvider);
    await Future.wait([
      ref.refresh(moduleProvider.future),
      ref.refresh(workspaceProvider.future),
    ]);
    ref.invalidate(serverConnectionProvider);
    ref.invalidate(backendUpdateProvider);
  }

  void _showLauncherUpdateDialog(BuildContext context, WidgetRef ref) {
    final moduleState = ref.read(moduleProvider).value;
    final update = moduleState?.pendingLauncherUpdate;
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
              style: Zeta.of(
                context,
              ).textStyles.bodyMedium.copyWith(fontWeight: FontWeight.bold),
            ),
            Text(releaseNotes),
          ],
        ),
        actions: [
          ZetaButton.text(
            onPressed: () {
              ref.read(moduleProvider.notifier).dismissLauncherUpdate();
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

/// Keeps long first-time probes legible without replacing the setup form
/// during user-initiated Quick Connect attempts.
class _LauncherBootstrapLoadingView extends StatefulWidget {
  const _LauncherBootstrapLoadingView({this.targetHost});

  final String? targetHost;

  @override
  State<_LauncherBootstrapLoadingView> createState() =>
      _LauncherBootstrapLoadingViewState();
}

class _LauncherBootstrapLoadingViewState
    extends State<_LauncherBootstrapLoadingView> {
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
