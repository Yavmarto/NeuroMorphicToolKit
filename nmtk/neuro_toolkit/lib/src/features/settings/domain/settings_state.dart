import 'package:flutter/material.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings_state.freezed.dart';

enum LogLevel { info, debug, warning, error, critical }

@freezed
abstract class SettingsState with _$SettingsState {
  const factory SettingsState({
    @Default(false) bool telemetryEnabled,
    String? remoteEndpoint,
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(false) bool isHighContrast,
    @Default(1.0) double fontSizeFactor,
    @Default(LogLevel.info) LogLevel logLevel,
    @Default({}) Map<String, Map<String, dynamic>> moduleSettings,
    String? launcherControlApiBaseUrl,
  }) = _SettingsState;
}
