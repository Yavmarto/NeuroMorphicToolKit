// CEL-433 regression gate for the standalone shell's destination chip.
//
// The selected chip paints `accentForeground` on `accentContainer`. In dark
// theme the palette used to hand back `colorScheme.onPrimaryContainer` (#ffffff)
// against `primaryContainer` (#8496f4), which measures 2.75:1 — below the WCAG
// 1.4.11 3:1 non-text floor and the 4.5:1 text floor. The token now resolves the
// foreground against the container, so this test measures the rendered ink of
// the selected chip in both themes and fails if the pairing regresses.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

const Size _viewport = Size(390, 844);

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
    '#${(c.r * 255).round().toRadixString(16).padLeft(2, '0')}'
    '${(c.g * 255).round().toRadixString(16).padLeft(2, '0')}'
    '${(c.b * 255).round().toRadixString(16).padLeft(2, '0')}';

Color? _paintedColorOf(Widget widget) {
  if (widget is Container) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration) return decoration.color;
    return widget.color;
  }
  if (widget is Material) return widget.color;
  if (widget is ColoredBox) return widget.color;
  if (widget is DecoratedBox) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration) return decoration.color;
    return null;
  }
  if (widget is Ink) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration) return decoration.color;
    return null;
  }
  return null;
}

/// The nearest opaque fill behind [element], compositing translucent ancestors.
Color? _nearestOpaqueBackground(Element element) {
  final layers = <Color>[];
  Color? base;
  element.visitAncestorElements((ancestor) {
    final color = _paintedColorOf(ancestor.widget);
    if (color == null || color.a == 0) return true;
    if (color.a >= 0.999) {
      base = color;
      return false;
    }
    layers.add(color);
    return true;
  });
  if (base == null) return null;
  var result = base!;
  for (final layer in layers.reversed) {
    result = _over(layer, result);
  }
  return result;
}

Widget _host(Widget home, ThemeMode mode) {
  return NmtkZetaTheme.wrap(
    initialThemeMode: mode,
    builder: (context, light, dark, effective) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: effective,
      home: home,
    ),
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  for (final mode in <ThemeMode>[ThemeMode.dark, ThemeMode.light]) {
    testWidgets(
      'selected destination chip clears text and icon floors (${mode.name})',
      (tester) async {
        tester.view.physicalSize = _viewport;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          _host(
            Scaffold(
              body: NmtkTopAppBar(
                destinations: const <NavigationDestinationData>[
                  NavigationDestinationData(
                    icon: Icons.dashboard_outlined,
                    selectedIcon: Icons.dashboard,
                    label: 'Overview',
                  ),
                  NavigationDestinationData(
                    icon: Icons.science_outlined,
                    selectedIcon: Icons.science,
                    label: 'Benchmarks',
                  ),
                ],
                selectedIndex: 0,
                onDestinationSelected: (_) {},
              ),
            ),
            mode,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));

        final labelElement = tester.element(find.text('Overview'));
        final label = tester.widget<Text>(find.text('Overview'));
        final labelColor = label.style?.color;
        expect(labelColor, isNotNull, reason: 'chip label must set a colour');
        final labelBackground = _nearestOpaqueBackground(labelElement);
        expect(labelBackground, isNotNull);
        final labelRatio = _contrastRatio(labelColor!, labelBackground!);
        debugPrint(
          'contrast destination chip label/${mode.name}: '
          '${_hex(labelColor)} vs ${_hex(labelBackground)} '
          '= ${labelRatio.toStringAsFixed(2)}',
        );
        expect(
          labelRatio,
          greaterThanOrEqualTo(4.5),
          reason:
              'selected chip label rendered ${labelRatio.toStringAsFixed(2)}:1 '
              '(${_hex(labelColor)} on ${_hex(labelBackground)})',
        );

        final iconElement = tester.element(find.byIcon(Icons.dashboard));
        final icon = tester.widget<Icon>(find.byIcon(Icons.dashboard));
        final iconColor = icon.color ?? IconTheme.of(iconElement).color;
        expect(iconColor, isNotNull, reason: 'chip icon must set a colour');
        final iconBackground = _nearestOpaqueBackground(iconElement);
        expect(iconBackground, isNotNull);
        final iconRatio = _contrastRatio(iconColor!, iconBackground!);
        debugPrint(
          'contrast destination chip icon/${mode.name}: '
          '${_hex(iconColor)} vs ${_hex(iconBackground)} '
          '= ${iconRatio.toStringAsFixed(2)}',
        );
        expect(
          iconRatio,
          greaterThanOrEqualTo(3.0),
          reason:
              'selected chip icon rendered ${iconRatio.toStringAsFixed(2)}:1 '
              '(${_hex(iconColor)} on ${_hex(iconBackground)})',
        );
      },
    );
  }
}
