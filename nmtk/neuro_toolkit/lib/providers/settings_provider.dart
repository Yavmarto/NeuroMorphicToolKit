import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'package:neuro_toolkit/services/analytics_service.dart';

enum LogLevel { info, debug, warning, error, critical }

class SettingsProvider with ChangeNotifier {
  static const String _telemetryKey = 'telemetry_enabled';
  static const String _endpointKey = 'remote_endpoint';
  static const String _themeModeKey = 'theme_mode';
  static const String _highContrastKey = 'high_contrast';
  static const String _fontSizeFactorKey = 'font_size_factor';
  static const String _logLevelKey = 'log_level';
  static const String _moduleSettingsKey = 'module_settings';

  bool _telemetryEnabled = false;
  String? _remoteEndpoint;
  ThemeMode _themeMode = ThemeMode.system;
  bool _isHighContrast = false;
  double _fontSizeFactor = 1.0;
  LogLevel _logLevel = LogLevel.info;
  Map<String, Map<String, dynamic>> _moduleSettings = {};

  late final SharedPreferences _prefs;
  bool _initialized = false;

  bool get telemetryEnabled => _telemetryEnabled;
  String? get remoteEndpoint => _remoteEndpoint;
  bool get initialized => _initialized;
  ThemeMode get themeMode => _themeMode;
  bool get isHighContrast => _isHighContrast;
  double get fontSizeFactor => _fontSizeFactor;
  LogLevel get logLevel => _logLevel;

  Map<String, dynamic> getModuleSettings(String moduleId) {
    return _moduleSettings[moduleId] ?? {};
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _telemetryEnabled = _prefs.getBool(_telemetryKey) ?? false;
    _remoteEndpoint = _prefs.getString(_endpointKey);
    _themeMode = ThemeMode.values[_prefs.getInt(_themeModeKey) ?? 0];
    _isHighContrast = _prefs.getBool(_highContrastKey) ?? false;
    _fontSizeFactor = _prefs.getDouble(_fontSizeFactorKey) ?? 1.0;
    _logLevel = LogLevel.values[_prefs.getInt(_logLevelKey) ?? 0];

    final String? moduleSettingsJson = _prefs.getString(_moduleSettingsKey);
    if (moduleSettingsJson != null) {
      try {
        final Map<String, dynamic> decoded =
            jsonDecode(moduleSettingsJson) as Map<String, dynamic>;
        _moduleSettings = decoded
            .map((key, value) => MapEntry(key, value as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Error decoding module settings: $e');
      }
    }

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

  Future<void> setLogLevel(LogLevel level) async {
    _logLevel = level;
    await _prefs.setInt(_logLevelKey, level.index);
    notifyListeners();
  }

  Future<void> updateModuleSettings(
      String moduleId, Map<String, dynamic> settings) async {
    final currentSettings = _moduleSettings[moduleId] ?? {};
    final newSettings = Map<String, dynamic>.from(currentSettings)
      ..addAll(settings);
    _moduleSettings[moduleId] = newSettings;
    await _prefs.setString(_moduleSettingsKey, jsonEncode(_moduleSettings));
    notifyListeners();
  }
}
