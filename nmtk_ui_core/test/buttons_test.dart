import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('NmtkPrimaryButton', () {
    testWidgets('renders label and handles tap', (WidgetTester tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NmtkPrimaryButton(
              label: 'Test Button',
              onPressed: () {
                pressed = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Test Button'), findsOneWidget);

      await tester.tap(find.byType(NmtkPrimaryButton));
      expect(pressed, isTrue);
    });

    testWidgets('renders icon when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NmtkPrimaryButton(
              label: 'Test Button',
              icon: Icons.add,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('respects null onPressed (disabled state)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkPrimaryButton(label: 'Test Button', onPressed: null),
          ),
        ),
      );

      // Widget renders without error when disabled
      expect(find.text('Test Button'), findsOneWidget);
    });
  });

  group('NmtkOutlinedButton', () {
    testWidgets('renders label and handles tap', (WidgetTester tester) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NmtkOutlinedButton(
              label: 'Outline',
              onPressed: () {
                pressed = true;
              },
            ),
          ),
        ),
      );

      expect(find.text('Outline'), findsOneWidget);

      await tester.tap(find.byType(NmtkOutlinedButton));
      expect(pressed, isTrue);
    });

    testWidgets('renders icon when provided', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NmtkOutlinedButton(
              label: 'Outline',
              icon: Icons.close,
              onPressed: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('respects null onPressed (disabled state)', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkOutlinedButton(label: 'Outline', onPressed: null),
          ),
        ),
      );

      // Widget renders without error when disabled
      expect(find.text('Outline'), findsOneWidget);
    });
  });
}
