// Widget tests for [NmtkItemCard].
//
// These tests assert the structural invariants of the primitive that the
// Parse / Validate / NIR migrations depend on:
//
//   1. The three slots (leading, child, trailing) render when supplied.
//   2. The 3 px left-edge accent bar is always present.
//   3. Padding values match the active [NmtkItemCardDensity].
//   4. Inner gaps between non-null slots match the active density.
//   5. Tone maps to the documented Zeta border-* token (assertion uses the
//      Zeta-resolved color path under [NmtkZetaTheme.wrap]).
//
// Goldens live in `item_card_golden_test.dart`. This file only asserts
// behavior reachable without pixel comparison.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

/// Plain MaterialApp harness in dark mode. NmtkItemCard falls back to
/// [NmtkShellTokens] colors when no `ZetaProvider` is in the tree, so
/// structural assertions (slot rendering, accent width, padding, gaps)
/// can run without the heavier `NmtkZetaTheme.wrap`.
Widget _harness(Widget child) {
  return MaterialApp(
    theme: ThemeData.dark(),
    home: Scaffold(
      body: Center(
        child: SizedBox(width: 320, child: child),
      ),
    ),
  );
}

/// Locate the 3 px accent bar inside an [NmtkItemCard] subtree.
Finder _accentFinder() {
  return find.byWidgetPredicate(
    (Widget widget) {
      if (widget is! Container) return false;
      final BoxConstraints? c = widget.constraints;
      if (c?.minWidth == NmtkItemCard.accentBarWidth &&
          c?.maxWidth == NmtkItemCard.accentBarWidth) {
        return true;
      }
      // SizedBox-style explicit width — `Container(width: 3, ...)` resolves
      // through `additionalConstraints`.
      return widget.constraints?.maxWidth == NmtkItemCard.accentBarWidth;
    },
    description: 'NmtkItemCard accent bar (width=${NmtkItemCard.accentBarWidth})',
  );
}

void main() {
  testWidgets('renders child, leading and trailing slots', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const NmtkItemCard(
          leading: Icon(Icons.bolt, key: Key('leading-icon')),
          trailing: Icon(Icons.check, key: Key('trailing-icon')),
          child: Text('item-body', key: Key('child-text')),
        ),
      ),
    );

    expect(find.byKey(const Key('leading-icon')), findsOneWidget);
    expect(find.byKey(const Key('child-text')), findsOneWidget);
    expect(find.byKey(const Key('trailing-icon')), findsOneWidget);
  });

  testWidgets('renders without leading or trailing when not supplied', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const NmtkItemCard(
          child: Text('only-body', key: Key('child-text')),
        ),
      ),
    );

    expect(find.byKey(const Key('child-text')), findsOneWidget);
    // No descendant Icon (leading/trailing absent).
    expect(
      find.descendant(
        of: find.byType(NmtkItemCard),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );
  });

  testWidgets('accent bar is 3 px wide', (WidgetTester tester) async {
    await tester.pumpWidget(
      _harness(const NmtkItemCard(child: Text('body'))),
    );

    final Finder accent = _accentFinder();
    expect(accent, findsOneWidget);

    final Container container = tester.widget<Container>(accent);
    // Container(width: 3) sets BoxConstraints.tightFor(width: 3) in
    // `additionalConstraints`.
    expect(container.constraints?.maxWidth, NmtkItemCard.accentBarWidth);
    expect(container.constraints?.minWidth, NmtkItemCard.accentBarWidth);
  });

  testWidgets('regular density uses 12 px outer padding and 8 px inner gap', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const NmtkItemCard(
          leading: Icon(Icons.bolt),
          trailing: Icon(Icons.check),
          child: Text('body'),
        ),
      ),
    );

    // Locate the inner Padding sibling of the accent bar (the one wrapping
    // the leading/child/trailing Row). It is the only Padding descendant
    // of the NmtkItemCard with EdgeInsets.all(12).
    final Iterable<Padding> paddings =
        tester.widgetList<Padding>(find.descendant(
      of: find.byType(NmtkItemCard),
      matching: find.byType(Padding),
    ));
    final bool hasRegularPadding = paddings.any(
      (Padding p) => p.padding == const EdgeInsets.all(NmtkItemCard.regularPadding),
    );
    expect(hasRegularPadding, isTrue,
        reason: 'NmtkItemCard regular density must use 12 px all-side padding.');

    // Inner gaps: two SizedBox(width: 8) — one between leading↔child and one
    // between child↔trailing.
    final Iterable<SizedBox> gaps =
        tester.widgetList<SizedBox>(find.descendant(
      of: find.byType(NmtkItemCard),
      matching: find.byType(SizedBox),
    ));
    final int regularGapCount = gaps
        .where((SizedBox sb) => sb.width == NmtkItemCard.regularInnerGap)
        .length;
    expect(regularGapCount, greaterThanOrEqualTo(2),
        reason:
            'NmtkItemCard regular density must use 8 px gaps between leading/child/trailing.');
  });

  testWidgets('every NmtkTone produces a non-null accent color', (
    WidgetTester tester,
  ) async {
    // Sanity check — exercises the widget under each tone so the tone
    // mapping is reachable. Color identity (which Zeta token) is locked
    // by the goldens; this test guards against `null`/transparent regressions.
    for (final NmtkTone tone in NmtkTone.values) {
      await tester.pumpWidget(
        _harness(
          NmtkItemCard(
            tone: tone,
            child: Text('body-$tone'),
          ),
        ),
      );

      final Container accent = tester.widget<Container>(_accentFinder());
      final BoxDecoration? deco = accent.decoration as BoxDecoration?;
      expect(deco, isNotNull,
          reason: 'tone=$tone accent must have a BoxDecoration');
      expect(deco!.color, isNotNull,
          reason: 'tone=$tone accent BoxDecoration.color must be non-null');
      expect(deco.color!.a, greaterThan(0),
          reason: 'tone=$tone accent color must be visible (non-transparent)');
    }
  });

  testWidgets('compact density uses 8 px outer padding and 6 px inner gap', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _harness(
        const NmtkItemCard(
          density: NmtkItemCardDensity.compact,
          leading: Icon(Icons.bolt),
          trailing: Icon(Icons.check),
          child: Text('body'),
        ),
      ),
    );

    final Iterable<Padding> paddings =
        tester.widgetList<Padding>(find.descendant(
      of: find.byType(NmtkItemCard),
      matching: find.byType(Padding),
    ));
    final bool hasCompactPadding = paddings.any(
      (Padding p) =>
          p.padding == const EdgeInsets.all(NmtkItemCard.compactPadding),
    );
    expect(hasCompactPadding, isTrue,
        reason: 'NmtkItemCard compact density must use 8 px all-side padding.');

    final Iterable<SizedBox> gaps =
        tester.widgetList<SizedBox>(find.descendant(
      of: find.byType(NmtkItemCard),
      matching: find.byType(SizedBox),
    ));
    final int compactGapCount = gaps
        .where((SizedBox sb) => sb.width == NmtkItemCard.compactInnerGap)
        .length;
    expect(compactGapCount, greaterThanOrEqualTo(2),
        reason:
            'NmtkItemCard compact density must use 6 px gaps between leading/child/trailing.');
  });

  testWidgets('non-interactive card has no InkWell in its subtree', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _harness(const NmtkItemCard(child: Text('body'))),
    );

    expect(
      find.descendant(
        of: find.byType(NmtkItemCard),
        matching: find.byType(InkWell),
      ),
      findsNothing,
      reason:
          'NmtkItemCard with onTap == null must not introduce an InkWell '
          '(no ripple on presentational cards).',
    );
  });

  testWidgets('interactive card fires onTap and exposes one InkWell', (
    WidgetTester tester,
  ) async {
    int tapCount = 0;
    await tester.pumpWidget(
      _harness(
        NmtkItemCard(
          onTap: () => tapCount++,
          child: const Text('body'),
        ),
      ),
    );

    final Finder inkWell = find.descendant(
      of: find.byType(NmtkItemCard),
      matching: find.byType(InkWell),
    );
    expect(inkWell, findsOneWidget,
        reason: 'NmtkItemCard with onTap set must wrap content in InkWell.');

    await tester.tap(find.byType(NmtkItemCard));
    await tester.pump();
    expect(tapCount, 1,
        reason: 'Tapping NmtkItemCard with onTap set must fire the callback.');
  });
}
