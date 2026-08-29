import 'package:flutter/material.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart' show NmtkSection;

import 'package:neuro_toolkit/features/neurocnl/models/sensor_frame.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/hardware_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/sensor_time_series_chart.dart';

/// Displays live telemetry preview: disconnected placeholder, waiting
/// placeholder, chart + latest-frame readout.
class HardwareSensorPanel extends StatelessWidget {
  const HardwareSensorPanel({super.key, required this.state});

  final HardwareState state;

  @override
  Widget build(BuildContext context) {
    // zeta-card-reduction Task 10: NeurocnlSectionCard → NmtkSection.
    return NmtkSection(
      title: 'Telemetry Preview',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!state.isConnected)
            const _TelemetryPlaceholder(
              message:
                  'Connect to a device to preview local telemetry before handing off to NeuroSense or Neurochip',
            )
          else if (state.sensorData.isEmpty)
            const _TelemetryPlaceholder(
              message: 'Waiting for telemetry preview data…',
            )
          else ...[
            SensorTimeSeriesChart(frames: state.sensorData),
            const Divider(),
            _LatestFrame(frame: state.sensorData.last),
          ],
        ],
      ),
    );
  }
}

// ── Private sub-widgets ────────────────────────────────────────────────────

class _TelemetryPlaceholder extends StatelessWidget {
  const _TelemetryPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(message),
      ),
    );
  }
}

class _LatestFrame extends StatelessWidget {
  const _LatestFrame({required this.frame});

  final SensorFrame frame;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Timestamp: ${frame.timestamp.toStringAsFixed(3)} s',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        for (int i = 0; i < frame.emgChannels.length; i++)
          Text('EMG ${i + 1}: ${frame.emgChannels[i].toStringAsFixed(4)}'),
        if (frame.eegBands != null)
          for (final entry in frame.eegBands!.entries)
            Text('EEG ${entry.key}: ${entry.value.toStringAsFixed(4)}'),
        if (frame.proximity != null)
          Text('Proximity: ${frame.proximity!.toStringAsFixed(2)}'),
      ],
    );
  }
}
