// Regression test for zeta-theming-migration Wave 3b (Task 6.1):
// the CnlSentenceBuilderDialog concept-list rows no longer encode
// selection state via a Border(left: BorderSide) side-stripe. Selection
// is now communicated by a leading status Icon whose color sources from
// NmtkShellTokens (runningColor when selected, subtleBorder otherwise).
//
// Validates: Requirements 6.1, 6.2, 6.5, 6.6.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' show ZetaIcons;

import 'package:neuro_toolkit/features/neurocnl/widgets/cnl_sentence_builder_dialog.dart';

void main() {
  Future<void> pumpDialog(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: CnlSentenceBuilderDialog())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'concept-list rows render no Border(left/right: BorderSide) decoration',
    (WidgetTester tester) async {
      await pumpDialog(tester);

      // Walk every AnimatedContainer in the dialog subtree and inspect its
      // decoration. None may carry a Border with a non-transparent left or
      // right BorderSide of width >= 2 — that is the side-stripe pattern.
      final animatedContainers = tester.widgetList<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(
        animatedContainers,
        isNotEmpty,
        reason: 'Concept list rows should render as AnimatedContainer widgets.',
      );

      for (final container in animatedContainers) {
        final decoration = container.decoration;
        if (decoration is! BoxDecoration) continue;
        final border = decoration.border;
        if (border is Border) {
          expect(
            border.left,
            BorderSide.none,
            reason:
                'AnimatedContainer must not carry a left BorderSide '
                '(zeta-theming-migration Requirement 6.1).',
          );
          expect(
            border.right,
            BorderSide.none,
            reason:
                'AnimatedContainer must not carry a right BorderSide '
                '(zeta-theming-migration Requirement 6.1).',
          );
        } else {
          expect(
            border,
            isNull,
            reason:
                'AnimatedContainer decoration.border must be null after the '
                'side-stripe was removed (zeta-theming-migration '
                'Requirement 6.1).',
          );
        }
      }
    },
  );

  testWidgets(
    'each concept-list row contains a leading status Icon plus the concept '
    'icon and label',
    (WidgetTester tester) async {
      await pumpDialog(tester);

      // The dialog ships with a fixed list of 14 concepts. After the
      // side-stripe migration each row renders two icons (a leading status
      // glyph + the concept glyph) followed by the label inside an Expanded
      // Text. Find one row by its label, then introspect its descendants.
      final rowFinder = find
          .ancestor(
            of: find.text('Threshold Firing'),
            matching: find.byType(InkWell),
          )
          .first;
      expect(rowFinder, findsOneWidget);

      // The row's Row child should contain three meaningful children: a
      // leading status Icon, the concept Icon, and the Expanded label.
      final rowIcons = find.descendant(
        of: rowFinder,
        matching: find.byType(Icon),
      );
      expect(
        rowIcons,
        findsNWidgets(2),
        reason:
            'Concept row must contain exactly two Icon widgets after the '
            'side-stripe migration: one leading status icon and the existing '
            'concept icon (zeta-theming-migration Requirement 6.2).',
      );

      // The leading icon must be one of the discriminable selection glyphs.
      final leadingIcon = tester.widget<Icon>(rowIcons.first);
      expect(
        leadingIcon.icon,
        anyOf(ZetaIcons.check_circle_outline, ZetaIcons.radio_button_unchecked),
        reason:
            'Leading icon must use a selection-state glyph '
            '(zeta-theming-migration Requirement 6.2).',
      );

      // And the row still hosts an Expanded label child.
      expect(
        find.descendant(of: rowFinder, matching: find.byType(Expanded)),
        findsOneWidget,
      );
    },
  );
}
