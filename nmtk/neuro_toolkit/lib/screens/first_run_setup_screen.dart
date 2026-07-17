import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/server_setup.dart';

/// Guided first-run setup: Python → launcher server → optional backend provision.
///
/// Used from [LauncherBootstrapHost] before the main app shell, from
/// [MainScreen] when Python is missing, and from `/setup` in settings.
///
/// All Python install/detection state is owned by [pythonInstallProvider];
/// this widget is a pure read-and-dispatch surface with no local [setState].
class FirstRunSetupScreen extends ConsumerWidget {
  const FirstRunSetupScreen({
    super.key,
    this.requirePython = true,
    this.requireLauncher = true,
    this.initialLauncherStep = ServerSetupMode.connect,
    this.launcherMessage,
    this.launcherInitialValue,
    this.onLauncherConnect,
    this.launcherConnectLabel = 'Save & Retry',
    this.allowLauncherConnect = true,
    this.launcherSetupAvailable = true,
    this.launcherSetupUnavailableMessage,
    this.onLauncherSetupCompleted,
    this.openOnBackendStep = false,
  });

  final bool requirePython;
  final bool requireLauncher;

  final ServerSetupMode initialLauncherStep;
  final String? launcherMessage;
  final String? launcherInitialValue;
  final Future<void> Function(String host)? onLauncherConnect;
  final String launcherConnectLabel;
  final bool allowLauncherConnect;
  final bool launcherSetupAvailable;
  final String? launcherSetupUnavailableMessage;
  final VoidCallback? onLauncherSetupCompleted;
  final bool openOnBackendStep;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moduleStateAsync = ref.watch(moduleProvider);
    final moduleState = moduleStateAsync.value;
    final pythonReady =
        !requirePython || (moduleState?.pythonAvailable ?? false);

    final installState = ref.watch(pythonInstallProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(context.nmtkTokens.sectionGap * 1.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: context.nmtkTokens.compactGap),
                  if (requirePython) ...[
                    _buildPythonSection(
                        context, ref, pythonReady, installState),
                    SizedBox(height: context.nmtkTokens.sectionGap),
                  ],
                  if (requireLauncher && pythonReady)
                    ServerSetupScreen(
                      message: launcherMessage ??
                          'Enter the host or base URL for the launcher control API.',
                      initialValue: launcherInitialValue,
                      onConnect: onLauncherConnect,
                      connectLabel: launcherConnectLabel,
                      allowConnect: allowLauncherConnect,
                      setupAvailable: launcherSetupAvailable,
                      showScaffold: false,
                      initialMode: openOnBackendStep
                          ? ServerSetupMode.setup
                          : initialLauncherStep,
                      onSetupCompleted: onLauncherSetupCompleted,
                      setupUnavailableMessage: launcherSetupUnavailableMessage,
                    ),
                  if (pythonReady) ...[
                    SizedBox(height: context.nmtkTokens.sectionGap),
                    NmtkSection(
                      title: 'Python environments (optional)',
                      subtitle:
                          'Manage Jupyter kernels and per-module venvs after '
                          'the launcher is connected.',
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ZetaButton.outline(
                          onPressed: () => context.push('/environments'),
                          leadingIcon: ZetaIcons.tune,
                          label: 'Open environment manager',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPythonSection(
    BuildContext context,
    WidgetRef ref,
    bool pythonReady,
    PythonInstallState installState,
  ) {
    return NmtkSection(
      title: 'Step 1 — Python',
      subtitle: pythonReady
          ? 'Python 3.10+ detected. Continue with launcher setup below.'
          : 'Python 3.10+ is required for module backends.',
      child: pythonReady
          ? NmtkShellReadinessStateView.fromState(
              NmtkShellReadinessState.ready,
              message: 'Python is available on this machine.',
            )
          : _PythonInstallSection(installState: installState),
    );
  }
}

/// Private stateless sub-widget that renders install actions and output.
/// Extracted so [FirstRunSetupScreen.build] stays under 60 lines.
class _PythonInstallSection extends ConsumerWidget {
  const _PythonInstallSection({required this.installState});

  final PythonInstallState installState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(pythonInstallProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ZetaButton.primary(
          onPressed:
              installState.isInstalling ? null : notifier.installWithHomebrew,
          leadingIcon: ZetaIcons.download,
          label: installState.isInstalling
              ? 'Installing…'
              : 'Install with Homebrew',
        ),
        SizedBox(height: context.nmtkTokens.compactGap),
        ZetaButton.outline(
          onPressed: notifier.openPythonOrg,
          leadingIcon: ZetaIcons.open_in_new_window,
          label: 'Download from python.org',
        ),
        SizedBox(height: context.nmtkTokens.compactGap),
        ZetaButton.primary(
          onPressed: (installState.isInstalling || installState.isChecking)
              ? null
              : notifier.recheckPython,
          leadingIcon: ZetaIcons.refresh,
          label: installState.isChecking
              ? 'Checking for Python…'
              : 'Retry detection',
        ),
        if (installState.installOutput != null) ...[
          SizedBox(height: context.nmtkTokens.compactGap),
          SelectableText(
            installState.installOutput!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: NmtkFontFamilies.monospace,
                  package: NmtkFontFamilies.package,
                ),
          ),
        ],
        if (installState.errorMessage != null) ...[
          SizedBox(height: context.nmtkTokens.compactGap),
          Text(
            installState.errorMessage!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
      ],
    );
  }
}

/// Settings / deep-link entry: full setup flow inside the main app shell.
class InAppFirstRunSetupScreen extends StatelessWidget {
  const InAppFirstRunSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final step = GoRouterState.of(context).uri.queryParameters['step'];
    return FirstRunSetupScreen(
      requirePython: true,
      requireLauncher: true,
      allowLauncherConnect: false,
      openOnBackendStep: step == 'backend',
      onLauncherSetupCompleted: () {
        if (context.mounted) {
          context.go('/workspace');
        }
      },
    );
  }
}
