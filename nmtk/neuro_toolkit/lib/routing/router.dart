import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:neuro_toolkit/screens/settings.dart';
import 'package:neuro_toolkit/screens/python_setup.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/screens/onboarding.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/app_provider.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/services/launcher_control_bootstrap_service.dart';
import 'package:neuro_toolkit/services/update_service.dart';

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
            path: '/catalog',
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
// MainScreen — shell wrapper providing the app bar with settings + updates.
// Navigation rail/bar is intentionally absent: the workspace is always the
// primary body and settings is reached via the top-right icon button.
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

    if (!provider.pythonAvailable && !provider.isLoading) {
      return const PythonSetupScreen();
    }

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

    final location = GoRouterState.of(context).uri.toString();
    final isOnSettings = location.startsWith('/settings');

    return Scaffold(
      appBar: AppBar(
        title: const Text('NeuroToolkit'),
        actions: [
          Semantics(
            label: isOnSettings ? 'Close Settings' : 'Open Settings',
            button: true,
            child: IconButton(
              icon: Icon(
                isOnSettings ? Icons.close : Icons.settings_outlined,
              ),
              tooltip: isOnSettings ? 'Close Settings' : 'Settings',
              onPressed: () =>
                  isOnSettings ? context.go('/workspace') : context.go('/settings'),
            ),
          ),
          Semantics(
            label: 'Check for Updates',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Check for Updates',
              onPressed: () => provider.checkForUpdates(),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: widget.child,
    );
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
      builder: (context) => AlertDialog(
        title: const Text('Launcher Update Available'),
        content: Column(
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
        actions: [
          TextButton(
            onPressed: () {
              provider.dismissLauncherUpdate();
              Navigator.of(context).pop();
            },
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = Uri.parse(update.url);
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              }
            },
            child: const Text('Download Now'),
          ),
        ],
      ),
    );
  }
}
