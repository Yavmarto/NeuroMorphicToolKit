import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/screens/server_setup.dart';
import 'package:url_launcher/url_launcher.dart';

/// Guided first-run setup: Python → launcher server → optional backend provision.
///
/// Used from [LauncherBootstrapHost] before the main app shell, from
/// [MainScreen] when Python is missing, and from `/setup` in settings.
class FirstRunSetupScreen extends ConsumerStatefulWidget {
  const FirstRunSetupScreen({
    super.key,
    this.requirePython = true,
    this.requireLauncher = true,
    this.initialLauncherStep = ServerSetupMode.connect,
    this.launcherMessage,
    this.launcherInitialValue,
    this.onLauncherChanged,
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
  final ValueChanged<String?>? onLauncherChanged;
  final Future<void> Function()? onLauncherConnect;
  final String launcherConnectLabel;
  final bool allowLauncherConnect;
  final bool launcherSetupAvailable;
  final String? launcherSetupUnavailableMessage;
  final VoidCallback? onLauncherSetupCompleted;
  final bool openOnBackendStep;

  @override
  ConsumerState<FirstRunSetupScreen> createState() =>
      _FirstRunSetupScreenState();
}

class _FirstRunSetupScreenState extends ConsumerState<FirstRunSetupScreen> {
  bool _isInstallingPython = false;
  bool _isCheckingPython = false;
  String? _pythonInstallOutput;
  String? _pythonErrorMessage;

  @override
  Widget build(BuildContext context) {
    final moduleStateAsync = ref.watch(moduleNotifierProvider);
    final moduleState = moduleStateAsync.value;
    final pythonReady =
        !widget.requirePython || (moduleState?.pythonAvailable ?? false);
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 8),
                  if (widget.requirePython) ...[
                    _buildPythonSection(context, pythonReady),
                    const SizedBox(height: 16),
                  ],
                  if (widget.requireLauncher && pythonReady)
                    ServerSetupScreen(
                      message: widget.launcherMessage ??
                          'Enter the host or base URL for the launcher control API.',
                      initialValue: widget.launcherInitialValue,
                      onChanged: widget.onLauncherChanged,
                      onConnect: widget.onLauncherConnect,
                      connectLabel: widget.launcherConnectLabel,
                      allowConnect: widget.allowLauncherConnect,
                      setupAvailable: widget.launcherSetupAvailable,
                      showScaffold: false,
                      initialMode: widget.openOnBackendStep
                          ? ServerSetupMode.setup
                          : widget.initialLauncherStep,
                      onSetupCompleted: widget.onLauncherSetupCompleted,
                      setupUnavailableMessage:
                          widget.launcherSetupUnavailableMessage,
                    ),
                  if (pythonReady) ...[
                    const SizedBox(height: 16),
                    NmtkSection(
                      title: 'Python environments (optional)',
                      subtitle:
                          'Manage Jupyter kernels and per-module venvs after '
                          'the launcher is connected.',
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: NmtkOutlinedButton(
                          onPressed: () => context.push('/environments'),
                          icon: ZetaIcons.tune,
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

  Widget _buildPythonSection(BuildContext context, bool pythonReady) {
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (Platform.isMacOS) ...[
                  NmtkPrimaryButton(
                    onPressed:
                        _isInstallingPython ? null : _installWithHomebrew,
                    icon: ZetaIcons.download,
                    label: _isInstallingPython
                        ? 'Installing…'
                        : 'Install with Homebrew',
                  ),
                  const SizedBox(height: 12),
                  NmtkOutlinedButton(
                    onPressed: _openPythonOrg,
                    icon: ZetaIcons.open_in_new_window,
                    label: 'Download from python.org',
                    tone: NmtkTone.info,
                  ),
                  const SizedBox(height: 12),
                ],
                NmtkPrimaryButton(
                  onPressed: (_isInstallingPython || _isCheckingPython)
                      ? null
                      : _retryPythonCheck,
                  icon: ZetaIcons.refresh,
                  label: _isCheckingPython
                      ? 'Checking for Python…'
                      : 'Retry detection',
                  tone: NmtkTone.neutral,
                ),
                if (_pythonInstallOutput != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    _pythonInstallOutput!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontFamily: NmtkFontFamilies.monospace,
                          package: NmtkFontFamilies.package,
                        ),
                  ),
                ],
                if (_pythonErrorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _pythonErrorMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _installWithHomebrew() async {
    setState(() {
      _isInstallingPython = true;
      _pythonInstallOutput = 'Running: brew install python\n';
      _pythonErrorMessage = null;
    });

    try {
      final brewCheck = await Process.run('which', ['brew']);
      if (brewCheck.exitCode != 0) {
        setState(() {
          _isInstallingPython = false;
          _pythonErrorMessage =
              'Homebrew is not installed. Install it from https://brew.sh '
              'or download Python from python.org.';
        });
        return;
      }

      final process = await Process.start('brew', ['install', 'python']);
      final outputBuffer = StringBuffer();

      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        outputBuffer.write(data);
        if (mounted) {
          setState(() => _pythonInstallOutput = outputBuffer.toString());
        }
      });

      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        outputBuffer.write(data);
        if (mounted) {
          setState(() => _pythonInstallOutput = outputBuffer.toString());
        }
      });

      final exitCode = await process.exitCode;
      if (mounted) {
        setState(() => _isInstallingPython = false);
        if (exitCode == 0) {
          unawaited(_retryPythonCheck());
        } else {
          _pythonErrorMessage = 'Homebrew install exited with code $exitCode.';
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInstallingPython = false;
          _pythonErrorMessage = 'Failed to run brew: $e';
        });
      }
    }
  }

  Future<void> _openPythonOrg() async {
    final uri = Uri.parse('https://www.python.org/downloads/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _retryPythonCheck() async {
    setState(() {
      _isCheckingPython = true;
      _pythonErrorMessage = null;
    });

    await ref.read(moduleNotifierProvider.notifier).recheckPython();

    if (mounted) {
      setState(() => _isCheckingPython = false);
    }
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
