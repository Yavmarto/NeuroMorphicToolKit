library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/neurosense_sensor_target.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosense_api_service.dart';

/// A live sensor source configured for this Studio workspace: which
/// NeuroSense device to read from, which channel, and at what sample rate.
///
/// Deliberately separate from the SSH/host-credential pairing used by the
/// compute hardware targets (Akida/PYNQ/SC-NeuroCore) — a sensor is
/// identified by device id + channel + sample rate, not a host/login.
class NeuroSenseSensorConfig {
  const NeuroSenseSensorConfig({
    required this.device,
    required this.channel,
    required this.sampleRateHz,
  });

  final NeurosenseDeviceInfo device;
  final int channel;
  final int sampleRateHz;

  NeuroSenseSensorConfig copyWith({
    NeurosenseDeviceInfo? device,
    int? channel,
    int? sampleRateHz,
  }) {
    return NeuroSenseSensorConfig(
      device: device ?? this.device,
      channel: channel ?? this.channel,
      sampleRateHz: sampleRateHz ?? this.sampleRateHz,
    );
  }
}

/// Devices reported by the NeuroSense backend, refreshed on demand.
final neuroSenseAvailableDevicesProvider =
    FutureProvider.autoDispose<List<NeurosenseDeviceInfo>>((ref) {
      return ref.watch(neurosenseApiServiceProvider).listDevices();
    });

class NeuroSenseSourceNotifier extends Notifier<NeuroSenseSensorConfig?> {
  @override
  NeuroSenseSensorConfig? build() => null;

  void setConfig(NeuroSenseSensorConfig config) => state = config;

  void clear() => state = null;
}

/// The sensor source configured for Studio's NeuroSense workspace, if any.
final neuroSenseSourceProvider =
    NotifierProvider<NeuroSenseSourceNotifier, NeuroSenseSensorConfig?>(
      NeuroSenseSourceNotifier.new,
    );
