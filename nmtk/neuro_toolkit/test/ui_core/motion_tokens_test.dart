import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

void main() {
  group('NmtkTapScaleWrapper', () {
    testWidgets('activates with pointer, enter, and space', (tester) async {
      var tapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: NmtkTapScaleWrapper(
                onTap: () {
                  tapCount++;
                },
                child: const Text('Run'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Run'));
      await tester.pump();
      expect(tapCount, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(tapCount, 2);

      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pump();
      expect(tapCount, 3);
    });

    testWidgets('does not expose button semantics without onTap', (
      tester,
    ) async {
      final semanticsHandle = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(child: NmtkTapScaleWrapper(child: Text('Status'))),
          ),
        ),
      );

      final semantics = tester.getSemantics(find.text('Status'));
      expect(semantics.flagsCollection.isButton, isFalse);
      semanticsHandle.dispose();
    });
  });
}
