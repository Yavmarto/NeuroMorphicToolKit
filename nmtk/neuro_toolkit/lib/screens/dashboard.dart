import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/update_service.dart';
import 'package:url_launcher/url_launcher.dart';

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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => controller.checkForUpdates(),
            tooltip: 'Check for Updates',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.go('/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NmtkSurfaceCard(
            title: 'Deployment Workflows',
            subtitle:
                'Jump into hardware-specific deployment flows from the launcher.',
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildDeployButton(
                  context: context,
                  route: '/deploy/akida',
                  icon: Icons.architecture,
                  label: 'Akida Deploy',
                ),
                _buildDeployButton(
                  context: context,
                  route: '/deploy/pynq',
                  icon: Icons.developer_board,
                  label: 'PYNQ Deploy',
                ),
                _buildDeployButton(
                  context: context,
                  route: '/deploy/teensy',
                  icon: Icons.memory,
                  label: 'Teensy Deploy',
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Installed Modules',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          if (moduleState.installedModules.isEmpty)
            const NmtkEmptyState(
              title: 'No Modules Installed',
              message:
                  'No modules installed yet. Go to the Catalog to install modules.',
              icon: Icons.widgets_outlined,
            )
          else
            ...moduleState.installedModules.map(
              (module) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ModuleSummaryCard(
                  module: module,
                  onLaunch: () => controller.launchModule(module.id),
                  onOpen: () => context.go('/tool/${module.id}'),
                  onStop: () => controller.stopModule(module.id),
                  onUninstall: () => controller.uninstallModule(module.id),
                  onUpdate: _hasUpdateAvailable(module)
                      ? () => controller.updateModule(module.id)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static bool _hasUpdateAvailable(Module module) {
    return !module.versionPinned &&
        UpdateService.isNewerVersion(module.version, module.remoteVersion);
  }

  Widget _buildDeployButton({
    required BuildContext context,
    required String route,
    required IconData icon,
    required String label,
  }) {
    return NmtkPrimaryButton(
      onPressed: () => context.go(route),
      icon: icon,
      label: label,
    );
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

class _ModuleSummaryCard extends StatelessWidget {
  final Module module;
  final VoidCallback onLaunch;
  final VoidCallback onOpen;
  final VoidCallback onStop;
  final VoidCallback onUninstall;
  final VoidCallback? onUpdate;

  const _ModuleSummaryCard({
    required this.module,
    required this.onLaunch,
    required this.onOpen,
    required this.onStop,
    required this.onUninstall,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NmtkSurfaceCard(
      title: module.name,
      subtitle: module.description,
      trailing: _buildStatusIndicator(module.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
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
          if (module.status == ModuleStatus.updating)
            _ModuleProgressState(
              label: 'Updating to ${module.remoteVersion}',
              progress: module.installProgress,
            )
          else if (module.status == ModuleStatus.starting)
            const _ModuleActivityState(label: 'Starting module...')
          else if (module.status == ModuleStatus.stopping)
            const _ModuleActivityState(
              label: 'Stopping module...',
              tone: NmtkTone.warning,
            )
          else
            Wrap(
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
                if (module.status == ModuleStatus.installed ||
                    module.status == ModuleStatus.error)
                  Semantics(
                    label: 'Start ${module.name}',
                    button: true,
                    child: NmtkPrimaryButton(
                      onPressed: onLaunch,
                      icon: Icons.play_arrow,
                      label: 'Start',
                    ),
                  ),
                if (module.status == ModuleStatus.running ||
                    module.status == ModuleStatus.degraded) ...[
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
            ),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator(ModuleStatus status) {
    switch (status) {
      case ModuleStatus.running:
        return const NmtkStatusBadge(
          label: 'Running',
          tone: NmtkTone.success,
          icon: Icons.check_circle,
          semanticsLabel: 'Status: Running',
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
      case ModuleStatus.starting:
        return const NmtkStatusBadge(
          label: 'Starting',
          tone: NmtkTone.info,
          icon: Icons.sync,
          semanticsLabel: 'Status: Starting',
        );
      case ModuleStatus.stopping:
        return const NmtkStatusBadge(
          label: 'Stopping',
          tone: NmtkTone.warning,
          icon: Icons.stop_circle_outlined,
          semanticsLabel: 'Status: Stopping',
        );
      case ModuleStatus.updating:
        return const NmtkStatusBadge(
          label: 'Updating',
          tone: NmtkTone.info,
          icon: Icons.system_update,
          semanticsLabel: 'Status: Updating',
        );
      default:
        return const NmtkStatusBadge(
          label: 'Stopped',
          tone: NmtkTone.neutral,
          icon: Icons.pause_circle_outline,
          semanticsLabel: 'Status: Stopped',
        );
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
