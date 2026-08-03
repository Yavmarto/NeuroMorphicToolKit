import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/screens/environment_editor.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/widgets/server_setup_popup.dart';

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
            builder: (context, state) => const ToolViewScreen(
              openServerSetupOnStart: true,
            ),
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
  bool _startupSetupPromptQueued = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      launcherBootstrapProvider,
      _handleBootstrapChange,
      fireImmediately: true,
    );
  }

  void _handleBootstrapChange(
    AsyncValue<LauncherBootstrapData>? previous,
    AsyncValue<LauncherBootstrapData> next,
  ) {
    if (next.isLoading && next.value == null) return;
    if (ref.read(startupServerSetupPromptProvider) ||
        _startupSetupPromptQueued) {
      return;
    }
    if (next.value?.isReady == true) {
      ref.read(startupServerSetupPromptProvider.notifier).markHandled();
      return;
    }

    _startupSetupPromptQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _startupSetupPromptQueued = false;
        return;
      }
      final isExplicitSetupRoute =
          GoRouterState.of(context).uri.path == '/setup';
      ref.read(startupServerSetupPromptProvider.notifier).markHandled();
      if (isExplicitSetupRoute) {
        _startupSetupPromptQueued = false;
        return;
      }

      final latestData = ref.read(launcherBootstrapProvider).value;
      if (latestData?.isReady == true) {
        _startupSetupPromptQueued = false;
        return;
      }
      final savedHost =
          ref.read(settingsProvider).value?.launcherControlApiBaseUrl;
      await showAdaptiveServerSetupPopup(
        context,
        initialHost: latestData?.suggestedInstallHost ?? savedHost,
        message: latestData?.setupMessage ??
            'Preflight failed while checking the launcher host. Confirm the '
                'address and try again.',
      );
      _startupSetupPromptQueued = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final moduleStateAsync = ref.watch(moduleProvider);
    final moduleState = moduleStateAsync.value;

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

    // The workspace is always the base surface. Bootstrap readiness controls
    // the one-time adaptive setup popup, never whether the shell can mount.
    return widget.child;
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
