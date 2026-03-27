import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class PreferencesService {
  static final PreferencesService _instance = PreferencesService._internal();
  factory PreferencesService({String? basePath}) {
    if (basePath != null) {
      _instance._basePath = basePath;
    }
    return _instance;
  }
  PreferencesService._internal();

  static const String _fileName = 'preferences.json';
  File? _file;
  Map<String, dynamic> _data = {};
  String? _basePath;

  Future<void> init() async {
    try {
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

  bool get hasSeenOnboarding => _data['hasSeenOnboarding'] as bool? ?? false;

  Future<void> setHasSeenOnboarding(bool value) async {
    _data['hasSeenOnboarding'] = value;
    await _save();
  }

  Future<void> _save() async {
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
    _basePath = null;
  }
}
