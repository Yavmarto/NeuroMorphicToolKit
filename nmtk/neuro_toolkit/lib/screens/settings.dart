import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:neuro_toolkit/providers/settings_provider.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final TextEditingController _endpointController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = context.read<SettingsProvider>();
    _endpointController.text = settings.remoteEndpoint ?? '';
  }

  @override
  void dispose() {
    _endpointController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final analytics = AnalyticsService();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildTelemetrySection(settings),
          const Divider(),
          _buildCrashLogSection(analytics),
        ],
      ),
    );
  }

  Widget _buildTelemetrySection(SettingsProvider settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Analytics & Telemetry',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SwitchListTile(
          title: const Text('Opt-in Telemetry'),
          subtitle:
              const Text('Share anonymous usage data and performance metrics'),
          value: settings.telemetryEnabled,
          onChanged: (value) => settings.setTelemetryEnabled(value),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _endpointController,
          decoration: const InputDecoration(
            labelText: 'Remote Reporting Endpoint',
            hintText: 'https://example.com/api/logs',
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => settings.setRemoteEndpoint(value),
        ),
      ],
    );
  }

  Widget _buildCrashLogSection(AnalyticsService analytics) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Local Crash Logs',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: () async {
            final logs = await analytics.getLocalLogs();
            if (mounted) {
              _showLogDialog(context, logs);
            }
          },
          icon: const Icon(Icons.history),
          label: const Text('View Local Logs'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () async {
            await analytics.clearLocalLogs();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Local logs cleared')),
              );
            }
          },
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear Local Logs'),
        ),
      ],
    );
  }

  void _showLogDialog(BuildContext context, String logs) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Local Crash Logs'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Text(
              logs,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
