import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              _buildSectionHeader(context, 'Appearance'),
              ListTile(
                title: const Text('Theme Mode'),
                trailing: DropdownButton<ThemeMode>(
                  value: settings.themeMode,
                  onChanged: (ThemeMode? mode) {
                    if (mode != null) {
                      settings.setThemeMode(mode);
                    }
                  },
                  items: const [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text('System'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text('Light'),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text('Dark'),
                    ),
                  ],
                ),
              ),
              SwitchListTile(
                title: const Text('High Contrast'),
                subtitle: const Text('Increase color contrast for better visibility'),
                value: settings.isHighContrast,
                onChanged: (bool value) {
                  settings.setHighContrast(value);
                },
              ),
              const Divider(),
              _buildSectionHeader(context, 'Accessibility'),
              ListTile(
                title: const Text('Font Size'),
                subtitle: Text('Scale: ${settings.fontSizeFactor.toStringAsFixed(2)}x'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Slider(
                  value: settings.fontSizeFactor,
                  min: 0.8,
                  max: 1.5,
                  divisions: 7,
                  label: settings.fontSizeFactor.toStringAsFixed(2),
                  onChanged: (double value) {
                    settings.setFontSizeFactor(value);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
