import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/services/preferences_service.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('prefs_test');
    PreferencesService().clear();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('PreferencesService init and onboarding toggle', () async {
    final prefs = PreferencesService(basePath: tempDir.path);
    await prefs.init();

    expect(prefs.hasSeenOnboarding, isFalse);

    await prefs.setHasSeenOnboarding(true);
    expect(prefs.hasSeenOnboarding, isTrue);

    // Re-init should load from file
    final prefs2 = PreferencesService(basePath: tempDir.path);
    await prefs2.init();
    expect(prefs2.hasSeenOnboarding, isTrue);

    final prefFile = File(p.join(tempDir.path, 'preferences.json'));
    expect(await prefFile.exists(), isTrue);
  });

  test('PreferencesService can persist onboarding with shared preferences',
      () async {
    SharedPreferences.setMockInitialValues({});

    final prefs = PreferencesService(useSharedPreferencesForTesting: true);
    await prefs.init();

    expect(prefs.hasSeenOnboarding, isFalse);

    await prefs.setHasSeenOnboarding(true);
    expect(prefs.hasSeenOnboarding, isTrue);

    PreferencesService().clear();

    final prefs2 = PreferencesService(useSharedPreferencesForTesting: true);
    await prefs2.init();
    expect(prefs2.hasSeenOnboarding, isTrue);
  });
}
