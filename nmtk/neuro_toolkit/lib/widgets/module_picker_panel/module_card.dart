part of '../module_picker_panel.dart';

class _ModuleCard extends StatelessWidget {
  final Module module;
  final bool isMuJoCoUnavailable;
  final VoidCallback onInstall;
  final VoidCallback onLaunch;
  final VoidCallback onOpen;
  final VoidCallback onStop;
  final VoidCallback? onUpdate;
  final VoidCallback? onRepair;

  const _ModuleCard({
    required this.module,
    required this.isMuJoCoUnavailable,
    required this.onInstall,
    required this.onLaunch,
    required this.onOpen,
    required this.onStop,
    required this.onUpdate,
    this.onRepair,
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
                    icon: ZetaIcons.push_pin,
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
          child: ZetaButton.primary(
            onPressed: onInstall,
            leadingIcon: ZetaIcons.download,
            label: 'Install',
          ),
        );

      case ModuleStatus.installed:
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (onUpdate != null)
              ZetaButton.primary(
                onPressed: onUpdate,
                leadingIcon: Icons
                    .system_update, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                label: 'Update to ${module.remoteVersion}',
              ),
            Semantics(
              label: 'Start ${module.name}',
              button: true,
              child: ZetaButton.primary(
                onPressed: onLaunch,
                leadingIcon: ZetaIcons.play,
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
              ZetaButton.primary(
                onPressed: onUpdate,
                leadingIcon: Icons
                    .system_update, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
                label: 'Update to ${module.remoteVersion}',
              ),
            Semantics(
              label: 'Open ${module.name} in Workspace',
              button: true,
              child: ZetaButton.primary(
                onPressed: onOpen,
                leadingIcon: ZetaIcons.open_in_new_window,
                label: 'Open',
              ),
            ),
            Semantics(
              label: 'Stop ${module.name}',
              button: true,
              child: ZetaButton.outline(
                onPressed: onStop,
                leadingIcon: ZetaIcons.stop_circle,
                label: 'Stop',
              ),
            ),
          ],
        );

      case ModuleStatus.error:
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (onRepair != null)
              Semantics(
                label: 'Repair ${module.name}',
                button: true,
                child: ZetaButton.primary(
                  onPressed: onRepair,
                  leadingIcon: ZetaIcons.build,
                  label: 'Repair',
                ),
              ),
            Semantics(
              label: 'Retry starting ${module.name}',
              button: true,
              child: ZetaButton.primary(
                onPressed: onLaunch,
                leadingIcon: ZetaIcons.play,
                label: 'Start',
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
        icon: Icons
            .hardware_outlined, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      );
    }
    switch (module.status) {
      case ModuleStatus.notInstalled:
        return const NmtkStatusBadge(
          label: 'Not Installed',
          tone: NmtkTone.neutral,
          icon: ZetaIcons.download,
        );
      case ModuleStatus.installing:
        return const NmtkStatusBadge(
          label: 'Installing',
          tone: NmtkTone.info,
          icon: ZetaIcons.sync,
          semanticsLabel: 'Status: Installing',
        );
      case ModuleStatus.installed:
        return const NmtkStatusBadge(
          label: 'Installed',
          tone: NmtkTone.success,
          icon: ZetaIcons.check_circle_outline,
          semanticsLabel: 'Status: Installed',
        );
      case ModuleStatus.starting:
        return const NmtkStatusBadge(
          label: 'Starting',
          tone: NmtkTone.info,
          icon: ZetaIcons.sync,
          semanticsLabel: 'Status: Starting',
        );
      case ModuleStatus.running:
        return const NmtkStatusBadge(
          label: 'Running',
          tone: NmtkTone.success,
          icon: ZetaIcons.check_circle,
          semanticsLabel: 'Status: Running',
        );
      case ModuleStatus.stopping:
        return const NmtkStatusBadge(
          label: 'Stopping',
          tone: NmtkTone.warning,
          icon: ZetaIcons.stop_circle,
          semanticsLabel: 'Status: Stopping',
        );
      case ModuleStatus.degraded:
        return const NmtkStatusBadge(
          label: 'Degraded',
          tone: NmtkTone.warning,
          icon: ZetaIcons.warning_outline,
          semanticsLabel: 'Status: Degraded',
        );
      case ModuleStatus.error:
        return const NmtkStatusBadge(
          label: 'Error',
          tone: NmtkTone.danger,
          icon: ZetaIcons.error_outline,
          semanticsLabel: 'Status: Error',
        );
      case ModuleStatus.updating:
        return const NmtkStatusBadge(
          label: 'Updating',
          tone: NmtkTone.info,
          icon:
              Icons.system_update, // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
          semanticsLabel: 'Status: Updating',
        );
    }
  }

  static IconData _iconDataFor(String iconName) {
    switch (iconName) {
      case 'code':
        return Icons.code; // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      case 'architecture':
        return Icons.architecture; // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      case 'memory':
        return ZetaIcons.memory;
      case 'speed':
        return Icons.speed; // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      case 'sensors':
        return Icons.sensors; // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      case 'hub':
        return Icons.hub; // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      case 'precision_manufacturing':
        return Icons
            .precision_manufacturing; // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
      default:
        return Icons.extension; // ZETA-MIGRATION-EXEMPT: no Zeta equivalent
    }
  }
}

// ---------------------------------------------------------------------------
// Status message bar
// ---------------------------------------------------------------------------
