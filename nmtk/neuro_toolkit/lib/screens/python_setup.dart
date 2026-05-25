import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen shown when no Python interpreter is detected.
/// Guides the user through installing Python on their platform.
class PythonSetupScreen extends ConsumerStatefulWidget {
  const PythonSetupScreen({super.key});

  @override
  ConsumerState<PythonSetupScreen> createState() => _PythonSetupScreenState();
}

class _PythonSetupScreenState extends ConsumerState<PythonSetupScreen> {
  bool _isInstalling = false;
  bool _isChecking = false;
  String? _installOutput;
  String? _errorMessage;

  Future<void> _installWithHomebrew() async {
    setState(() {
      _isInstalling = true;
      _installOutput = 'Running: brew install python\n';
      _errorMessage = null;
    });

    try {
      final brewCheck = await Process.run('which', ['brew']);
      if (brewCheck.exitCode != 0) {
        setState(() {
          _isInstalling = false;
          _errorMessage =
              'Homebrew is not installed. Install it first from https://brew.sh, '
              'or download Python directly from python.org.';
        });
        return;
      }

      final process = await Process.start('brew', ['install', 'python']);
      final outputBuffer = StringBuffer();

      process.stdout.transform(const SystemEncoding().decoder).listen((data) {
        outputBuffer.write(data);
        if (mounted) {
          setState(() => _installOutput = outputBuffer.toString());
        }
      });

      process.stderr.transform(const SystemEncoding().decoder).listen((data) {
        outputBuffer.write(data);
        if (mounted) {
          setState(() => _installOutput = outputBuffer.toString());
        }
      });

      final exitCode = await process.exitCode;
      if (mounted) {
        setState(() => _isInstalling = false);
        if (exitCode == 0) {
          unawaited(_retryCheck());
        } else {
          setState(() {
            _errorMessage = 'Homebrew install exited with code $exitCode. '
                'Try installing manually from python.org.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInstalling = false;
          _errorMessage = 'Failed to run brew: $e';
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

  Future<void> _retryCheck() async {
    setState(() {
      _isChecking = true;
      _errorMessage = null;
    });

    final provider = ref.read(moduleStateProvider);
    unawaited(provider.recheckPython());

    if (mounted) {
      setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NmtkSurfaceCard(
                    child: Column(
                      children: [
                        const Icon(Icons.terminal, size: 72),
                        const SizedBox(height: 20),
                        Text(
                          'Python Required',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'NeuroMorphic ToolKit requires Python 3.10+ to run '
                          'module backends. Install Python to continue.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 24),
                        if (Platform.isMacOS) ...[
                          SizedBox(
                            width: double.infinity,
                            child: NmtkPrimaryButton(
                              onPressed:
                                  _isInstalling ? null : _installWithHomebrew,
                              icon: Icons.download,
                              label: _isInstalling
                                  ? 'Installing...'
                                  : 'Install with Homebrew',
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: NmtkOutlinedButton(
                              onPressed: _openPythonOrg,
                              icon: Icons.open_in_new,
                              label: 'Download from python.org',
                              tone: NmtkTone.info,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        SizedBox(
                          width: double.infinity,
                          child: NmtkPrimaryButton(
                            onPressed: (_isInstalling || _isChecking)
                                ? null
                                : _retryCheck,
                            icon: Icons.refresh,
                            label: _isChecking
                                ? 'Checking for Python...'
                                : 'Retry Detection',
                            tone: NmtkTone.neutral,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_installOutput != null) ...[
                    const SizedBox(height: 12),
                    NmtkSurfaceCard(
                      title: 'Installer Output',
                      child: SizedBox(
                        height: 180,
                        child: SingleChildScrollView(
                          reverse: true,
                          child: SelectableText(
                            _installOutput!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(fontFamily: NmtkFontFamilies.monospace, package: NmtkFontFamilies.package),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    NmtkSurfaceCard(
                      title: 'Installation Problem',
                      tone: NmtkTone.danger,
                      child: Text(_errorMessage!),
                    ),
                  ],
                  const SizedBox(height: 12),
                  NmtkSurfaceCard(
                    title: 'Or Install via Terminal',
                    tone: NmtkTone.info,
                    child: SelectableText(
                      Platform.isMacOS
                          ? 'brew install python'
                          : 'sudo apt install python3 python3-venv',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: NmtkFontFamilies.monospace,
                            package: NmtkFontFamilies.package,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
