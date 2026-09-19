import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/neurosense_sensor_target.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosense_api_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/shell_surface.dart';

/// Launcher-native NeuroSense surface: device scan and quick connect.
class NeurosenseMonitorSurface extends ConsumerStatefulWidget {
  const NeurosenseMonitorSurface({super.key});

  @override
  ConsumerState<NeurosenseMonitorSurface> createState() =>
      _NeurosenseMonitorSurfaceState();
}

class _NeurosenseMonitorSurfaceState
    extends ConsumerState<NeurosenseMonitorSurface> {
  List<NeurosenseDeviceInfo> _devices = const [];
  String? _status;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_scan);
  }

  Future<void> _scan() async {
    setState(() {
      _loading = true;
      _status = null;
    });
    try {
      final devices = await ref.read(neurosenseApiServiceProvider).listDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _status = devices.isEmpty
            ? 'No devices found. Start the NeuroSense worker or use synthetic mode.'
            : '${devices.length} device(s) available.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Scan failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connect(NeurosenseDeviceInfo device) async {
    setState(() => _status = 'Connecting to ${device.name}…');
    try {
      await ref.read(neurosenseApiServiceProvider).connectDevice(
        device.id,
        serialPort: device.serialPort,
        allowExperimental: true,
      );
      if (!mounted) return;
      setState(() => _status = 'Connected to ${device.name}.');
      await _scan();
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Connect failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const NeurocnlScreenHeader(
            eyebrow: 'Instrumentation',
            title: 'NeuroSense',
            subtitle:
                'Scan biosignal devices, connect a board, and record spike-encoded sessions.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _loading ? null : _scan,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(_loading ? 'Scanning…' : 'Scan devices'),
              ),
            ],
          ),
          if (_status != null) ...[
            const SizedBox(height: 12),
            Text(_status!),
          ],
          const SizedBox(height: 16),
          for (final device in _devices)
            Card(
              child: ListTile(
                leading: Icon(
                  device.connected ? Icons.sensors : Icons.sensors_off,
                ),
                title: Text(device.name),
                subtitle: Text(
                  '${device.type} • ${device.channels} ch @ ${device.samplingRateHz} Hz',
                ),
                trailing: device.connected
                    ? const Icon(Icons.check_circle_outline)
                    : TextButton(
                        onPressed: () => _connect(device),
                        child: const Text('Connect'),
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
