import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/src/features/app/presentation/launcher_navigation_notifier.dart';

final commandStateProvider = Provider<List<NmtkCommand>>((ref) {
  return [
    NmtkCommand(
      id: 'nav-workspace',
      label: 'Open Workspace',
      description: 'Go to the main workspace',
      icon: ZetaIcons.dashboard,
      category: 'Navigation',
      onExecute: () =>
          ref.read(launcherNavigationProvider.notifier).openWorkspace(),
    ),
    NmtkCommand(
      id: 'nav-neurocnl',
      label: 'Open NeuroStudio (CNL)',
      description: 'Open the neuromorphic compiler and network editor',
      icon: Icons.code_rounded, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      category: 'Navigation',
      onExecute: () =>
          ref.read(launcherNavigationProvider.notifier).openModule('neurocnl'),
    ),
    NmtkCommand(
      id: 'nav-neurochip',
      label: 'Open Neurochip Analysis',
      description: 'Analyze and deploy to hardware targets (Teensy, Akida)',
      icon: ZetaIcons.memory,
      category: 'Navigation',
      onExecute: () =>
          ref.read(launcherNavigationProvider.notifier).openModule('Neurochip'),
    ),
    NmtkCommand(
      id: 'nav-neurobench',
      label: 'Open Neurobench',
      description:
          'Run SNN benchmarks and compare results across hardware targets',
      icon: ZetaIcons.analytics,
      category: 'Navigation',
      onExecute: () => ref
          .read(launcherNavigationProvider.notifier)
          .openModule('Neurobench'),
    ),
    NmtkCommand(
      id: 'action-toggle-sidebar',
      label: 'Toggle Sidebar',
      description: 'Expand or collapse the navigation sidebar',
      icon:
          Icons.menu_open_rounded, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      category: 'Actions',
      onExecute: () =>
          ref.read(launcherNavigationProvider.notifier).toggleSidebar(),
    ),
    NmtkCommand(
      id: 'action-toggle-dev',
      label: 'Toggle Developer Mode',
      description: 'Show/hide advanced module controls and internals',
      icon: Icons.handyman_rounded, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      category: 'System',
      onExecute: () {
        ref.read(appProvider.notifier).toggleDeveloperMode();
      },
    ),
    NmtkCommand(
      id: 'action-reload',
      label: 'Reload Workspace',
      description: 'Refresh the current module state',
      icon: ZetaIcons.refresh,
      category: 'Actions',
      onExecute: () =>
          ref.read(launcherNavigationProvider.notifier).reloadWorkspace(),
    ),
  ];
});
