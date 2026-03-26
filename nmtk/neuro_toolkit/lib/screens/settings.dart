import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/services/update_service.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Consumer<ModuleProvider>(
        builder: (context, provider, child) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildUpdateChannelTile(provider),
              const Divider(),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16.0),
                child: Text(
                  'Module Version Pinning',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ...provider.installedModules.map((module) => _buildModulePinningTile(provider, module)),
              if (provider.installedModules.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('No modules installed to pin.'),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUpdateChannelTile(ModuleProvider provider) {
    return ListTile(
      title: const Text('Update Channel'),
      subtitle: const Text('Select which version of updates you want to receive'),
      trailing: DropdownButton<UpdateChannel>(
        value: provider.currentChannel,
        onChanged: (UpdateChannel? newValue) {
          if (newValue != null) {
            provider.setUpdateChannel(newValue);
          }
        },
        items: UpdateChannel.values.map<DropdownMenuItem<UpdateChannel>>((UpdateChannel value) {
          return DropdownMenuItem<UpdateChannel>(
            value: value,
            child: Text(value.name.toUpperCase()),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildModulePinningTile(ModuleProvider provider, dynamic module) {
    return SwitchListTile(
      title: Text(module.name),
      subtitle: Text('Current version: v${module.version}'),
      value: module.versionPinned,
      onChanged: (bool value) {
        provider.setVersionPinned(module.id, value);
      },
      secondary: const Icon(Icons.push_pin),
    );
  }
}
