import 'package:flutter/foundation.dart';
import 'package:neuro_toolkit/services/preferences_service.dart';

class AppProvider with ChangeNotifier {
  static final AppProvider _instance = AppProvider._internal();
  factory AppProvider() => _instance;
  AppProvider._internal() {
    _init();
  }

  final PreferencesService _prefs = PreferencesService();

  bool _hasSeenOnboarding = false;
  bool _isInitialized = false;

  Future<void> _init() async {
    if (_isInitialized) return;
    await _prefs.init();
    _hasSeenOnboarding = _prefs.hasSeenOnboarding;
    _isInitialized = true;
    notifyListeners();
  }

  bool get hasSeenOnboarding => _hasSeenOnboarding;
  bool get isInitialized => _isInitialized;

  Future<void> completeOnboarding() async {
    await _prefs.setHasSeenOnboarding(true);
    _hasSeenOnboarding = true;
    notifyListeners();
  }
}
