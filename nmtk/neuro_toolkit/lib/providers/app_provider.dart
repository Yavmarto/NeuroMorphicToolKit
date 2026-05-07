import 'package:flutter/foundation.dart';
import 'package:neuro_toolkit/services/preferences_service.dart';

class AppProvider with ChangeNotifier {
  AppProvider({PreferencesService? preferencesService})
      : _prefs = preferencesService ?? PreferencesService() {
    _init();
  }

  final PreferencesService _prefs;

  bool _hasSeenOnboarding = false;
  bool _isInitialized = false;
  bool _developerMode = false;

  Future<void> _init() async {
    if (_isInitialized) return;
    await _prefs.init();
    _hasSeenOnboarding = _prefs.hasSeenOnboarding;
    _isInitialized = true;
    notifyListeners();
  }

  bool get hasSeenOnboarding => _hasSeenOnboarding;
  bool get isInitialized => _isInitialized;
  bool get developerMode => _developerMode;

  void toggleDeveloperMode() {
    _developerMode = !_developerMode;
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    await _prefs.setHasSeenOnboarding(true);
    _hasSeenOnboarding = true;
    notifyListeners();
  }
}
