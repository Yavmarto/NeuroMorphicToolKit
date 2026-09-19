// CEL-431 mobile-standard audit for `lib/features/neurobench/screens/*`.
//
// Pumps each audited screen at the two required narrow widths (375x667 iPhone
// SE, 390x844 iPhone 14) and fails on a RenderFlex overflow. Also measures the
// rendered contrast of the themed controls each screen paints, in both dark and
// light themes, so a passing theme-API audit is not mistaken for legibility.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/models/workspace_route_state.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/providers/results_provider.dart';
import 'package:neuro_toolkit/features/neurobench/screens/benchmark_screen.dart';
import 'package:neuro_toolkit/features/neurobench/screens/comparison_screen.dart';
import 'package:neuro_toolkit/features/neurobench/screens/robustness_screen.dart';
import 'package:neuro_toolkit/features/neurobench/screens/workbench_shell.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/benchmark_header_card.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

const Size _iphoneSe = Size(375, 667);
const Size _iphone14 = Size(390, 844);
const List<Size> _phoneSizes = <Size>[_iphoneSe, _iphone14];

BenchmarkDefinition _benchmark() => BenchmarkDefinition(
  id: 'test_bench',
  name: 'Test Benchmark With A Deliberately Long Catalog Name',
  description:
      'A benchmark used for the CEL-431 mobile audit. The description is long '
      'on purpose so the catalog and comparison surfaces have to wrap it.',
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

Future<List<String>> _captureOverflows(Future<void> Function() body) async {
  final overflows = <String>[];
  final original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    if (message.contains('overflowed by')) {
      overflows.add(message);
      return;
    }
    original?.call(details);
  };
  try {
    await body();
  } finally {
    FlutterError.onError = original;
  }
  return overflows;
}

void _expectNoOverflow(List<String> overflows) {
  expect(overflows, isEmpty, reason: overflows.join('\n'));
}

// ── Contrast helpers (WCAG relative luminance) ────────────────────────────────

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

/// Measures the rendered ink of every visible icon against its nearest opaque
/// ancestor background, and asserts the WCAG 1.4.11 3:1 non-text floor.
void _expectIconContrast(
  WidgetTester tester,
  String label, {
  double minimum = 3.0,
  Finder? within,
}) {
  final icons = within == null
      ? find.byType(Icon)
      : find.descendant(of: within, matching: find.byType(Icon));
  expect(icons, findsWidgets, reason: '$label: expected at least one icon');
  var checked = 0;
  for (final element in icons.evaluate()) {
    final icon = element.widget as Icon;
    // WCAG 1.4.11 exempts disabled controls, so a greyed-out action is not a
    // finding. Measure only enabled ink, which is what a user must read.
    if (_isDisabledIcon(element)) continue;
    // ZetaButton paints Icon(leadingIcon) with no explicit color, inheriting
    // the FilledButton's foreground colour through IconTheme. Resolve that so
    // the measurement reflects what a user actually sees.
    final color = icon.color ?? IconTheme.of(element).color;
    if (color == null) continue;
    final background = _nearestOpaqueBackground(element);
    if (background == null) continue;
    final ratio = _contrastRatio(color, background);
    debugPrint(
      'contrast $label ${icon.icon}: ${_hex(color)} vs ${_hex(background)} '
      '= ${ratio.toStringAsFixed(2)}',
    );
    expect(
      ratio,
      greaterThanOrEqualTo(minimum),
      reason:
          '$label: ${icon.icon} rendered ${ratio.toStringAsFixed(2)}:1 '
          '(${_hex(color)} on ${_hex(background)}), below the '
          '${minimum.toStringAsFixed(1)}:1 floor',
    );
    checked++;
  }
  expect(checked, greaterThan(0), reason: '$label: no icon contrast measured');
}

/// True when [element] sits inside a disabled button (WCAG 1.4.11 exemption).
bool _isDisabledIcon(Element element) {
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

/// The effective colour behind [element], compositing every translucent
/// ancestor fill down to the nearest opaque one.
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

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('overflow — audited neurobench screens', () {
    for (final size in _phoneSizes) {
      final sizeLabel = '${size.width.toInt()}x${size.height.toInt()}';

      testWidgets('workbench_shell.dart fits $sizeLabel', (tester) async {
        _useViewport(tester, size);
        final container = _container(active: true);
        addTearDown(container.dispose);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(
            _host(
              container,
              const WorkbenchShellScreen(
                routeState: NeurobenchRouteState(benchmarkId: 'test_bench'),
              ),
            ),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
        });
        expect(find.textContaining('Test Benchmark'), findsWidgets);
        _expectNoOverflow(overflows);
      });

      testWidgets('benchmark_screen.dart fits $sizeLabel', (tester) async {
        _useViewport(tester, size);
        final container = _container();
        addTearDown(container.dispose);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(_host(container, const BenchmarkScreen()));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
        });
        expect(find.text('Benchmark Catalog'), findsOneWidget);
        _expectNoOverflow(overflows);
      });

      testWidgets('robustness_screen.dart fits $sizeLabel', (tester) async {
        _useViewport(tester, size);
        final container = _container();
        addTearDown(container.dispose);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(_host(container, const RobustnessScreen()));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
        });
        expect(find.text('Benchmark Catalog'), findsOneWidget);
        _expectNoOverflow(overflows);
      });

      testWidgets('comparison_screen.dart (empty) fits $sizeLabel', (
        tester,
      ) async {
        _useViewport(tester, size);
        final container = _container();
        addTearDown(container.dispose);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(_host(container, const ComparisonScreen()));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
        });
        expect(
          find.text('Select a benchmark on the main screen first'),
          findsOneWidget,
        );
        _expectNoOverflow(overflows);
      });

      testWidgets('comparison_screen.dart (populated) fits $sizeLabel', (
        tester,
      ) async {
        _useViewport(tester, size);
        final container = _container(active: true, withDiff: true);
        addTearDown(container.dispose);
        final overflows = await _captureOverflows(() async {
          await tester.pumpWidget(_host(container, const ComparisonScreen()));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 600));
        });
        expect(find.textContaining('Comparing Results for:'), findsOneWidget);
        _expectNoOverflow(overflows);
      });
    }
  });

  group('contrast — rendered neurobench screens', () {
    for (final mode in <ThemeMode>[ThemeMode.dark, ThemeMode.light]) {
      testWidgets('comparison_screen icons clear 3:1 (${mode.name})', (
        tester,
      ) async {
        _useViewport(tester, _iphone14);
        final container = _container(active: true, withDiff: true);
        addTearDown(container.dispose);
        await tester.pumpWidget(
          _host(container, const ComparisonScreen(), mode: mode),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.textContaining('Comparing Results for:'), findsOneWidget);
        _expectIconContrast(tester, 'comparison_screen/${mode.name}');
      });

      testWidgets('workbench_shell icons clear 3:1 (${mode.name})', (
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
            mode: mode,
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        // Scope to the surface CEL-431 changed (the benchmark header card):
        // the standalone top-app-bar destination chip is product chrome that
        // the embedded NeuroBench surface hides (shell_adapter.dart), and its
        // own contrast is tracked separately.
        _expectIconContrast(
          tester,
          'workbench_shell/${mode.name}',
          within: find.byType(BenchmarkHeaderCard),
        );
      });
    }
  });
}
