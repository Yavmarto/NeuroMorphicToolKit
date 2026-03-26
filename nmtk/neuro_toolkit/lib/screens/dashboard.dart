import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashboard'),
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
                  title: Row(
                    children: [
                      Text(module.name),
                      const SizedBox(width: 8),
                      _buildStatusIndicator(module.status),
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
                      if (module.status == ModuleStatus.installed ||
                          module.status == ModuleStatus.error)
                        ElevatedButton(
                          onPressed: () => provider.launchModule(module.id),
                          child: const Text('Start'),
                        )
                      else if (module.status == ModuleStatus.starting)
                        const CircularProgressIndicator()
                      else if (module.status == ModuleStatus.running ||
                          module.status == ModuleStatus.degraded)
                        Row(
                          children: [
                            ElevatedButton(
                              onPressed: () => context.go('/tool/${module.id}'),
                              child: const Text('Open'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => provider.stopModule(module.id),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Stop'),
                            ),
                          ],
                        )
                      else if (module.status == ModuleStatus.stopping)
                        const CircularProgressIndicator(color: Colors.orange),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          provider.uninstallModule(module.id);
                        },
                        tooltip: 'Uninstall',
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
      default:
        color = Colors.grey;
        label = 'Stopped';
    }

    return Container(
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
    );
  }
}
