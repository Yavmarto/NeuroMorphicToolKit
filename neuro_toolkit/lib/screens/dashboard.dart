import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/module.dart';
import '../providers/module_provider.dart';
import 'tool_view.dart';

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
              child: Text('No modules installed yet. Go to the Catalog to install modules.'),
            );
          }

          return ListView.builder(
            itemCount: installedModules.length,
            itemBuilder: (context, index) {
              final module = installedModules[index];
              return Card(
                margin: const EdgeInsets.all(8.0),
                child: ListTile(
                  title: Text(module.name),
                  subtitle: Text(module.description),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ToolViewScreen(module: module),
                            ),
                          );
                        },
                        child: const Text('Launch'),
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
