import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

Widget _wrap(Widget child) {
  return CupertinoApp(home: CupertinoPageScaffold(child: Center(child: child)));
}

void main() {
  group('NmtkPrimaryButton', () {
    testWidgets('renders label and handles tap', (tester) async {
      var pressed = false;
      await tester.pumpWidget(_wrap(
        NmtkPrimaryButton(
          label: 'Test Button',
          onPressed: () => pressed = true,
        ),
      ));
      expect(find.text('Test Button'), findsOneWidget);
      await tester.tap(find.byType(NmtkPrimaryButton));
      expect(pressed, isTrue);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        NmtkPrimaryButton(
          label: 'Test Button',
          icon: NmtkIcons.add,
          onPressed: () {},
        ),
      ));
      expect(find.byIcon(NmtkIcons.add), findsOneWidget);
    });

    testWidgets('respects null onPressed (disabled state)', (tester) async {
      await tester.pumpWidget(_wrap(
        const NmtkPrimaryButton(label: 'Test Button'),
      ));
      expect(find.text('Test Button'), findsOneWidget);
    });
  });

  group('NmtkOutlinedButton', () {
    testWidgets('renders label and handles tap', (tester) async {
      var pressed = false;
      await tester.pumpWidget(_wrap(
        NmtkOutlinedButton(
          label: 'Outline',
          onPressed: () => pressed = true,
        ),
      ));
      expect(find.text('Outline'), findsOneWidget);
      await tester.tap(find.byType(NmtkOutlinedButton));
      expect(pressed, isTrue);
    });

    testWidgets('renders icon when provided', (tester) async {
      await tester.pumpWidget(_wrap(
        NmtkOutlinedButton(
          label: 'Outline',
          icon: NmtkIcons.close,
          onPressed: () {},
        ),
      ));
      expect(find.byIcon(NmtkIcons.close), findsOneWidget);
    });

    testWidgets('respects null onPressed (disabled state)', (tester) async {
      await tester.pumpWidget(_wrap(
        const NmtkOutlinedButton(label: 'Outline'),
      ));
      expect(find.text('Outline'), findsOneWidget);
    });
  });
}
