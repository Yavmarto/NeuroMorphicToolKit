import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/speck_paired_device.dart';

final speckTargetServiceProvider = Provider<SpeckTargetService>((ref) {
  return SpeckTargetService();
});

class SpeckTargetService {
  static const String _prefsKey = 'speck_paired_devices';

  Future<List<SpeckPairedDevice>> fetchDevices() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return const <SpeckPairedDevice>[];
    }
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      return const <SpeckPairedDevice>[];
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(SpeckPairedDevice.fromJson)
        .toList(growable: false);
  }

  Future<SpeckPairedDevice> saveDevice({
    String? deviceId,
    required String displayName,
    required String deviceIdentifier,
    bool isDefault = false,
    bool sameHostAsBackend = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var devices = await fetchDevices();
    final id = (deviceId == null || deviceId.isEmpty)
        ? 'speck_${DateTime.now().millisecondsSinceEpoch}'
        : deviceId;
    final saved = SpeckPairedDevice(
      id: id,
      displayName: displayName,
      deviceIdentifier: deviceIdentifier,
      isDefault: isDefault,
      sameHostAsBackend: sameHostAsBackend,
    );

    if (isDefault) {
      devices = devices
          .map((device) => device.id == id ? device : device.copyWith(isDefault: false))
          .toList();
    }

    final index = devices.indexWhere((device) => device.id == id);
    if (index >= 0) {
      devices[index] = saved;
    } else {
      devices = [...devices, saved];
    }

    await prefs.setString(
      _prefsKey,
      jsonEncode(devices.map((device) => device.toJson()).toList()),
    );
    return saved;
  }
}
