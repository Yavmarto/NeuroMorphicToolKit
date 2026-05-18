import 'package:flutter/foundation.dart';

class AppProvider with ChangeNotifier {
  AppProvider();
  bool _developerMode = false;
  bool get developerMode => _developerMode;

  void toggleDeveloperMode() {
    _developerMode = !_developerMode;
    notifyListeners();
  }
}
