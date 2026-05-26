// Golden tests for [NmtkItemCard].
//
// Coverage matrix (kept selective so CI stays fast — see plan task 3):
//
//   * neutral / regular           ← Task 1
//   * info    / regular           ← Task 2
//   * success / regular           ← Task 2
//   * warning / regular           ← Task 2
//   * danger  / regular           ← Task 2
//   * neutral / compact           ← Task 3
//   * danger  / compact           ← Task 3
//
// Any future tone × density pair MAY be added here; matrix expansion is
// considered intentional (regenerate goldens with
// `flutter test --update-goldens`).
//
// All goldens render under a plain dark [MaterialApp]. [NmtkItemCard] falls
// back to [NmtkShellTokens] when no `ZetaProvider` is in the tree, which is
// deterministic across CI hosts and matches how every other widget test in
// this package operates. Production app shells wrap with `NmtkZetaTheme.wrap`
// for Zeta-exact colors; the structural look (radius, borders, padding,
// accent placement) is identical in either path.
//
// Note: golden tests use `loadAppFonts()` (via `flutter_test`'s default font
// loader) so text rendering is platform-independent; if the host machine
// substitutes system fonts the goldens may diverge — regenerate with
// `flutter test --update-goldens` to refresh on the developer's machine.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

const Size _goldenCardSize = Size(360, 80);

Widget _goldenHarness(Widget card) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: Scaffold(
      // Solid backdrop so any transparency leaks are obvious in goldens.
      backgroundColor: const Color(0xFF000000),
      body: Center(
        child: SizedBox(
          width: _goldenCardSize.width,
          child: card,
        ),
      ),
    ),
  );
}

NmtkItemCard _sampleCard({
  required NmtkTone tone,
  required NmtkItemCardDensity density,
}) {
  return NmtkItemCard(
    tone: tone,
    density: density,
    leading: const Icon(Icons.label_outline, size: 16),
    trailing: const Icon(Icons.check_circle_outline, size: 16),
    child: const Text('Item card sample'),
  );
}

Future<void> _expectGolden(
  WidgetTester tester,
  Widget card,
  String name,
) async {
  await tester.pumpWidget(_goldenHarness(card));
  await tester.pump();
  await expectLater(
    find.byType(NmtkItemCard),
    matchesGoldenFile('goldens/item_card_$name.png'),
  );
}

void main() {
  testWidgets('NmtkItemCard golden — neutral / regular', (
    WidgetTester tester,
  ) async {
    await _expectGolden(
      tester,
      _sampleCard(
        tone: NmtkTone.neutral,
        density: NmtkItemCardDensity.regular,
      ),
      'neutral_regular',
    );
  });

  testWidgets('NmtkItemCard golden — info / regular', (
    WidgetTester tester,
  ) async {
    await _expectGolden(
      tester,
      _sampleCard(
        tone: NmtkTone.info,
        density: NmtkItemCardDensity.regular,
      ),
      'info_regular',
    );
  });

  testWidgets('NmtkItemCard golden — success / regular', (
    WidgetTester tester,
  ) async {
    await _expectGolden(
      tester,
      _sampleCard(
        tone: NmtkTone.success,
        density: NmtkItemCardDensity.regular,
      ),
      'success_regular',
    );
  });

  testWidgets('NmtkItemCard golden — warning / regular', (
    WidgetTester tester,
  ) async {
    await _expectGolden(
      tester,
      _sampleCard(
        tone: NmtkTone.warning,
        density: NmtkItemCardDensity.regular,
      ),
      'warning_regular',
    );
  });

  testWidgets('NmtkItemCard golden — danger / regular', (
    WidgetTester tester,
  ) async {
    await _expectGolden(
      tester,
      _sampleCard(
        tone: NmtkTone.danger,
        density: NmtkItemCardDensity.regular,
      ),
      'danger_regular',
    );
  });

  testWidgets('NmtkItemCard golden — neutral / compact', (
    WidgetTester tester,
  ) async {
    await _expectGolden(
      tester,
      _sampleCard(
        tone: NmtkTone.neutral,
        density: NmtkItemCardDensity.compact,
      ),
      'neutral_compact',
    );
  });

  testWidgets('NmtkItemCard golden — danger / compact', (
    WidgetTester tester,
  ) async {
    await _expectGolden(
      tester,
      _sampleCard(
        tone: NmtkTone.danger,
        density: NmtkItemCardDensity.compact,
      ),
      'danger_compact',
    );
  });
}
