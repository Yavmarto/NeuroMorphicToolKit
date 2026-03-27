import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';

class SettingsProvider with ChangeNotifier {
  static const String _telemetryKey = 'telemetry_enabled';
  static const String _endpointKey = 'remote_endpoint';

  bool _telemetryEnabled = false;
  String? _remoteEndpoint;
  late final SharedPreferences _prefs;
  bool _initialized = false;

  bool get telemetryEnabled => _telemetryEnabled;
  String? get remoteEndpoint => _remoteEndpoint;
  bool get initialized => _initialized;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _telemetryEnabled = _prefs.getBool(_telemetryKey) ?? false;
    _remoteEndpoint = _prefs.getString(_endpointKey);

    // Sync with AnalyticsService
    final analytics = AnalyticsService();
    analytics.telemetryEnabled = _telemetryEnabled;
    analytics.remoteEndpoint = _remoteEndpoint;

    _initialized = true;
    notifyListeners();
  }

  Future<void> setTelemetryEnabled(bool value) async {
    _telemetryEnabled = value;
    await _prefs.setBool(_telemetryKey, value);
    AnalyticsService().telemetryEnabled = value;
    notifyListeners();
  }

  Future<void> setRemoteEndpoint(String? value) async {
    _remoteEndpoint = value;
    if (value == null || value.isEmpty) {
      await _prefs.remove(_endpointKey);
    } else {
      await _prefs.setString(_endpointKey, value);
    }
    AnalyticsService().remoteEndpoint = value;
    notifyListeners();
  }
}
