import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/src/features/app/presentation/command_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';

/// Toolbar actions shown in the [ToolViewScreen] header.
///
/// Includes: developer-mode toggle, command palette, and (in developer mode)
/// open-module, stop-module, and check-for-updates buttons.
class ToolViewHeaderActions extends ConsumerWidget {
  const ToolViewHeaderActions({
    required this.activeModule,
    required this.onShowModulePicker,
    super.key,
  });

  final Module? activeModule;
  final VoidCallback onShowModulePicker;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appState = ref.watch(appNotifierProvider);
    final developerMode = appState.developerMode;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Developer-mode toggle — always visible (wrench icon).
        Semantics(
          label: developerMode
              ? 'Hide developer controls'
              : 'Show developer controls',
          button: true,
          child: IconButton(
            icon: Icon(
              developerMode ? Icons.handyman_rounded : Icons.handyman_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
              color:
                  developerMode ? Theme.of(context).colorScheme.primary : null,
            ),
            onPressed: () =>
                ref.read(appNotifierProvider.notifier).toggleDeveloperMode(),
            tooltip: developerMode
                ? 'Hide module internals'
                : 'Show module internals',
          ),
        ),
        // Search Commands button.
        Semantics(
          label: 'Search commands',
          button: true,
          child: IconButton(
            icon: const Icon(ZetaIcons.search),
            onPressed: () {
              final commands = ref.read(commandStateProvider);
              NmtkCommandPalette.show(context, commands: commands);
            },
            tooltip:
                'Search commands (${defaultTargetPlatform == TargetPlatform.macOS ? '⌘K' : 'Ctrl+K'})',
          ),
        ),
        // Module management controls — developer mode only.
        if (developerMode) ...[
          Semantics(
            label: 'Open a module',
            button: true,
            child: IconButton(
              icon: const Icon(ZetaIcons.add),
              onPressed: onShowModulePicker,
              tooltip: 'Open a Module',
            ),
          ),
          Semantics(
            label: 'Stop currently active module',
            button: true,
            child: IconButton(
              icon: Icon(
                ZetaIcons.stop_circle,
                color: Theme.of(context).colorScheme.error,
              ),
              onPressed: activeModule == null
                  ? null
                  : () {
                      unawaited(ref
                          .read(moduleNotifierProvider.notifier)
                          .stopModule(activeModule!.id));
                    },
              tooltip: 'Stop Module',
            ),
          ),
          Semantics(
            label: 'Check for Updates',
            button: true,
            child: IconButton(
              icon: const Icon(ZetaIcons.refresh),
              onPressed: () =>
                  ref.read(moduleNotifierProvider.notifier).checkForUpdates(),
              tooltip: 'Check for Updates',
            ),
          ),
        ],
      ],
    );
  }
}
