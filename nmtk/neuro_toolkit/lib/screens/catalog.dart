import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/update_service.dart';

/// Catalog screen — content-only widget (no Scaffold; chrome is provided by
/// NmtkDesktopScaffold in the calling screen or the ShellRoute wrapper).
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        CatalogModuleSection(),
      ],
    );
  }
}

class CatalogModuleSection extends ConsumerWidget {
  const CatalogModuleSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(moduleStateProvider);
    final theme = Theme.of(context);
    final shadScheme = ShadTheme.of(context).colorScheme;

    if (provider.isLoading) {
      return const Center(child: ShadProgress());
    }

    if (provider.error != null) {
      return NmtkEmptyState(
        title: 'Catalog Unavailable',
        message: provider.error!,
        icon: Icons.cloud_off,
        tone: NmtkTone.danger,
      );
    }

    final modules = provider.modules;

    if (modules.isEmpty) {
      return const NmtkEmptyState(
        title: 'No Modules Available',
        message: 'The launcher did not load any installable modules.',
        icon: Icons.inventory_2_outlined,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Module Catalog',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Browse, install, update, and remove modules from the toolkit home view.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        ...modules.map((module) {
          final isMuJoCoUnavailable =
              module.requiresMuJoCo && !provider.isMuJoCoAvailable();

          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Opacity(
              opacity: isMuJoCoUnavailable ? 0.55 : 1.0,
              child: NmtkSurfaceCard(
                title: module.name,
                subtitle: module.description,
                leading: Icon(_getIconData(module.icon), size: 28),
                trailing: _buildStatusBadge(
                  module: module,
                  isMuJoCoUnavailable: isMuJoCoUnavailable,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Text(
                          'ID: ${module.id}',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (module.version != '0.0.0')
                          Text(
                            'Version: ${module.version}',
                            style: theme.textTheme.bodySmall,
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (module.status == ModuleStatus.installing ||
                        module.status == ModuleStatus.updating)
                      ShadCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${module.status == ModuleStatus.installing ? "Installing" : "Updating"}... ${(module.installProgress * 100).toInt()}%',
                            ),
                            const SizedBox(height: 10),
                            ShadProgress(value: module.installProgress),
                          ],
                        ),
                      )
                    else if (module.status == ModuleStatus.error)
                      Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            color: shadScheme.destructive,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Installation failed: ${module.healthStatus ?? 'Unknown error'}',
                              style: TextStyle(color: shadScheme.destructive),
                            ),
                          ),
                          Semantics(
                            label: 'Retry installation of ${module.name}',
                            button: true,
                            child: NmtkPrimaryButton(
                              onPressed: () {
                                unawaited(provider.installModule(module.id));
                              },
                              label: 'Retry',
                              icon: Icons.refresh,
                              tone: NmtkTone.danger,
                            ),
                          ),
                        ],
                      )
                    else if (module.status == ModuleStatus.notInstalled)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Semantics(
                          label: 'Install ${module.name}',
                          button: true,
                          child: NmtkPrimaryButton(
                            onPressed: isMuJoCoUnavailable
                                ? null
                                : () {
                                    unawaited(
                                        provider.installModule(module.id));
                                  },
                            icon: Icons.download,
                            label: 'Install',
                          ),
                        ),
                      )
                    else if (module.status == ModuleStatus.installed ||
                        module.status == ModuleStatus.running ||
                        module.status == ModuleStatus.degraded)
                      Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          if (!module.versionPinned &&
                              UpdateService.isNewerVersion(
                                module.version,
                                module.remoteVersion,
                              ))
                            NmtkPrimaryButton(
                              onPressed: () {
                                unawaited(provider.updateModule(module.id));
                              },
                              icon: Icons.system_update,
                              label: 'Update to ${module.remoteVersion}',
                              tone: NmtkTone.info,
                            ),
                          NmtkOutlinedButton(
                            onPressed: () {
                              unawaited(provider.uninstallModule(module.id));
                            },
                            label: module.status == ModuleStatus.installed
                                ? 'Installed'
                                : 'Running',
                            tone: module.status == ModuleStatus.degraded
                                ? NmtkTone.warning
                                : NmtkTone.neutral,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  IconData _getIconData(String iconName) {
    switch (iconName) {
      case 'code':
        return Icons.code;
      case 'architecture':
        return Icons.architecture;
      case 'memory':
        return Icons.memory;
      case 'speed':
        return Icons.speed;
      case 'sensors':
        return Icons.sensors;
      case 'hub':
        return Icons.hub;
      case 'precision_manufacturing':
        return Icons.precision_manufacturing;
      default:
        return Icons.extension;
    }
  }

  Widget _buildStatusBadge({
    required Module module,
    required bool isMuJoCoUnavailable,
  }) {
    if (isMuJoCoUnavailable) {
      return const NmtkStatusBadge(
        label: 'MuJoCo Missing',
        tone: NmtkTone.warning,
        icon: Icons.hardware_outlined,
      );
    }

    switch (module.status) {
      case ModuleStatus.notInstalled:
        return const NmtkStatusBadge(
          label: 'Not Installed',
          tone: NmtkTone.warning,
          icon: Icons.download_outlined,
        );
      case ModuleStatus.installing:
        return const NmtkStatusBadge(
          label: 'Installing',
          tone: NmtkTone.info,
          icon: Icons.sync,
        );
      case ModuleStatus.installed:
        return const NmtkStatusBadge(
          label: 'Installed',
          tone: NmtkTone.success,
          icon: Icons.check_circle_outline,
        );
      case ModuleStatus.starting:
        return const NmtkStatusBadge(
          label: 'Starting',
          tone: NmtkTone.info,
          icon: Icons.play_circle_outline,
        );
      case ModuleStatus.running:
        return const NmtkStatusBadge(
          label: 'Running',
          tone: NmtkTone.success,
          icon: Icons.bolt,
        );
      case ModuleStatus.stopping:
        return const NmtkStatusBadge(
          label: 'Stopping',
          tone: NmtkTone.warning,
          icon: Icons.stop_circle_outlined,
        );
      case ModuleStatus.error:
        return const NmtkStatusBadge(
          label: 'Error',
          tone: NmtkTone.danger,
          icon: Icons.error_outline,
        );
      case ModuleStatus.degraded:
        return const NmtkStatusBadge(
          label: 'Degraded',
          tone: NmtkTone.warning,
          icon: Icons.warning_amber_rounded,
        );
      case ModuleStatus.updating:
        return const NmtkStatusBadge(
          label: 'Updating',
          tone: NmtkTone.info,
          icon: Icons.system_update,
        );
    }
  }
}
