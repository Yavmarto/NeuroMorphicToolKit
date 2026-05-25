import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/update_service.dart';

/// A scrollable grid of module cards.
///
/// Used as the [ToolViewScreen] empty state (full-screen) and as a bottom
/// sheet when the user taps "+" in the workspace tab bar. The panel is
/// stateless — all lifecycle actions delegate to [moduleStateProvider].
class ModulePickerPanel extends ConsumerWidget {
  const ModulePickerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moduleState = ref.watch(moduleStateProvider);
    final controller = ref.read(moduleStateProvider);
    final theme = Theme.of(context);

    if (moduleState.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (moduleState.error != null) {
      return NmtkEmptyState(
        title: 'Catalog Unavailable',
        message: moduleState.error!,
        icon: Icons.cloud_off,
        tone: NmtkTone.danger,
      );
    }

    final modules = moduleState.modules;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Modules',
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Browse, install, and launch toolkit modules.',
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
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 12.0;
              final crossAxisCount = constraints.maxWidth >= 900
                  ? 3
                  : constraints.maxWidth >= 600
                      ? 2
                      : 1;
              final cardWidth =
                  (constraints.maxWidth - spacing * (crossAxisCount - 1)) /
                      crossAxisCount;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: modules.map((module) {
                  final isMuJoCoUnavailable =
                      module.requiresMuJoCo && !moduleState.isMuJoCoAvailable();
                  return SizedBox(
                    width: cardWidth,
                    child: _ModuleCard(
                      module: module,
                      isMuJoCoUnavailable: isMuJoCoUnavailable,
                      onInstall: () => controller.installModule(module.id),
                      onLaunch: () => controller.launchModule(module.id),
                      onOpen: () =>
                          context.go('/workspace?moduleId=${module.id}'),
                      onStop: () => controller.stopModule(module.id),
                      onUpdate: _hasUpdateAvailable(module)
                          ? () => unawaited(controller.updateModule(module.id))
                          : null,
                    ),
                  );
                }).toList(),
              );
            },
          ),
      ],
    );
  }

  static bool _hasUpdateAvailable(Module module) {
    return !module.versionPinned &&
        UpdateService.isNewerVersion(module.version, module.remoteVersion);
  }
}

// ---------------------------------------------------------------------------
// Module card
// ---------------------------------------------------------------------------

class _ModuleCard extends StatelessWidget {
  final Module module;
  final bool isMuJoCoUnavailable;
  final VoidCallback onInstall;
  final VoidCallback onLaunch;
  final VoidCallback onOpen;
  final VoidCallback onStop;
  final VoidCallback? onUpdate;

  const _ModuleCard({
    required this.module,
    required this.isMuJoCoUnavailable,
    required this.onInstall,
    required this.onLaunch,
    required this.onOpen,
    required this.onStop,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final statusTone = module.status == ModuleStatus.error
        ? NmtkTone.danger
        : module.status == ModuleStatus.degraded
            ? NmtkTone.warning
            : NmtkTone.info;

    return Opacity(
      opacity: isMuJoCoUnavailable ? 0.55 : 1.0,
      child: NmtkSurfaceCard(
        title: module.name,
        subtitle: module.description,
        leading: Icon(_iconDataFor(module.icon), size: 28),
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
              const SizedBox(height: 8),
              _StatusMessageBar(
                message: module.statusMessage!,
                tone: statusTone,
                moduleName: module.name,
              ),
            ],
            const SizedBox(height: 12),
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
          label: 'Installing... ${(module.installProgress * 100).toInt()}%',
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
        return Semantics(
          label: 'Install ${module.name}',
          button: true,
          child: NmtkPrimaryButton(
            onPressed: onInstall,
            icon: Icons.download_outlined,
            label: 'Install',
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
          ],
        );

      case ModuleStatus.error:
        return Semantics(
          label: 'Retry starting ${module.name}',
          button: true,
          child: NmtkPrimaryButton(
            onPressed: onLaunch,
            icon: Icons.play_arrow,
            label: 'Start',
          ),
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

  static IconData _iconDataFor(String iconName) {
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

// ---------------------------------------------------------------------------
// Status message bar
// ---------------------------------------------------------------------------

class _StatusMessageBar extends StatelessWidget {
  final String message;
  final NmtkTone tone;
  final String moduleName;

  const _StatusMessageBar({
    required this.message,
    required this.tone,
    required this.moduleName,
  });

  @override
  Widget build(BuildContext context) {
    final palette = resolveNmtkTonePalette(context, tone);
    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: palette.foreground,
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.background,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            Icon(_toneIcon(tone), size: 12, color: palette.foreground),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                message,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
            const SizedBox(width: 4),
            InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () => _showInfoDialog(context),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.info_outline,
                  size: 13,
                  color: palette.foreground,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$moduleName — Status'),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          ZetaButton.text(
            onPressed: () => Navigator.of(ctx).pop(),
            label: 'Close',
          ),
        ],
      ),
    );
  }

  static IconData _toneIcon(NmtkTone tone) {
    switch (tone) {
      case NmtkTone.danger:
        return Icons.error_outline;
      case NmtkTone.warning:
        return Icons.warning_amber_rounded;
      case NmtkTone.info:
        return Icons.info_outline;
      case NmtkTone.success:
        return Icons.check_circle_outline;
      case NmtkTone.neutral:
        return Icons.circle_outlined;
    }
  }
}

// ---------------------------------------------------------------------------
// Progress / activity states
// ---------------------------------------------------------------------------

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
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}
