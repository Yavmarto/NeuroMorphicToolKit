import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService({
    String? basePath,
    @visibleForTesting bool useSharedPreferencesForTesting = false,
  }) {
    if (basePath != null) {
      _instance._basePath = basePath;
    }
    _instance._useSharedPreferencesForTesting = useSharedPreferencesForTesting;
    return _instance;
  }
  PreferencesService._internal();

  static const String _fileName = 'preferences.json';
  static const String _hasSeenOnboardingKey = 'hasSeenOnboarding';
  File? _file;
  Map<String, dynamic> _data = {};
  SharedPreferences? _sharedPreferences;
  String? _basePath;
  bool _useSharedPreferencesForTesting = false;

  bool get _usesSharedPreferences =>
      _basePath == null && (kIsWeb || _useSharedPreferencesForTesting);

  Future<void> init() async {
    try {
      if (_usesSharedPreferences) {
        _sharedPreferences = await SharedPreferences.getInstance();
        _data = {
          _hasSeenOnboardingKey:
              _sharedPreferences!.getBool(_hasSeenOnboardingKey) ?? false,
        };
        _file = null;
        return;
      }

      final String directoryPath =
          _basePath ?? (await getApplicationSupportDirectory()).path;
      _file = File(p.join(directoryPath, _fileName));

      if (await _file!.exists()) {
        final content = await _file!.readAsString();
        _data = jsonDecode(content) as Map<String, dynamic>;
      } else {
        _data = {};
      }
    } catch (e) {
      debugPrint('Error initializing PreferencesService: $e');
    }
  }

  bool get hasSeenOnboarding => _data[_hasSeenOnboardingKey] as bool? ?? false;

  Future<void> setHasSeenOnboarding(bool value) async {
    _data[_hasSeenOnboardingKey] = value;
    await _save();
  }

  Future<void> _save() async {
    if (_usesSharedPreferences) {
      final prefs = _sharedPreferences ?? await SharedPreferences.getInstance();
      _sharedPreferences = prefs;
      await prefs.setBool(_hasSeenOnboardingKey, hasSeenOnboarding);
      return;
    }

    if (_file == null) return;
    try {
      await _file!.writeAsString(jsonEncode(_data));
    } catch (e) {
      debugPrint('Error saving preferences: $e');
    }
  }

  @visibleForTesting
  void clear() {
    _data = {};
    _file = null;
    _sharedPreferences = null;
    _basePath = null;
    _useSharedPreferencesForTesting = false;
  }
}
