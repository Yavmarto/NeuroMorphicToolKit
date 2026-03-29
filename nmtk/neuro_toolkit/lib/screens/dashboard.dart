import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<ModuleProvider>(context, listen: false);

    // Show launcher update dialog if available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (provider.pendingLauncherUpdate != null) {
        _showLauncherUpdateDialog(context, provider);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.checkForUpdates(),
            tooltip: 'Check for Updates',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.go('/settings'),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Consumer<ModuleProvider>(
        builder: (context, provider, child) {
          final installedModules = provider.installedModules;

          if (installedModules.isEmpty) {
            return const Center(
              child: Text(
                'No modules installed yet. Go to the Catalog to install modules.',
              ),
            );
          }

          return ListView.builder(
            itemCount: installedModules.length,
            itemBuilder: (context, index) {
              final module = installedModules[index];
              return Card(
                margin: const EdgeInsets.all(8.0),
                child: ListTile(
                  title: Wrap(
                    spacing: 8.0,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Semantics(
                        label: 'Module Name',
                        child: Text(module.name, overflow: TextOverflow.ellipsis),
                      ),
                      _buildStatusIndicator(module.status),
                      if (module.versionPinned) ...[
                        const Icon(Icons.push_pin,
                            size: 14, color: Colors.blue),
                      ],
                      Text(
                        'v${module.version}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(module.description),
                      if (module.healthStatus != null)
                        Text(
                          'Health: ${module.healthStatus}',
                          style: TextStyle(
                            fontSize: 12,
                            color: module.status == ModuleStatus.error
                                ? Colors.red
                                : Colors.grey[600],
                            fontWeight: module.status == ModuleStatus.error
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                          maxLines: 3,
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (module.remoteVersion != null &&
                          module.status != ModuleStatus.updating)
                        Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ElevatedButton.icon(
                            onPressed: () => provider.updateModule(module.id),
                            icon: const Icon(Icons.system_update),
                            label: Text('Update to ${module.remoteVersion}'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      if (module.status == ModuleStatus.updating)
                        SizedBox(
                          width: 100,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              LinearProgressIndicator(
                                  value: module.installProgress),
                              const SizedBox(height: 4),
                              const Text('Updating...',
                                  style: TextStyle(fontSize: 10)),
                            ],
                          ),
                        )
                      else if (module.status == ModuleStatus.installed ||
                          module.status == ModuleStatus.error)
                        Semantics(
                          label: 'Start ${module.name}',
                          button: true,
                          child: ElevatedButton(
                            onPressed: () => provider.launchModule(module.id),
                            child: const Text('Start'),
                          ),
                        )
                      else if (module.status == ModuleStatus.starting)
                        const CircularProgressIndicator()
                      else if (module.status == ModuleStatus.running ||
                          module.status == ModuleStatus.degraded)
                        Row(
                          children: [
                            Semantics(
                              label: 'Open ${module.name} in Workspace',
                              button: true,
                              child: ElevatedButton(
                                onPressed: () =>
                                    context.go('/tool/${module.id}'),
                                child: const Text('Open'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Semantics(
                              label: 'Stop ${module.name}',
                              button: true,
                              child: ElevatedButton(
                                onPressed: () => provider.stopModule(module.id),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.orange,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Stop'),
                              ),
                            ),
                          ],
                        )
                      else if (module.status == ModuleStatus.stopping)
                        const CircularProgressIndicator(color: Colors.orange),
                      const SizedBox(width: 8),
                      Semantics(
                        label: 'Uninstall ${module.name}',
                        button: true,
                        child: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            provider.uninstallModule(module.id);
                          },
                          tooltip: 'Uninstall',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildStatusIndicator(ModuleStatus status) {
    Color color;
    String label;
    switch (status) {
      case ModuleStatus.running:
        color = Colors.green;
        label = 'Running';
        break;
      case ModuleStatus.degraded:
        color = Colors.yellow[700]!;
        label = 'Degraded';
        break;
      case ModuleStatus.error:
        color = Colors.red;
        label = 'Error';
        break;
      case ModuleStatus.starting:
        color = Colors.blue;
        label = 'Starting';
        break;
      case ModuleStatus.stopping:
        color = Colors.orange;
        label = 'Stopping';
        break;
      case ModuleStatus.updating:
        color = Colors.purple;
        label = 'Updating';
        break;
      default:
        color = Colors.grey;
        label = 'Stopped';
    }

    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  void _showLauncherUpdateDialog(
      BuildContext context, ModuleProvider provider) {
    final update = provider.pendingLauncherUpdate!;
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
                'A new version of NeuroToolkit (${update.version}) is available.'),
            const SizedBox(height: 16),
            const Text('Release Notes:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            Text(update.releaseNotes),
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
