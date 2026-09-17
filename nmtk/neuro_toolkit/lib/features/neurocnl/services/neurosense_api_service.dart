import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/neurosense_sensor_target.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';

final neurosenseApiServiceProvider = Provider<NeurosenseApiService>((ref) {
  return NeurosenseApiService(ref.watch(apiClientProvider));
});

class NeurosenseApiService {
  NeurosenseApiService(this._client);

  final ApiClient _client;

  Future<List<NeurosenseDeviceInfo>> listDevices() async {
    final response = await _client.getNeurosenseJson('/devices');
    if (response is! List) {
      return const [];
    }
    return response
        .whereType<Map<String, dynamic>>()
        .map(NeurosenseDeviceInfo.fromJson)
        .toList(growable: false);
  }

  Future<List<NeurosenseAcquisitionPreset>> listPresets() async {
    final response = await _client.getNeurosenseJson('/presets');
    if (response is! List) {
      return const [];
    }
    return response
        .whereType<Map<String, dynamic>>()
        .map(NeurosenseAcquisitionPreset.fromJson)
        .toList(growable: false);
  }

  Future<void> connectDevice(
    String deviceId, {
    String? serialPort,
    bool allowExperimental = false,
  }) async {
    await _client.postNeurosenseJson(
      '/devices/$deviceId/connect?allow_experimental=$allowExperimental',
      serialPort == null || serialPort.isEmpty
          ? const <String, dynamic>{}
          : {'serial_port': serialPort},
    );
  }

  Future<void> disconnectDevice(String deviceId) async {
    await _client.postNeurosenseJson('/devices/$deviceId/disconnect', {});
  }
}
