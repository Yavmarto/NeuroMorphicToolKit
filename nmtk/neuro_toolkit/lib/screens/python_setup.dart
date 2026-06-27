import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';

/// Screen shown when no Python interpreter is detected.
/// Guides the user through installing Python on their platform.
///
/// All install/detection state is owned by [pythonInstallProvider]; this
/// widget is a pure read-and-dispatch surface with no local [setState].
class PythonSetupScreen extends ConsumerWidget {
  const PythonSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final installState = ref.watch(pythonInstallProvider);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: EdgeInsets.all(context.nmtkTokens.sectionGap * 1.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  NmtkSurfaceCard(
                    child: Column(
                      children: [
                        const Icon(Icons.terminal,
                            size:
                                72), // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                        SizedBox(height: context.nmtkTokens.sectionGap * 1.25),
                        Text(
                          'Python Required',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: context.nmtkTokens.compactGap),
                        Text(
                          'NeuroMorphic ToolKit requires Python 3.10+ to run '
                          'module backends. Install Python to continue.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                        SizedBox(height: context.nmtkTokens.sectionGap * 1.5),
                        if (Platform.isMacOS) ...[
                          SizedBox(
                            width: double.infinity,
                            child: ZetaButton.primary(
                              onPressed: installState.isInstalling
                                  ? null
                                  : () => ref
                                      .read(pythonInstallProvider.notifier)
                                      .installWithHomebrew(),
                              leadingIcon: ZetaIcons.download,
                              label: installState.isInstalling
                                  ? 'Installing...'
                                  : 'Install with Homebrew',
                            ),
                          ),
                          SizedBox(height: context.nmtkTokens.compactGap),
                          SizedBox(
                            width: double.infinity,
                            child: ZetaButton.outline(
                              onPressed: () => ref
                                  .read(pythonInstallProvider.notifier)
                                  .openPythonOrg(),
                              leadingIcon: ZetaIcons.open_in_new_window,
                              label: 'Download from python.org',
                            ),
                          ),
                          SizedBox(height: context.nmtkTokens.compactGap),
                        ],
                        SizedBox(
                          width: double.infinity,
                          child: ZetaButton.primary(
                            onPressed: (installState.isInstalling ||
                                    installState.isChecking)
                                ? null
                                : () => ref
                                    .read(pythonInstallProvider.notifier)
                                    .recheckPython(),
                            leadingIcon: ZetaIcons.refresh,
                            label: installState.isChecking
                                ? 'Checking for Python...'
                                : 'Retry Detection',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (installState.installOutput != null) ...[
                    const SizedBox(height: 12),
                    NmtkSurfaceCard(
                      title: 'Installer Output',
                      child: SizedBox(
                        height: 180,
                        child: SingleChildScrollView(
                          reverse: true,
                          child: SelectableText(
                            installState.installOutput!,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    fontFamily: NmtkFontFamilies.monospace,
                                    package: NmtkFontFamilies.package),
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (installState.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    NmtkSurfaceCard(
                      title: 'Installation Problem',
                      tone: NmtkTone.danger,
                      child: Text(installState.errorMessage!),
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
