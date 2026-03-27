import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// Screen shown when no Python interpreter is detected.
/// Guides the user through installing Python on their platform.
class PythonSetupScreen extends StatefulWidget {
  const PythonSetupScreen({super.key});

  @override
  State<PythonSetupScreen> createState() => _PythonSetupScreenState();
}

class _PythonSetupScreenState extends State<PythonSetupScreen> {
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
      // Check if Homebrew is available
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
          // Recheck Python availability
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

    final provider = context.read<ModuleProvider>();
    unawaited(provider.recheckPython());

    if (mounted) {
      setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.terminal,
                  size: 72,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Python Required',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'NeuroMorphic ToolKit requires Python 3.10+ to run '
                  'module backends. Please install Python to continue.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),

                // --- macOS-specific install options ---
                if (Platform.isMacOS) ...[
                  Semantics(
                    label: 'Install Python using Homebrew',
                    button: true,
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _isInstalling ? null : _installWithHomebrew,
                        icon: const Icon(Icons.download),
                        label: _isInstalling
                            ? const Text('Installing...')
                            : const Text('Install with Homebrew'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Semantics(
                    label: 'Download Python from python.org website',
                    button: true,
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _openPythonOrg,
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Download from python.org'),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),

                // --- Retry button ---
                Semantics(
                  label: 'Retry detecting installed Python',
                  button: true,
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonalIcon(
                      onPressed:
                          (_isInstalling || _isChecking) ? null : _retryCheck,
                      icon: _isChecking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: const Text('Retry Detection'),
                    ),
                  ),
                ),

                // --- Install output ---
                if (_installOutput != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    height: 160,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      reverse: true,
                      child: SelectableText(
                        _installOutput!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
                ],

                // --- Error message ---
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 24),
                // Hint for terminal users
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Or install via terminal:',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        Platform.isMacOS
                            ? 'brew install python'
                            : 'sudo apt install python3 python3-venv',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
