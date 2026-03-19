import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
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
                  leading: Icon(
                    module.hasFrontend ? Icons.web : Icons.api,
                    color: module.isLaunched ? Colors.green : null,
                  ),
                  title: Text(module.name),
                  subtitle: Text(module.description),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          provider.launchModule(module.id);
                          context.go('/tool/${module.id}');
                        },
                        child: Text(module.isLaunched ? 'View' : 'Launch'),
                      ),
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
}
