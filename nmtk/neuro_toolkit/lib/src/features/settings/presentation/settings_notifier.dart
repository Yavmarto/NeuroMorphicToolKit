import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/providers/riverpod_providers.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
import 'package:neuro_toolkit/src/features/settings/domain/settings_state.dart';

part 'settings_notifier.g.dart';

@Riverpod(keepAlive: true)
class SettingsNotifier extends _$SettingsNotifier {
  static const String _telemetryKey = 'telemetry_enabled';
  static const String _endpointKey = 'remote_endpoint';
  static const String _themeModeKey = 'theme_mode';
  static const String _highContrastKey = 'high_contrast';
  static const String _fontSizeFactorKey = 'font_size_factor';
  static const String _logLevelKey = 'log_level';
  static const String _moduleSettingsKey = 'module_settings';
  static const String _launcherControlApiBaseUrlKey =
      'launcher_control_api_base_url';
  static const String _suiteApiBaseUrlKey = 'suite_api_base_url';

  late final SharedPreferences _prefs;

  @override
  Future<SettingsState> build() async {
    _prefs = await SharedPreferences.getInstance();

    final telemetryEnabled = _prefs.getBool(_telemetryKey) ?? false;
    final remoteEndpoint = _prefs.getString(_endpointKey);
    final themeMode = ThemeMode.values[_prefs.getInt(_themeModeKey) ?? 0];
    final isHighContrast = _prefs.getBool(_highContrastKey) ?? false;
    final fontSizeFactor = _prefs.getDouble(_fontSizeFactorKey) ?? 1.0;
    final logLevel = LogLevel.values[_prefs.getInt(_logLevelKey) ?? 0];
    final launcherControlApiBaseUrl =
        _prefs.getString(_launcherControlApiBaseUrlKey);
    final suiteApiBaseUrl = _prefs.getString(_suiteApiBaseUrlKey);

    Map<String, Map<String, dynamic>> moduleSettings = {};
    final String? moduleSettingsJson = _prefs.getString(_moduleSettingsKey);
    if (moduleSettingsJson != null) {
      try {
        final Map<String, dynamic> decoded =
            jsonDecode(moduleSettingsJson) as Map<String, dynamic>;
        moduleSettings = decoded
            .map((key, value) => MapEntry(key, value as Map<String, dynamic>));
      } catch (e) {
        debugPrint('Error decoding module settings: $e');
      }
    }

    // Sync with AnalyticsService
    final analytics = ref.read(analyticsServiceProvider);
    analytics.telemetryEnabled = telemetryEnabled;
    analytics.remoteEndpoint = remoteEndpoint;

    return SettingsState(
      telemetryEnabled: telemetryEnabled,
      remoteEndpoint: remoteEndpoint,
      themeMode: themeMode,
      isHighContrast: isHighContrast,
      fontSizeFactor: fontSizeFactor,
      logLevel: logLevel,
      moduleSettings: moduleSettings,
      launcherControlApiBaseUrl: launcherControlApiBaseUrl,
      suiteApiBaseUrl: suiteApiBaseUrl,
    );
  }

  Future<void> setTelemetryEnabled(bool value) async {
    await _prefs.setBool(_telemetryKey, value);
    final analytics = ref.read(analyticsServiceProvider);
    analytics.telemetryEnabled = value;

    state = state.whenData((s) => s.copyWith(telemetryEnabled: value));
  }

  Future<void> setRemoteEndpoint(String? value) async {
    if (value == null || value.isEmpty) {
      await _prefs.remove(_endpointKey);
    } else {
      await _prefs.setString(_endpointKey, value);
    }
    final analytics = ref.read(analyticsServiceProvider);
    analytics.remoteEndpoint = value;

    state = state.whenData((s) => s.copyWith(remoteEndpoint: value));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setInt(_themeModeKey, mode.index);
    state = state.whenData((s) => s.copyWith(themeMode: mode));
  }

  Future<void> setHighContrast(bool value) async {
    await _prefs.setBool(_highContrastKey, value);
    state = state.whenData((s) => s.copyWith(isHighContrast: value));
  }

  Future<void> setFontSizeFactor(double value) async {
    final clamped = value.clamp(0.8, 2.0);
    await _prefs.setDouble(_fontSizeFactorKey, clamped);
    state = state.whenData((s) => s.copyWith(fontSizeFactor: clamped));
  }

  Future<void> setLogLevel(LogLevel level) async {
    await _prefs.setInt(_logLevelKey, level.index);
    state = state.whenData((s) => s.copyWith(logLevel: level));
  }

  Future<void> setLauncherControlApiBaseUrl(String? value) async {
    final trimmed = value?.trim() ?? '';
    String? normalizedUrl;

    if (trimmed.isEmpty) {
      await _prefs.remove(_launcherControlApiBaseUrlKey);
    } else {
      normalizedUrl = ControlApiService.normalizeBaseUrl(trimmed);
      await _prefs.setString(_launcherControlApiBaseUrlKey, normalizedUrl);
    }

    state = state.whenData(
      (s) => s.copyWith(launcherControlApiBaseUrl: normalizedUrl),
    );
  }

  Future<void> setSuiteApiBaseUrl(String? value) async {
    final trimmed = value?.trim() ?? '';
    String? normalizedUrl;
    if (trimmed.isNotEmpty) {
      final withScheme = trimmed.contains('://') ? trimmed : 'http://$trimmed';
      final parsed = Uri.parse(withScheme);
      normalizedUrl = parsed.hasPort
          ? parsed.toString()
          : parsed.replace(port: 9000).toString();
    }
    if (normalizedUrl == null) {
      await _prefs.remove(_suiteApiBaseUrlKey);
    } else {
      await _prefs.setString(_suiteApiBaseUrlKey, normalizedUrl);
    }
    state = state.whenData(
      (settings) => settings.copyWith(suiteApiBaseUrl: normalizedUrl),
    );
  }

  Future<void> updateModuleSettings(
      String moduleId, Map<String, dynamic> settings) async {
    final currentState = state.value;
    if (currentState == null) return;

    final currentSettings = currentState.moduleSettings[moduleId] ?? {};
    final newSettings = Map<String, dynamic>.from(currentSettings)
      ..addAll(settings);

    final updatedModuleSettings =
        Map<String, Map<String, dynamic>>.from(currentState.moduleSettings);
    updatedModuleSettings[moduleId] = newSettings;

    await _prefs.setString(
        _moduleSettingsKey, jsonEncode(updatedModuleSettings));

    state = state
        .whenData((s) => s.copyWith(moduleSettings: updatedModuleSettings));
  }
}
