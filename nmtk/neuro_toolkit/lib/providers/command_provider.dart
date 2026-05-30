import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';

/// ----------------------------------------------------------------------------
/// NMTK COMMAND PROVIDER
/// ----------------------------------------------------------------------------

final commandStateProvider = Provider<List<NmtkCommand>>((ref) {
  final router = ref.watch(goRouterProvider);

  return [
    // --- Navigation Commands ---
    NmtkCommand(
      id: 'nav-workspace',
      label: 'Open Workspace',
      description: 'Go to the main workspace',
      icon: Icons.dashboard_rounded,
      category: 'Navigation',
      onExecute: () => router.go('/workspace'),
    ),
    NmtkCommand(
      id: 'nav-neurocnl',
      label: 'Open NeuroStudio (CNL)',
      description: 'Open the neuromorphic compiler and network editor',
      icon: Icons.code_rounded,
      category: 'Navigation',
      onExecute: () => router.go('/module/neurocnl'),
    ),
    NmtkCommand(
      id: 'nav-neurochip',
      label: 'Open Neurochip Analysis',
      description: 'Analyze and deploy to hardware targets (Teensy, Akida)',
      icon: Icons.memory_rounded,
      category: 'Navigation',
      onExecute: () => router.go('/module/neurochip'),
    ),
    NmtkCommand(
      id: 'nav-neurohub',
      label: 'Open Neurohub Dashboard',
      description: 'View saved sessions and experiment telemetry',
      icon: Icons.analytics_rounded,
      category: 'Navigation',
      onExecute: () => router.go('/module/neurohub'),
    ),
    NmtkCommand(
      id: 'nav-settings',
      label: 'Open Settings',
      description: 'Configure appearance, API host, and hardware paths',
      icon: Icons.settings_rounded,
      category: 'System',
      onExecute: () => router.go('/settings'),
    ),
    NmtkCommand(
      id: 'action-toggle-sidebar',
      label: 'Toggle Sidebar',
      description: 'Expand or collapse the navigation sidebar',
      icon: Icons.menu_open_rounded,
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
      icon: Icons.handyman_rounded,
      category: 'System',
      onExecute: () {
        ref.read(appStateProvider).toggleDeveloperMode();
      },
    ),

    // --- Action Commands ---
    NmtkCommand(
      id: 'action-reload',
      label: 'Reload Workspace',
      description: 'Refresh the current module state',
      icon: Icons.refresh_rounded,
      category: 'Actions',
      onExecute: () {
        // Just trigger a rebuild/refresh if needed,
        // or re-navigate to same path to trigger refresh
        final current = router.state.uri.toString();
        router.go(current);
      },
    ),
  ];
});
