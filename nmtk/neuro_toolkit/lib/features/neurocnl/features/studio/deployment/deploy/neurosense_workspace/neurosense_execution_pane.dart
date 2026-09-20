import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_source_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/host_module_navigation.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosense_api_service.dart';

class NeurosenseExecutionPane extends ConsumerStatefulWidget {
  const NeurosenseExecutionPane({super.key, required this.config});

  final NeuroSenseSensorConfig? config;

  @override
  ConsumerState<NeurosenseExecutionPane> createState() =>
      _NeurosenseExecutionPaneState();
}

class _NeurosenseExecutionPaneState
    extends ConsumerState<NeurosenseExecutionPane> {
  String? _status;
  bool _busy = false;

  Future<void> _connect() async {
    final config = widget.config;
    if (config == null) {
      setState(() => _status = 'Configure a sensor source first.');
      return;
    }
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await ref
          .read(neurosenseApiServiceProvider)
          .connectDevice(config.device.id, serialPort: config.device.serialPort);
      if (!mounted) return;
      setState(() => _status = 'Connected to ${config.device.name}.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Connect failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMonitor() async {
    final opened = await openModuleInHost(
      context,
      moduleId: 'Neurosense',
      deepLink: '/',
    );
    if (!opened && mounted) {
      setState(
        () => _status =
            'Could not open NeuroSense from this workspace. Use the launcher nav.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final textStyles = Zeta.of(context).textStyles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Live acquisition',
          style: textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          'Connect the configured sensor source, then open NeuroSense for '
          'recording, encoding presets, and HDF5 session export.',
          style: textStyles.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const Key('neurosense-connect-device'),
              onPressed: _busy ? null : _connect,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.link,
                      size: 18,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
              label: Text(_busy ? 'Connecting…' : 'Connect sensor'),
            ),
            OutlinedButton.icon(
              key: const Key('neurosense-open-monitor'),
              onPressed: _openMonitor,
              icon: Icon(
                Icons.monitor_heart_outlined,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              label: const Text('Open NeuroSense'),
            ),
          ],
        ),
        if (_status != null) ...[
          const SizedBox(height: 8),
          Text(
            _status!,
            style: textStyles.bodySmall.copyWith(
              color: Zeta.of(context).colors.mainSubtle,
            ),
          ),
        ],
      ],
    );
  }
}
