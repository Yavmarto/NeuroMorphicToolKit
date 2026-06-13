import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';

final commandStateProvider = Provider<List<NmtkCommand>>((ref) {
  final router = ref.watch(goRouterProvider);

  return [
    NmtkCommand(
      id: 'nav-workspace',
      label: 'Open Workspace',
      description: 'Go to the main workspace',
      icon: ZetaIcons.dashboard,
      category: 'Navigation',
      onExecute: () => router.go('/workspace'),
    ),
    NmtkCommand(
      id: 'nav-neurocnl',
      label: 'Open NeuroStudio (CNL)',
      description: 'Open the neuromorphic compiler and network editor',
      icon: Icons.code_rounded, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      category: 'Navigation',
      onExecute: () => router.go('/module/neurocnl'),
    ),
    NmtkCommand(
      id: 'nav-neurochip',
      label: 'Open Neurochip Analysis',
      description: 'Analyze and deploy to hardware targets (Teensy, Akida)',
      icon: ZetaIcons.memory,
      category: 'Navigation',
      onExecute: () => router.go('/module/neurochip'),
    ),
    NmtkCommand(
      id: 'nav-neurohub',
      label: 'Open Neurohub Dashboard',
      description: 'View saved sessions and experiment telemetry',
      icon: ZetaIcons.analytics,
      category: 'Navigation',
      onExecute: () => router.go('/module/neurohub'),
    ),
    NmtkCommand(
      id: 'nav-settings',
      label: 'Open Settings',
      description: 'Configure appearance, API host, and hardware paths',
      icon: ZetaIcons.settings,
      category: 'System',
      onExecute: () => router.go('/settings'),
    ),
    NmtkCommand(
      id: 'action-toggle-sidebar',
      label: 'Toggle Sidebar',
      description: 'Expand or collapse the navigation sidebar',
      icon: Icons.menu_open_rounded, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      category: 'Actions',
      onExecute: () {
        final context = router.configuration.navigatorKey.currentContext;
        if (context != null) {
          Actions.maybeInvoke(context, const ToggleSidebarIntent());
        }
      },
    ),
    NmtkCommand(
      id: 'action-toggle-dev',
      label: 'Toggle Developer Mode',
      description: 'Show/hide advanced module controls and internals',
      icon: Icons.handyman_rounded, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      category: 'System',
      onExecute: () {
        ref.read(appNotifierProvider.notifier).toggleDeveloperMode();
      },
    ),
    NmtkCommand(
      id: 'action-reload',
      label: 'Reload Workspace',
      description: 'Refresh the current module state',
      icon: ZetaIcons.refresh,
      category: 'Actions',
      onExecute: () {
        final current = router.state.uri.toString();
        router.go(current);
      },
    ),
  ];
});
