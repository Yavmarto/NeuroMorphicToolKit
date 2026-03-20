import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';

class CatalogScreen extends StatelessWidget {
  const CatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Module Catalog'),
      ),
      body: Consumer<ModuleProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
            );
          }

          if (provider.error != null) {
            return Center(
              child: Text(provider.error!),
            );
          }

          final modules = provider.modules;

          if (modules.isEmpty) {
            return const Center(
              child: Text('No modules available.'),
            );
          }

          return ListView.builder(
            itemCount: modules.length,
            itemBuilder: (context, index) {
              final module = modules[index];
              final isMuJoCoUnavailable = module.requiresMuJoCo && !provider.isMuJoCoAvailable();

              return Opacity(
                opacity: isMuJoCoUnavailable ? 0.5 : 1.0,
                child: Card(
                  margin: const EdgeInsets.all(8.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(_getIconData(module.icon), size: 32),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    module.name,
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  Text(
                                    'ID: ${module.id}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            _buildStatusBadge(context, module, isMuJoCoUnavailable),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(module.description),
                        const SizedBox(height: 16),
                        if (module.status == ModuleStatus.installing)
                          Column(
                            children: [
                              LinearProgressIndicator(
                                value: module.installProgress,
                              ),
                              const SizedBox(height: 8),
                              Text('${(module.installProgress * 100).toInt()}%'),
                            ],
                          )
                        else if (module.status == ModuleStatus.error)
                          Row(
                            children: [
                              const Icon(Icons.error_outline, color: Colors.red),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Installation failed: ${module.healthStatus ?? "Unknown error"}',
                                  style: const TextStyle(color: Colors.red),
                                ),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  provider.installModule(module.id);
                                },
                                child: const Text('Retry'),
                              ),
                            ],
                          )
                        else if (module.status == ModuleStatus.notInstalled)
                          Align(
                            alignment: Alignment.centerRight,
                            child: ElevatedButton(
                              onPressed: isMuJoCoUnavailable
                                  ? null
                                  : () {
                                      provider.installModule(module.id);
                                    },
                              child: const Text('Install'),
                            ),
                          )
                        else if (module.status == ModuleStatus.installed ||
                                 module.status == ModuleStatus.running ||
                                 module.status == ModuleStatus.degraded)
                          Align(
                            alignment: Alignment.centerRight,
                            child: OutlinedButton(
                              onPressed: () {
                                provider.uninstallModule(module.id);
                              },
                              child: Text(module.status == ModuleStatus.installed
                                  ? 'Installed'
                                  : 'Running'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
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

  Widget _buildStatusBadge(BuildContext context, Module module, bool isMuJoCoUnavailable) {
    String text;
    Color color;

    if (isMuJoCoUnavailable) {
      text = 'MuJoCo Missing';
      color = Colors.grey;
    } else {
      switch (module.status) {
        case ModuleStatus.notInstalled:
          text = 'Not Installed';
          color = Colors.orange;
          break;
        case ModuleStatus.installing:
          text = 'Installing';
          color = Colors.blue;
          break;
        case ModuleStatus.installed:
          text = 'Installed';
          color = Colors.green;
          break;
        case ModuleStatus.starting:
          text = 'Starting';
          color = Colors.blue;
          break;
        case ModuleStatus.running:
          text = 'Running';
          color = Colors.teal;
          break;
        case ModuleStatus.stopping:
          text = 'Stopping';
          color = Colors.orange;
          break;
        case ModuleStatus.error:
          text = 'Error';
          color = Colors.red;
          break;
        case ModuleStatus.degraded:
          text = 'Degraded';
          color = Colors.yellow.shade700;
          break;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
