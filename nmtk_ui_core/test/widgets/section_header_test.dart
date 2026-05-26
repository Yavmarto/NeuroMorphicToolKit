// Unit tests for NmtkSectionHeader and NmtkSection (introduced by zeta-card-
// reduction Task 1). These are flat frame-less section primitives that must
// never render a filled+rounded BoxDecoration of their own — they replace
// NeurocnlSectionCard for cases that don't need elevation.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

bool _hasFilledRoundedBoxDecoration(Widget widget) {
  if (widget is Container) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration &&
        decoration.color != null &&
        decoration.borderRadius != null) {
      return true;
    }
  }
  if (widget is DecoratedBox) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration &&
        decoration.color != null &&
        decoration.borderRadius != null) {
      return true;
    }
  }
  if (widget is Ink) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration &&
        decoration.color != null &&
        decoration.borderRadius != null) {
      return true;
    }
  }
  return false;
}

void main() {
  group('NmtkSectionHeader', () {
    testWidgets('renders title and subtitle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkSectionHeader(
              title: 'Deploy targets',
              subtitle: 'Coverage 6/6',
            ),
          ),
        ),
      );

      expect(find.text('Deploy targets'), findsOneWidget);
      expect(find.text('Coverage 6/6'), findsOneWidget);
    });

    testWidgets('renders no filled+rounded BoxDecoration in its subtree',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkSectionHeader(
              title: 'Layer 1',
              subtitle: 'Coverage 6/6',
              trailing: Icon(Icons.check_circle, size: 16),
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(_hasFilledRoundedBoxDecoration),
        findsNothing,
        reason: 'NmtkSectionHeader must be frame-less — no filled+rounded '
            'BoxDecoration may appear in its subtree.',
      );
    });

    testWidgets('renders trailing widget alongside the title at wide widths',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const trailingKey = Key('trailing-widget');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkSectionHeader(
              title: 'Akida Runtime',
              trailing: SizedBox(
                key: trailingKey,
                width: 80,
                height: 24,
                child: Placeholder(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(trailingKey), findsOneWidget);
    });
  });

  group('NmtkSection', () {
    testWidgets('renders title, subtitle, and child without a frame',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkSection(
              title: 'Deploy targets',
              subtitle: 'Pick a hardware backend',
              child: Text('child-payload'),
            ),
          ),
        ),
      );

      expect(find.text('Deploy targets'), findsOneWidget);
      expect(find.text('Pick a hardware backend'), findsOneWidget);
      expect(find.text('child-payload'), findsOneWidget);

      // The whole point: zero filled+rounded decorations.
      expect(
        find.byWidgetPredicate(_hasFilledRoundedBoxDecoration),
        findsNothing,
        reason: 'NmtkSection must remain frame-less.',
      );
    });

    testWidgets('renders no NmtkSurfaceCard descendant', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkSection(title: 'X', child: Text('y')),
          ),
        ),
      );

      expect(find.byType(NmtkSurfaceCard), findsNothing);
    });

    testWidgets('childGap=0 removes the gap row', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkSection(
              title: 'Compact',
              childGap: 0,
              child: SizedBox(height: 1, key: Key('inline-child')),
            ),
          ),
        ),
      );

      expect(find.byKey(const Key('inline-child')), findsOneWidget);
      // No SizedBox of explicit height 12 from the gap.
      final defaultGap = find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.height == 12,
      );
      expect(defaultGap, findsNothing);
    });
  });
}
