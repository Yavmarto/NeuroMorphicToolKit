// CEL-432 independent QA contrast sweep.
//
// The CEL-429/430/431 audit suites assert icon contrast for a handful of
// surfaces. This QA pass is independent: it renders the same in-scope screens
// and measures BOTH text and icon ink against the composited nearest opaque
// background, so a stale or theme-API-only audit cannot pass unnoticed. It also
// measures the shared `NmtkTopAppBar` destination chip, which the CEL-431 audit
// deliberately excluded from its own scope.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/results_provider.dart';
import 'package:neuro_toolkit/features/neurobench/screens/benchmark_screen.dart';
import 'package:neuro_toolkit/features/neurobench/screens/comparison_screen.dart';
import 'package:neuro_toolkit/features/neurobench/screens/robustness_screen.dart';
import 'package:neuro_toolkit/features/neurobench/screens/workbench_shell.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

const Size _iphone14 = Size(390, 844);

BenchmarkDefinition _benchmark() => BenchmarkDefinition(
  id: 'test_bench',
  name: 'Test Benchmark With A Deliberately Long Catalog Name',
  description:
      'A benchmark used for the CEL-432 QA sweep. The description is long on '
      'purpose so the catalog and comparison surfaces have to wrap it.',
  taskType: 'classification',
  builtin: true,
  assertions: const <String>['assert accuracy > 0.8'],
  inputSpec: InputSpec(type: 'synthetic'),
  scoring: ScoringConfig(
    primaryMetric: 'accuracy',
    secondaryMetrics: const <String>['latency_ms'],
    higherIsBetter: true,
    passThreshold: 0.8,
  ),
  defaultParams: const <String, dynamic>{
    'network_path': 'examples/test_bench.json',
    'seed': 7,
    'batch_size': 4,
  },
);

BenchmarkResult _result() => BenchmarkResult(
  id: 'run_1',
  benchmarkId: 'test_bench',
  networkSpecHash: 'hash-1',
  timestamp: '2026-04-24T10:05:00Z',
  params: const <String, dynamic>{'batch_size': 4},
  metrics: const <String, double>{'accuracy': 0.93},
  wallTimeSeconds: 1.5,
  seed: 7,
);

DiffResult _diff() => DiffResult(
  baselineId: 'base_1',
  currentId: 'run_1',
  metrics: <MetricDiff>[
    MetricDiff(
      name: 'accuracy',
      baselineValue: 0.9,
      currentValue: 0.93,
      delta: 0.03,
      deltaPct: 3.3,
      status: MetricStatus.improved,
      thresholdViolated: false,
      isSignificant: true,
      pValueTtest: 0.012,
      baselineStd: 0.01,
      currentStd: 0.02,
    ),
    MetricDiff(
      name: 'latency_ms',
      baselineValue: 12.5,
      currentValue: 15.0,
      delta: 2.5,
      deltaPct: 20.0,
      status: MetricStatus.regressed,
      thresholdViolated: true,
      isSignificant: false,
      baselineStd: 0.4,
      currentStd: 0.7,
    ),
  ],
);

ProviderContainer _container({bool active = false, bool withDiff = false}) {
  final container = ProviderContainer(
    overrides: [
      benchmarksProvider.overrideWith(
        (ref) async => <BenchmarkDefinition>[_benchmark()],
      ),
      resultsProvider.overrideWith((ref) async => <BenchmarkResult>[_result()]),
      baselinesProvider.overrideWith(
        (ref) async => <BenchmarkResult>[_result()],
      ),
      activeBenchmarkResultsProvider.overrideWith(
        (ref) async => <BenchmarkResult>[_result()],
      ),
      activeDiffProvider.overrideWith((ref) async => withDiff ? _diff() : null),
    ],
  );
  if (active) {
    container.read(activeBenchmarkIdProvider.notifier).set('test_bench');
  }
  return container;
}

Widget _host(
  ProviderContainer container,
  Widget home, {
  ThemeMode mode = ThemeMode.dark,
}) {
  return UncontrolledProviderScope(
    container: container,
    child: NmtkZetaTheme.wrap(
      initialThemeMode: mode,
      builder: (context, light, dark, effective) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: light,
        darkTheme: dark,
        themeMode: effective,
        home: home,
      ),
    ),
  );
}

void _useViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

// ── Contrast maths ────────────────────────────────────────────────────────────

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

Color? _background(Element element) {
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

/// Effective painted style of a [Text] element.
TextStyle? _textInk(Element element) {
  final ro = element.renderObject;
  if (ro is RenderParagraph) {
    final style = ro.text.style;
    if (style?.color != null) return style;
  }
  final style = DefaultTextStyle.of(element).style;
  return style.color == null ? null : style;
}

/// WCAG large-text floor: >=24px, or >=18.66px and bold.
bool _isLargeText(TextStyle style) {
  final size = style.fontSize ?? 14.0;
  final bold =
      (style.fontWeight ?? FontWeight.normal).value >= FontWeight.bold.value;
  return size >= 24 || (size >= 18.66 && bold);
}

/// Effective painted colour of an [Icon] element.
Color? _iconInk(Element element) {
  final icon = element.widget as Icon;
  return icon.color ?? IconTheme.of(element).color;
}

class _Finding {
  _Finding(this.label, this.description, this.ratio, this.floor);
  final String label;
  final String description;
  final double ratio;
  final double floor;
}

/// WCAG 1.4.11 exempts disabled controls; skip ink inside a disabled button.
bool _isDisabled(Element element) {
  var disabled = false;
  element.visitAncestorElements((ancestor) {
    final widget = ancestor.widget;
    if (widget is ButtonStyleButton) {
      disabled = !widget.enabled;
      return false;
    }
    if (widget is IconButton) {
      disabled = widget.onPressed == null;
      return false;
    }
    return true;
  });
  return disabled;
}

/// Renders and measures every visible [Text] and [Icon]; floors are WCAG 1.4.3
/// (4.5:1 text, 3:1 large text) and 1.4.11 (3:1 non-text).
List<_Finding> _sweep(WidgetTester tester, String label, {Finder? within}) {
  final findings = <_Finding>[];

  Iterable<Element> elementsOf(Type type) {
    final finder = within == null
        ? find.byType(type)
        : find.descendant(of: within, matching: find.byType(type));
    return finder.evaluate();
  }

  for (final element in elementsOf(Text)) {
    if (_isDisabled(element)) continue;
    final style = _textInk(element);
    if (style == null) continue;
    final color = style.color!;
    final bg = _background(element);
    if (bg == null) continue;
    final floor = _isLargeText(style) ? 3.0 : 4.5;
    final ratio = _contrastRatio(color, bg);
    debugPrint(
      'QA contrast $label TEXT "${_text(element)}": ${_hex(color)} vs '
      '${_hex(bg)} = ${ratio.toStringAsFixed(2)} (floor $floor)',
    );
    if (ratio < floor) {
      findings.add(_Finding(label, 'TEXT "${_text(element)}"', ratio, floor));
    }
  }

  for (final element in elementsOf(Icon)) {
    if (_isDisabled(element)) continue;
    final color = _iconInk(element);
    if (color == null) continue;
    final bg = _background(element);
    if (bg == null) continue;
    final ratio = _contrastRatio(color, bg);
    debugPrint(
      'QA contrast $label ICON ${(element.widget as Icon).icon}: '
      '${_hex(color)} vs ${_hex(bg)} = ${ratio.toStringAsFixed(2)} (floor 3.0)',
    );
    if (ratio < 3.0) {
      findings.add(
        _Finding(label, 'ICON ${(element.widget as Icon).icon}', ratio, 3.0),
      );
    }
  }
  return findings;
}

String _text(Element element) {
  final ro = element.renderObject;
  if (ro is RenderParagraph) return ro.text.toPlainText();
  return (element.widget as Text).data ?? '';
}

/// Known, pre-existing shared-chrome defects that this QA pass found but that
/// are owned outside the CEL-429/430/431 changed-file scope (tracked for fix).
/// The guard below fails on any NEW violation, so this list is a ratchet: it
/// must shrink as the shared chrome is corrected, never grow. CEL-434 cleared
/// the last entries, so the ledger stays empty.
const List<String> _knownSharedChromeViolations = <String>[];

void _report(List<_Finding> findings, String label) {
  final unexpected = findings
      .where(
        (f) => !_knownSharedChromeViolations.any(
          (known) => f.description.startsWith(known),
        ),
      )
      .toList(growable: false);
  final message = findings
      .map(
        (f) =>
            '${f.label}: ${f.description} = ${f.ratio.toStringAsFixed(2)}:1 '
            '(floor ${f.floor.toStringAsFixed(1)})',
      )
      .join('\n');
  if (findings.isNotEmpty) {
    debugPrint('QA FINDINGS $label:\n$message');
  }
  expect(
    unexpected,
    isEmpty,
    reason: unexpected.isEmpty
        ? null
        : '$label new contrast violations:\n${unexpected.map((f) => '${f.label}: ${f.description} = ${f.ratio.toStringAsFixed(2)}:1').join('\n')}',
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  final screens = <String, Widget>{
    'workbench_shell': const WorkbenchShellScreen(
      routeState: NeurobenchRouteState(benchmarkId: 'test_bench'),
    ),
    'benchmark_screen': const BenchmarkScreen(),
    'robustness_screen': const RobustnessScreen(),
    'comparison_screen': const ComparisonScreen(),
  };

  for (final mode in <ThemeMode>[ThemeMode.dark, ThemeMode.light]) {
    for (final entry in screens.entries) {
      testWidgets('QA sweep ${entry.key} text+icons (${mode.name})', (
        tester,
      ) async {
        _useViewport(tester, _iphone14);
        final container = _container(active: true, withDiff: true);
        addTearDown(container.dispose);
        await tester.pumpWidget(_host(container, entry.value, mode: mode));
        await _settle(tester);
        _report(_sweep(tester, '${entry.key}/${mode.name}'), entry.key);
      });
    }
  }

  for (final mode in <ThemeMode>[ThemeMode.dark, ThemeMode.light]) {
    testWidgets('QA NmtkTopAppBar destination chip contrast (${mode.name})', (
      tester,
    ) async {
      _useViewport(tester, _iphone14);
      await tester.pumpWidget(
        NmtkZetaTheme.wrap(
          initialThemeMode: mode,
          builder: (context, light, dark, effective) => MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: light,
            darkTheme: dark,
            themeMode: effective,
            home: Scaffold(
              appBar: NmtkTopAppBar(
                destinations: const <NavigationDestinationData>[
                  NavigationDestinationData(
                    label: 'Bench',
                    icon: ZetaIcons.dashboard,
                  ),
                  NavigationDestinationData(
                    label: 'Results',
                    icon: ZetaIcons.analytics,
                  ),
                ],
                selectedIndex: 0,
                onDestinationSelected: (_) {},
                mode: NmtkShellMode.command,
              ),
            ),
          ),
        ),
      );
      await _settle(tester);
      _report(_sweep(tester, 'NmtkTopAppBar/${mode.name}'), 'NmtkTopAppBar');
    });
  }

  group('QA back/cancel affordance (CEL-431 surfaces)', () {
    testWidgets(
      'comparison_screen keeps Back to Workbench (empty + populated)',
      (tester) async {
        _useViewport(tester, _iphone14);
        for (final withDiff in <bool>[false, true]) {
          final container = _container(active: true, withDiff: withDiff);
          addTearDown(container.dispose);
          await tester.pumpWidget(_host(container, const ComparisonScreen()));
          await _settle(tester);
          final back = find.text('Back to Workbench');
          expect(back, findsOneWidget, reason: 'withDiff=$withDiff');
          expect(
            find.ancestor(of: back, matching: find.byType(ZetaButton)),
            findsOneWidget,
            reason: 'withDiff=$withDiff: back must be a real button',
          );
        }
      },
    );

    testWidgets('workbench_shell keeps a change-benchmark path', (
      tester,
    ) async {
      _useViewport(tester, _iphone14);
      final container = _container(active: true);
      addTearDown(container.dispose);
      await tester.pumpWidget(
        _host(
          container,
          const WorkbenchShellScreen(
            routeState: NeurobenchRouteState(benchmarkId: 'test_bench'),
          ),
        ),
      );
      await _settle(tester);
      expect(find.text('← Change benchmark'), findsOneWidget);
    });
  });
}
