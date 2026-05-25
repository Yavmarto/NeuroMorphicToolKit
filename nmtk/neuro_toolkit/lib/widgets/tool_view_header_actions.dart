import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:url_launcher/url_launcher.dart';

import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/providers/command_provider.dart';

/// Toolbar actions shown in the [ToolViewScreen] header.
///
/// Includes: developer-mode toggle, command palette, and (in developer mode)
/// open-in-browser, stop-module, and check-for-updates buttons.
class ToolViewHeaderActions extends ConsumerWidget {
  const ToolViewHeaderActions({
    required this.moduleProvider,
    required this.activeModule,
    required this.onShowModulePicker,
    required this.onOpenInBrowser,
    super.key,
  });

  final ModuleProvider moduleProvider;
  final Module? activeModule;
  final VoidCallback onShowModulePicker;
  final void Function(Module module) onOpenInBrowser;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appProvider = ref.watch(appStateProvider);
    final developerMode = appProvider.developerMode;

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
              developerMode
                  ? Icons.handyman_rounded
                  : Icons.handyman_outlined,
              color: developerMode
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            onPressed: () => appProvider.toggleDeveloperMode(),
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
            icon: const Icon(Icons.search_rounded),
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
              icon: const Icon(Icons.add),
              onPressed: onShowModulePicker,
              tooltip: 'Open a Module',
            ),
          ),
          Semantics(
            label: 'Open module in system browser',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.open_in_browser),
              onPressed: activeModule != null
                  ? () => onOpenInBrowser(activeModule!)
                  : null,
              tooltip: 'Open in System Browser',
            ),
          ),
          Semantics(
            label: 'Stop currently active module',
            button: true,
            child: IconButton(
              icon: Icon(
                Icons.stop_circle,
                color: Theme.of(context).colorScheme.error,
              ),
              onPressed: activeModule == null
                  ? null
                  : () {
                      unawaited(moduleProvider.stopModule(activeModule!.id));
                    },
              tooltip: 'Stop Module',
            ),
          ),
          Semantics(
            label: 'Check for Updates',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => moduleProvider.checkForUpdates(),
              tooltip: 'Check for Updates',
            ),
          ),
        ],
      ],
    );
  }
}
