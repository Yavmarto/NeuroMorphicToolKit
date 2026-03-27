import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_toolkit/services/analytics_service.dart';

class SettingsProvider with ChangeNotifier {
  static const String _telemetryKey = 'telemetry_enabled';
  static const String _endpointKey = 'remote_endpoint';
  static const String _themeModeKey = 'theme_mode';
  static const String _highContrastKey = 'high_contrast';
  static const String _fontSizeFactorKey = 'font_size_factor';

  bool _telemetryEnabled = false;
  String? _remoteEndpoint;
  ThemeMode _themeMode = ThemeMode.system;
  bool _isHighContrast = false;
  double _fontSizeFactor = 1.0;
  late final SharedPreferences _prefs;
  bool _initialized = false;

  bool get telemetryEnabled => _telemetryEnabled;
  String? get remoteEndpoint => _remoteEndpoint;
  bool get initialized => _initialized;
  ThemeMode get themeMode => _themeMode;
  bool get isHighContrast => _isHighContrast;
  double get fontSizeFactor => _fontSizeFactor;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _telemetryEnabled = _prefs.getBool(_telemetryKey) ?? false;
    _remoteEndpoint = _prefs.getString(_endpointKey);
    _themeMode = ThemeMode.values[_prefs.getInt(_themeModeKey) ?? 0];
    _isHighContrast = _prefs.getBool(_highContrastKey) ?? false;
    _fontSizeFactor = _prefs.getDouble(_fontSizeFactorKey) ?? 1.0;

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

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _prefs.setInt(_themeModeKey, mode.index);
    notifyListeners();
  }

  Future<void> setHighContrast(bool value) async {
    _isHighContrast = value;
    await _prefs.setBool(_highContrastKey, value);
    notifyListeners();
  }

  Future<void> setFontSizeFactor(double value) async {
    _fontSizeFactor = value.clamp(0.8, 2.0);
    await _prefs.setDouble(_fontSizeFactorKey, _fontSizeFactor);
    notifyListeners();
  }
}
