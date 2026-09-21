import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/mobile_canvas_chrome.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

/// Spot-check for the CEL-88 "dark-theme floating toolbar contrast" finding,
/// captured as numbers by QA in CEL-91 and fixed in CEL-92.
///
/// The floating canvas toolbars paint their icons with Zeta/shell tokens on
/// top of the fixed "Obsidian Flow" bar colors used by canvas_screen.dart.
/// Measured ratios (WCAG 1.4.11 requires >= 3:1):
///   dark  undo/redo/add (mainInverse #1d1e23) vs navy/green: 1.01 / 1.02 ✗
///   light auto-layout   (accent #7c3aed)      vs navy/green: 2.90 / 2.96 ✗
///   dark  delete (surfaceNegative) and accent: 5.31–5.43 / 3.90–3.99 ✓
///   light undo/redo/add (#f3f6fa) and delete:  15.2+ / 3.07–3.14 ✓
/// The two failing pairs were pinned with `skip` while tracked in CEL-92;
/// the chrome now resolves its ink/accent from the actual bar color instead
/// of theme-relative mainInverse, so those pairs are asserted below.
const _obsidianNavy = Color(0xFF0B1F3A); // train pipeline canvas bar
const _obsidianGreen = Color(0xFF0B2116); // eval pipeline canvas bar

/// Third canvas bar variant: the architecture/NIR tab passes
/// `tokens.studioPalette.accentContainer` (canvas_screen.dart) instead of a
/// fixed "Obsidian Flow" color — unlike the two bars above, this bar color is
/// theme-relative, so it takes a different value per app theme. Mirrors
/// `NmtkShellTokens.fromColorScheme`'s `studioPalette.accentContainer`
/// (lib/ui_core/shell_tokens.dart) so a token change here fails loudly instead
/// of silently drifting from production.
const _studioAccentContainerDark = Color(0xFF251A46);
const _studioAccentContainerLight = Color(0xFFEDE9FE);

Widget _host({required ThemeMode mode, required Widget home}) {
  return NmtkZetaTheme.wrap(
    initialThemeMode: mode,
    builder: (context, light, dark, effective) => MaterialApp(
      theme: light,
      darkTheme: dark,
      themeMode: effective,
      home: Scaffold(body: home),
    ),
  );
}

Widget _chrome(Color barColor) => MobileCanvasChrome(
  body: const SizedBox.shrink(),
  barColor: barColor,
  onAutoLayout: () {},
  onAddPrimitive: () {},
  onClearCanvas: () {},
  onUndo: () {},
  onRedo: () {},
  canUndo: true,
  canRedo: true,
);

Color _over(Color fg, Color bg) {
  if (fg.a >= 0.999) return fg;
  return Color.from(
    alpha: 1.0,
    red: fg.r * fg.a + bg.r * (1 - fg.a),
    green: fg.g * fg.a + bg.g * (1 - fg.a),
    blue: fg.b * fg.a + bg.b * (1 - fg.a),
  );
}

double _channelLuminance(double c) =>
    c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channelLuminance(c.r) +
    0.7152 * _channelLuminance(c.g) +
    0.0722 * _channelLuminance(c.b);

double _contrastRatio(Color fg, Color bg) {
  final blended = _over(fg, bg);
  final la = _luminance(blended);
  final lb = _luminance(bg);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

String _hex(Color c) =>
    '${(c.r * 255).round().toRadixString(16).padLeft(2, '0')}'
    '${(c.g * 255).round().toRadixString(16).padLeft(2, '0')}'
    '${(c.b * 255).round().toRadixString(16).padLeft(2, '0')}';

void _expectLegible(
  WidgetTester tester,
  Iterable<IconData> icons,
  Color bar,
  String label,
) {
  for (final icon in icons) {
    expect(
      find.byIcon(icon),
      findsOneWidget,
      reason: '$icon must render in the toolbar',
    );
    final painted = tester.widget<Icon>(find.byIcon(icon)).color!;
    final ratio = _contrastRatio(painted, bar);
    debugPrint(
      'contrast $label $icon: #${_hex(painted)} vs #${_hex(bar)} '
      '= ${ratio.toStringAsFixed(2)}',
    );
    expect(ratio, greaterThanOrEqualTo(3.0));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final bar in {'navy': _obsidianNavy, 'green': _obsidianGreen}.entries) {
    testWidgets(
      'dark theme: delete and auto-layout icons clear 3:1 on the ${bar.key} bar',
      (tester) async {
        await tester.pumpWidget(
          _host(mode: ThemeMode.dark, home: _chrome(bar.value)),
        );
        await tester.pumpAndSettle();
        _expectLegible(
          tester,
          [ZetaIcons.delete, Icons.auto_awesome],
          bar.value,
          'dark/${bar.key}',
        );
      },
    );

    testWidgets(
      'light theme: undo/redo/add and delete icons clear 3:1 on the ${bar.key} bar',
      (tester) async {
        await tester.pumpWidget(
          _host(mode: ThemeMode.light, home: _chrome(bar.value)),
        );
        await tester.pumpAndSettle();
        _expectLegible(
          tester,
          [ZetaIcons.undo, ZetaIcons.redo, ZetaIcons.add, ZetaIcons.delete],
          bar.value,
          'light/${bar.key}',
        );
      },
    );

    // CEL-92: dark-theme undo/redo/add previously painted mainInverse
    // (#1d1e23) on the dark obsidian bar — ~1:1. The chrome now uses the
    // bar-resolved light ink, so they clear 3:1 in both themes.
    testWidgets(
      'dark theme: mainInverse icons clear 3:1 on the ${bar.key} bar',
      (tester) async {
        await tester.pumpWidget(
          _host(mode: ThemeMode.dark, home: _chrome(bar.value)),
        );
        await tester.pumpAndSettle();
        _expectLegible(
          tester,
          [ZetaIcons.undo, ZetaIcons.redo, ZetaIcons.add],
          bar.value,
          'dark/${bar.key}',
        );
      },
    );

    // CEL-92: the light-theme auto-layout accent (#7c3aed) measured 2.90–2.96:1,
    // just under the 3:1 non-text floor. The chrome now uses the bar-resolved
    // accent, so it clears 3:1 on the obsidian bars in both themes.
    testWidgets(
      'light theme: auto-layout accent icon clears 3:1 on the ${bar.key} bar',
      (tester) async {
        await tester.pumpWidget(
          _host(mode: ThemeMode.light, home: _chrome(bar.value)),
        );
        await tester.pumpAndSettle();
        _expectLegible(
          tester,
          [Icons.auto_awesome],
          bar.value,
          'light/${bar.key}',
        );
      },
    );
  }

  // Third canvas bar variant: the architecture/NIR tab (CanvasTab.architecture
  // in canvas_screen.dart) — unlike the two fixed obsidian bars above, this
  // bar is theme-relative (`tokens.studioPalette.accentContainer`), so each
  // app theme resolves a *different* bar color rather than the same fixed
  // color under both themes. This variant was not covered by the CEL-92
  // regression suite even though the CEL-92 fix explicitly generalized to it
  // (see the "studio accentContainer surfaces" comment in
  // mobile_canvas_chrome.dart's `_CanvasBarColors.forBar`).
  testWidgets(
    'dark theme: icons clear 3:1 on the architecture (studio accentContainer) bar',
    (tester) async {
      await tester.pumpWidget(
        _host(mode: ThemeMode.dark, home: _chrome(_studioAccentContainerDark)),
      );
      await tester.pumpAndSettle();
      _expectLegible(
        tester,
        [
          ZetaIcons.undo,
          ZetaIcons.redo,
          ZetaIcons.add,
          ZetaIcons.delete,
          Icons.auto_awesome,
        ],
        _studioAccentContainerDark,
        'dark/architecture',
      );
    },
  );

  testWidgets(
    'light theme: icons clear 3:1 on the architecture (studio accentContainer) bar',
    (tester) async {
      await tester.pumpWidget(
        _host(
          mode: ThemeMode.light,
          home: _chrome(_studioAccentContainerLight),
        ),
      );
      await tester.pumpAndSettle();
      _expectLegible(
        tester,
        [
          ZetaIcons.undo,
          ZetaIcons.redo,
          ZetaIcons.add,
          ZetaIcons.delete,
          Icons.auto_awesome,
        ],
        _studioAccentContainerLight,
        'light/architecture',
      );
    },
  );
}
