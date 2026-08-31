import 'dart:async';
import 'dart:io';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:neuro_toolkit/src/features/module/presentation/module_notifier.dart';
import 'package:neuro_toolkit/src/features/python_install/domain/python_install_state.dart';

part 'python_install_notifier.g.dart';

/// Manages the Python installation/detection flow, including:
/// - Homebrew-based installation with streamed output
/// - Python re-detection via the module provider
///
/// This notifier is `autoDispose` so it resets when the setup screen is
/// unmounted, preventing stale install state from persisting between visits.
@riverpod
class PythonInstallNotifier extends _$PythonInstallNotifier {
  @override
  PythonInstallState build() => const PythonInstallState();

  Future<void> installWithHomebrew() async {
    state = state.copyWith(
      isInstalling: true,
      installOutput: 'Running: brew install python\n',
      errorMessage: null,
    );

    try {
      final brewCheck = await Process.run('which', ['brew']);
      if (brewCheck.exitCode != 0) {
        state = state.copyWith(
          isInstalling: false,
          errorMessage:
              'Homebrew is not installed. Install it from https://brew.sh '
              'or download Python from python.org.',
        );
        return;
      }

      final process = await Process.start('brew', ['install', 'python']);
      final outputBuffer = StringBuffer(state.installOutput ?? '');

      final stdoutSub = process.stdout
          .transform(const SystemEncoding().decoder)
          .listen((data) {
            outputBuffer.write(data);
            state = state.copyWith(installOutput: outputBuffer.toString());
          });

      final stderrSub = process.stderr
          .transform(const SystemEncoding().decoder)
          .listen((data) {
            outputBuffer.write(data);
            state = state.copyWith(installOutput: outputBuffer.toString());
          });

      final exitCode = await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();

      state = state.copyWith(isInstalling: false);

      if (exitCode == 0) {
        // Auto-recheck after a successful install.
        await recheckPython();
      } else {
        state = state.copyWith(
          errorMessage: 'Homebrew install exited with code $exitCode.',
        );
      }
    } catch (e) {
      state = state.copyWith(
        isInstalling: false,
        errorMessage: 'Failed to run brew: $e',
      );
    }
  }

  Future<void> openPythonOrg() async {
    final uri = Uri.parse('https://www.python.org/downloads/');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> recheckPython() async {
    state = state.copyWith(isChecking: true, errorMessage: null);
    await ref.read(moduleProvider.notifier).recheckPython();
    state = state.copyWith(isChecking: false);
  }
}
