import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class AppRobot {
  AppRobot(this.tester);

  final WidgetTester tester;

  Finder _finderFor(String keyOrText) {
    final keyFinder = find.byKey(ValueKey<String>(keyOrText));
    if (keyFinder.evaluate().isNotEmpty) {
      return keyFinder;
    }
    return find.text(keyOrText);
  }

  Future<void> tap(String keyOrText) async {
    final finder = _finderFor(keyOrText).first;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> type(String keyOrText, String input) async {
    final finder = _finderFor(keyOrText).first;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.enterText(finder, input);
    await tester.pumpAndSettle();
  }

  Future<void> assertTextExists(String text) async {
    await tester.pumpAndSettle();
    expect(find.text(text), findsWidgets);
  }
}
