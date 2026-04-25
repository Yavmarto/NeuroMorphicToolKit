import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:url_launcher/url_launcher.dart';
// NOTE: The three hardware deploy flows (Akida, PYNQ, Teensy) were relocated
// to the Neurochip module frontend in ADR-claude/0007. They are no longer
// exposed from the launcher dashboard; users reach them by opening the
// Neurochip module workspace.

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(moduleStateProvider);
    final moduleState = ref.watch(moduleStateProvider);
    final theme = Theme.of(context);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (controller.pendingLauncherUpdate != null) {
        _showLauncherUpdateDialog(context, controller);
      }
    });

    if (moduleState.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (moduleState.error != null) {
      return Scaffold(
        body: NmtkEmptyState(
          title: 'Catalog Unavailable',
          message: moduleState.error!,
          icon: Icons.cloud_off,
          tone: NmtkTone.danger,
        ),
      );
    }

    final modules = moduleState.modules;

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Home',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Browse, install, and manage all toolkit modules from one view.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (modules.isEmpty)
            const NmtkEmptyState(
              title: 'No Modules Available',
              message: 'The launcher did not load any modules.',
              icon: Icons.inventory_2_outlined,
            )
          else
            ...modules.map((module) {
              final isMuJoCoUnavailable =
                  module.requiresMuJoCo && !moduleState.isMuJoCoAvailable();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ModuleCard(
                  module: module,
                  isMuJoCoUnavailable: isMuJoCoUnavailable,
                  onInstall: () =>
                      unawaited(controller.installModule(module.id)),
                  onLaunch: () => controller.launchModule(module.id),
                  onOpen: () =>
                      context.go('/workspace?moduleId=${module.id}'),
                  onStop: () => controller.stopModule(module.id),
                  onUninstall: () => controller.uninstallModule(module.id),
                  onUpdate: _hasUpdateAvailable(module)
                      ? () => unawaited(controller.updateModule(module.id))
                      : null,
                ),
              );
            }),
        ],
      ),
    );
  }

  static bool _hasUpdateAvailable(Module module) {
    return !module.versionPinned &&
        UpdateService.isNewerVersion(module.version, module.remoteVersion);
  }

  void _showLauncherUpdateDialog(
    BuildContext context,
    ModuleProvider provider,
  ) {
    final update = provider.pendingLauncherUpdate!;
    final releaseNotes = update.releaseNotes.trim().isEmpty
        ? 'No published release notes were found for this version.'
        : update.releaseNotes;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Launcher Update Available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version of NeuroToolkit (${update.version}) is available.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Release Notes:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(releaseNotes),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              provider.dismissLauncherUpdate();
              Navigator.of(context).pop();
            },
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              final url = Uri.parse(update.url);
              if (await canLaunchUrl(url)) {
                await launchUrl(url);
              }
            },
            child: const Text('Download Now'),
          ),
        ],
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  final Module module;
  final bool isMuJoCoUnavailable;
  final VoidCallback onInstall;
  final VoidCallback onLaunch;
  final VoidCallback onOpen;
  final VoidCallback onStop;
  final VoidCallback onUninstall;
  final VoidCallback? onUpdate;

  const _ModuleCard({
    required this.module,
    required this.isMuJoCoUnavailable,
    required this.onInstall,
    required this.onLaunch,
    required this.onOpen,
    required this.onStop,
    required this.onUninstall,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Opacity(
      opacity: isMuJoCoUnavailable ? 0.55 : 1.0,
      child: NmtkSurfaceCard(
        title: module.name,
        subtitle: module.description,
        leading: Icon(_getIconData(module.icon), size: 28),
        trailing: _buildStatusBadge(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (module.version != '0.0.0')
                  Text(
                    'v${module.version}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (module.versionPinned)
                  const NmtkStatusBadge(
                    label: 'Pinned',
                    tone: NmtkTone.info,
                    icon: Icons.push_pin,
                  ),
              ],
            ),
            if (module.statusMessage != null) ...[
              const SizedBox(height: 12),
              NmtkSurfaceCard(
                tone: module.status == ModuleStatus.error
                    ? NmtkTone.danger
                    : module.status == ModuleStatus.degraded
                        ? NmtkTone.warning
                        : NmtkTone.info,
                padding: const EdgeInsets.all(14),
                child: Text(
                  module.statusMessage!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
            const SizedBox(height: 16),
            _buildActionArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionArea() {
    switch (module.status) {
      case ModuleStatus.installing:
        return _ModuleProgressState(
          label:
              'Installing... ${(module.installProgress * 100).toInt()}%',
          progress: module.installProgress,
        );

      case ModuleStatus.updating:
        return _ModuleProgressState(
          label:
              'Updating to ${module.remoteVersion}... ${(module.installProgress * 100).toInt()}%',
          progress: module.installProgress,
        );

      case ModuleStatus.starting:
        return const _ModuleActivityState(label: 'Starting module...');

      case ModuleStatus.stopping:
        return const _ModuleActivityState(
          label: 'Stopping module...',
          tone: NmtkTone.warning,
        );

      case ModuleStatus.notInstalled:
        return Align(
          alignment: Alignment.centerRight,
          child: Semantics(
            label: 'Install ${module.name}',
            button: true,
            child: NmtkPrimaryButton(
              onPressed: isMuJoCoUnavailable ? null : onInstall,
              icon: Icons.download,
              label: 'Install',
            ),
          ),
        );

      case ModuleStatus.installed:
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (onUpdate != null)
              NmtkPrimaryButton(
                onPressed: onUpdate,
                icon: Icons.system_update,
                label: 'Update to ${module.remoteVersion}',
                tone: NmtkTone.success,
              ),
            Semantics(
              label: 'Start ${module.name}',
              button: true,
              child: NmtkPrimaryButton(
                onPressed: onLaunch,
                icon: Icons.play_arrow,
                label: 'Start',
              ),
            ),
            Semantics(
              label: 'Uninstall ${module.name}',
              button: true,
              child: NmtkOutlinedButton(
                onPressed: onUninstall,
                icon: Icons.delete,
                label: 'Uninstall',
                tone: NmtkTone.danger,
              ),
            ),
          ],
        );

      case ModuleStatus.running:
      case ModuleStatus.degraded:
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (onUpdate != null)
              NmtkPrimaryButton(
                onPressed: onUpdate,
                icon: Icons.system_update,
                label: 'Update to ${module.remoteVersion}',
                tone: NmtkTone.success,
              ),
            Semantics(
              label: 'Open ${module.name} in Workspace',
              button: true,
              child: NmtkPrimaryButton(
                onPressed: onOpen,
                icon: Icons.open_in_new,
                label: 'Open',
              ),
            ),
            Semantics(
              label: 'Stop ${module.name}',
              button: true,
              child: NmtkOutlinedButton(
                onPressed: onStop,
                icon: Icons.stop_circle_outlined,
                label: 'Stop',
                tone: NmtkTone.warning,
              ),
            ),
            Semantics(
              label: 'Uninstall ${module.name}',
              button: true,
              child: NmtkOutlinedButton(
                onPressed: onUninstall,
                icon: Icons.delete,
                label: 'Uninstall',
                tone: NmtkTone.danger,
              ),
            ),
          ],
        );

      case ModuleStatus.error:
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            Semantics(
              label: 'Start ${module.name}',
              button: true,
              child: NmtkPrimaryButton(
                onPressed: onLaunch,
                icon: Icons.play_arrow,
                label: 'Start',
              ),
            ),
            Semantics(
              label: 'Uninstall ${module.name}',
              button: true,
              child: NmtkOutlinedButton(
                onPressed: onUninstall,
                icon: Icons.delete,
                label: 'Uninstall',
                tone: NmtkTone.danger,
              ),
            ),
          ],
        );
    }
  }

  Widget _buildStatusBadge() {
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
          tone: NmtkTone.neutral,
          icon: Icons.download_outlined,
        );
      case ModuleStatus.installing:
        return const NmtkStatusBadge(
          label: 'Installing',
          tone: NmtkTone.info,
          icon: Icons.sync,
          semanticsLabel: 'Status: Installing',
        );
      case ModuleStatus.installed:
        return const NmtkStatusBadge(
          label: 'Installed',
          tone: NmtkTone.success,
          icon: Icons.check_circle_outline,
          semanticsLabel: 'Status: Installed',
        );
      case ModuleStatus.starting:
        return const NmtkStatusBadge(
          label: 'Starting',
          tone: NmtkTone.info,
          icon: Icons.sync,
          semanticsLabel: 'Status: Starting',
        );
      case ModuleStatus.running:
        return const NmtkStatusBadge(
          label: 'Running',
          tone: NmtkTone.success,
          icon: Icons.check_circle,
          semanticsLabel: 'Status: Running',
        );
      case ModuleStatus.stopping:
        return const NmtkStatusBadge(
          label: 'Stopping',
          tone: NmtkTone.warning,
          icon: Icons.stop_circle_outlined,
          semanticsLabel: 'Status: Stopping',
        );
      case ModuleStatus.degraded:
        return const NmtkStatusBadge(
          label: 'Degraded',
          tone: NmtkTone.warning,
          icon: Icons.warning_amber_rounded,
          semanticsLabel: 'Status: Degraded',
        );
      case ModuleStatus.error:
        return const NmtkStatusBadge(
          label: 'Error',
          tone: NmtkTone.danger,
          icon: Icons.error_outline,
          semanticsLabel: 'Status: Error',
        );
      case ModuleStatus.updating:
        return const NmtkStatusBadge(
          label: 'Updating',
          tone: NmtkTone.info,
          icon: Icons.system_update,
          semanticsLabel: 'Status: Updating',
        );
    }
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
}

class _ModuleProgressState extends StatelessWidget {
  final String label;
  final double progress;

  const _ModuleProgressState({required this.label, required this.progress});

  @override
  Widget build(BuildContext context) {
    return NmtkSurfaceCard(
      tone: NmtkTone.info,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: progress),
        ],
      ),
    );
  }
}

class _ModuleActivityState extends StatelessWidget {
  final String label;
  final NmtkTone tone;

  const _ModuleActivityState({required this.label, this.tone = NmtkTone.info});

  @override
  Widget build(BuildContext context) {
    final palette = resolveNmtkTonePalette(context, tone);

    return NmtkSurfaceCard(
      tone: tone,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: palette.foreground,
            ),
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }
}
