import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class SettingsProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _isHighContrast = false;
  double _fontSizeFactor = 1.0;

  ThemeMode get themeMode => _themeMode;
  bool get isHighContrast => _isHighContrast;
  double get fontSizeFactor => _fontSizeFactor;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final file = await _getSettingsFile();
      if (await file.exists()) {
        final jsonString = await file.readAsString();
        final jsonMap = jsonDecode(jsonString) as Map<String, dynamic>;

        _themeMode = ThemeMode.values.firstWhere(
          (e) => e.toString() == jsonMap['themeMode'],
          orElse: () => ThemeMode.system,
        );

        final dynamic hc = jsonMap['isHighContrast'];
        if (hc is bool) {
          _isHighContrast = hc;
        }

        final dynamic fs = jsonMap['fontSizeFactor'];
        if (fs is num) {
          _fontSizeFactor = fs.toDouble();
        }

        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load settings: $e');
    }
  }

  Future<void> _saveSettings() async {
    try {
      final file = await _getSettingsFile();
      final jsonMap = {
        'themeMode': _themeMode.toString(),
        'isHighContrast': _isHighContrast,
        'fontSizeFactor': _fontSizeFactor,
      };
      await file.writeAsString(jsonEncode(jsonMap));
    } catch (e) {
      debugPrint('Failed to save settings: $e');
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
      _saveSettings();
    }
  }

  void setHighContrast(bool value) {
    if (_isHighContrast != value) {
      _isHighContrast = value;
      notifyListeners();
      _saveSettings();
    }
  }

  void setFontSizeFactor(double factor) {
    if (_fontSizeFactor != factor) {
      _fontSizeFactor = factor;
      notifyListeners();
      _saveSettings();
    }
  }

  Future<File> _getSettingsFile() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/settings.json');
  }
}
