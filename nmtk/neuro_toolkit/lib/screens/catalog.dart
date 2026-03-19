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
          final availableModules = provider.availableModules;

          if (availableModules.isEmpty) {
            return const Center(
              child: Text('All modules are installed.'),
            );
          }

          return ListView.builder(
            itemCount: availableModules.length,
            itemBuilder: (context, index) {
              final module = availableModules[index];
              return Card(
                margin: const EdgeInsets.all(8.0),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        module.name,
                        style: Theme.of(context).textTheme.titleLarge,
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
                             Expanded(child: Text('Installation failed: ${module.healthStatus ?? "Unknown error"}', style: const TextStyle(color: Colors.red))),
                             ElevatedButton(
                                onPressed: () {
                                  provider.installModule(module.id);
                                },
                                child: const Text('Retry'),
                              ),
                           ],
                         )
                      else
                        Align(
                          alignment: Alignment.centerRight,
                          child: ElevatedButton(
                            onPressed: () {
                              provider.installModule(module.id);
                            },
                            child: const Text('Install'),
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
}
