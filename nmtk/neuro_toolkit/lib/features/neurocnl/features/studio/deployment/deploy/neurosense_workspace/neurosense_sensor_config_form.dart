library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/neurosense_sensor_target.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/deployment/deploy/neurosense_workspace/neurosense_source_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/shared/studio_shared.dart';

/// Device/channel/sample-rate picker for a live NeuroSense sensor source.
///
/// This is NOT the SSH/host-credential `AddHardwareTargetForm` used by the
/// compute hardware targets — a sensor is configured by picking a reported
/// device, one of its channels, and a sample rate, not a host + login.
class NeurosenseSensorConfigForm extends ConsumerStatefulWidget {
  const NeurosenseSensorConfigForm({
    super.key,
    this.initialConfig,
    required this.onCancel,
    required this.onSave,
  });

  final NeuroSenseSensorConfig? initialConfig;
  final VoidCallback onCancel;
  final ValueChanged<NeuroSenseSensorConfig> onSave;

  @override
  ConsumerState<NeurosenseSensorConfigForm> createState() =>
      _NeurosenseSensorConfigFormState();
}

class _NeurosenseSensorConfigFormState
    extends ConsumerState<NeurosenseSensorConfigForm> {
  NeurosenseDeviceInfo? _selectedDevice;
  int _channel = 0;
  int _sampleRateHz = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialConfig;
    if (initial != null) {
      _selectedDevice = initial.device;
      _channel = initial.channel;
      _sampleRateHz = initial.sampleRateHz;
    }
  }

  void _selectDevice(NeurosenseDeviceInfo device) {
    setState(() {
      _selectedDevice = device;
      _channel = 0;
      _sampleRateHz = device.samplingRateHz;
    });
  }

  bool get _canSave => _selectedDevice != null && _sampleRateHz > 0;

  void _save() {
    final device = _selectedDevice;
    if (device == null) return;
    widget.onSave(
      NeuroSenseSensorConfig(
        device: device,
        channel: _channel,
        sampleRateHz: _sampleRateHz,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textStyles = Zeta.of(context).textStyles;
    final devicesAsync = ref.watch(neuroSenseAvailableDevicesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Configure sensor source',
          style: textStyles.titleMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text('Device', style: textStyles.bodyMedium),
        const SizedBox(height: 4),
        devicesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          ),
          error: (error, _) => Text(
            'Could not list NeuroSense devices: $error',
            style: textStyles.bodySmall.copyWith(
              color: Zeta.of(context).colors.mainNegative,
            ),
          ),
          data: (devices) {
            if (devices.isEmpty) {
              return const StudioPhaseBanner(
                label: 'No NeuroSense devices reported by the backend.',
                tone: NmtkTone.warning,
              );
            }
            return DropdownButtonFormField<String>(
              key: const Key('neurosense-device-dropdown'),
              initialValue: _selectedDevice?.id,
              items: [
                for (final device in devices)
                  DropdownMenuItem(
                    value: device.id,
                    child: Text('${device.name} (${device.type})'),
                  ),
              ],
              onChanged: (id) {
                final device = devices.firstWhere((d) => d.id == id);
                _selectDevice(device);
              },
            );
          },
        ),
        const SizedBox(height: 16),
        Text('Channel', style: textStyles.bodyMedium),
        const SizedBox(height: 4),
        DropdownButtonFormField<int>(
          key: const Key('neurosense-channel-dropdown'),
          initialValue: _channel,
          items: [
            for (var i = 0; i < (_selectedDevice?.channels ?? 1).clamp(1, 1 << 20); i++)
              DropdownMenuItem(value: i, child: Text('Channel $i')),
          ],
          onChanged: _selectedDevice == null
              ? null
              : (value) => setState(() => _channel = value ?? 0),
        ),
        const SizedBox(height: 16),
        Text('Sample rate (Hz)', style: textStyles.bodyMedium),
        const SizedBox(height: 4),
        TextFormField(
          key: const Key('neurosense-sample-rate-field'),
          enabled: _selectedDevice != null,
          initialValue: _sampleRateHz == 0 ? '' : '$_sampleRateHz',
          keyboardType: TextInputType.number,
          onChanged: (value) =>
              setState(() => _sampleRateHz = int.tryParse(value) ?? 0),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('neurosense-sensor-config-save'),
              onPressed: _canSave ? _save : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}
