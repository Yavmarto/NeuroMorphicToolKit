// TODO(riverpod-migration): Migrate SettingsProvider to AsyncNotifier<SettingsState>.
//
// The main complication: main.dart calls `settings.init()` before runApp()
// to know the launcherControlApiBaseUrl for bootstrap. Steps:
//   1. Create immutable SettingsState with all current fields
//   2. Replace `class SettingsProvider with ChangeNotifier` with
//      `class SettingsNotifier extends AsyncNotifier<SettingsState>`
//   3. Move init() logic into build()
//   4. Refactor main.dart so bootstrap reads from the provider instead of
//      a pre-built object (use a FutureProvider or earlyInitProvider).
//   5. Remove `settingsStateProvider.overrideWith((ref) => settings)` from main.dart
//   6. All set*() methods become `state = state.whenData((s) => s.copyWith(...))`
//
// This requires coordinated changes to main.dart and settings.dart.
// Tackle on a dedicated branch after verifying all bootstrap tests pass.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'package:neuro_toolkit/services/analytics_service.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';

enum LogLevel { info, debug, warning, error, critical }

class SettingsProvider with ChangeNotifier {
  SettingsProvider({AnalyticsService? analyticsService})
      : _analytics = analyticsService ?? AnalyticsService();

  static const String _telemetryKey = 'telemetry_enabled';
  static const String _endpointKey = 'remote_endpoint';
  static const String _themeModeKey = 'theme_mode';
  static const String _highContrastKey = 'high_contrast';
  static const String _fontSizeFactorKey = 'font_size_factor';
  static const String _logLevelKey = 'log_level';
  static const String _moduleSettingsKey = 'module_settings';
  static const String _launcherControlApiBaseUrlKey =
      'launcher_control_api_base_url';

  bool _telemetryEnabled = false;
  String? _remoteEndpoint;
  ThemeMode _themeMode = ThemeMode.system;
  bool _isHighContrast = false;
  double _fontSizeFactor = 1.0;
  LogLevel _logLevel = LogLevel.info;
  Map<String, Map<String, dynamic>> _moduleSettings = {};
  String? _launcherControlApiBaseUrl;

  late final SharedPreferences _prefs;
  final AnalyticsService _analytics;
  bool _initialized = false;

  bool get telemetryEnabled => _telemetryEnabled;
  String? get remoteEndpoint => _remoteEndpoint;
  bool get initialized => _initialized;
  ThemeMode get themeMode => _themeMode;
  bool get isHighContrast => _isHighContrast;
  double get fontSizeFactor => _fontSizeFactor;
  LogLevel get logLevel => _logLevel;
  String? get launcherControlApiBaseUrl => _launcherControlApiBaseUrl;

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
    _launcherControlApiBaseUrl =
        _prefs.getString(_launcherControlApiBaseUrlKey);

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
    _analytics.telemetryEnabled = _telemetryEnabled;
    _analytics.remoteEndpoint = _remoteEndpoint;

    _initialized = true;
    notifyListeners();
  }

  Future<void> setTelemetryEnabled(bool value) async {
    _telemetryEnabled = value;
    await _prefs.setBool(_telemetryKey, value);
    _analytics.telemetryEnabled = value;
    notifyListeners();
  }

  Future<void> setRemoteEndpoint(String? value) async {
    _remoteEndpoint = value;
    if (value == null || value.isEmpty) {
      await _prefs.remove(_endpointKey);
    } else {
      await _prefs.setString(_endpointKey, value);
    }
    _analytics.remoteEndpoint = value;
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

  Future<void> setLauncherControlApiBaseUrl(String? value) async {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      _launcherControlApiBaseUrl = null;
      await _prefs.remove(_launcherControlApiBaseUrlKey);
    } else {
      _launcherControlApiBaseUrl = ControlApiService.normalizeBaseUrl(trimmed);
      await _prefs.setString(
        _launcherControlApiBaseUrlKey,
        _launcherControlApiBaseUrl!,
      );
    }
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
