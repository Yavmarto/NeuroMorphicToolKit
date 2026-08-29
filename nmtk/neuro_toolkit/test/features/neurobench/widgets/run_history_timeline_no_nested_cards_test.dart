// Regression test for zeta-theming-migration Wave 3a extension
// (Task 7.3 P0 remediation): the "Run History" NmtkSection renders
// flat per-run rows — no descendant Container/Ink with both
// BoxDecoration.color and BoxDecoration.borderRadius set. Mirrors the
// predicate convention from
// neurocnl/frontend/test/widgets/deploy_targets_no_nested_cards_test.dart.
//
// Validates: Requirements 5.1, 5.2, 8.4.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/run_history_timeline.dart';

void main() {
  BenchmarkResult buildResult({required String id}) {
    return BenchmarkResult(
      id: id,
      benchmarkId: 'mnist-bench',
      networkSpecHash: 'sha256:abc123',
      timestamp: '2024-05-01T10:00:00Z',
      params: const {},
      metrics: const {'accuracy': 0.92},
      wallTimeSeconds: 1.25,
      seed: 42,
    );
  }

  Future<void> pumpTimeline(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1024, 768);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          activeBenchmarkResultsProvider.overrideWith(
            (ref) async => [
              buildResult(id: 'run-aaaaaaaa-1'),
              buildResult(id: 'run-bbbbbbbb-2'),
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: RunHistoryTimeline())),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool hasFilledRoundedDecoration(BoxDecoration? decoration) {
    if (decoration == null) return false;
    return decoration.color != null && decoration.borderRadius != null;
  }

  testWidgets(
    'Run History section renders no descendant card-like Container/Ink',
    (WidgetTester tester) async {
      await pumpTimeline(tester);

      final outerFinder = find.byWidgetPredicate(
        (widget) => widget is NmtkSection && widget.title == 'Run History',
        description: 'NmtkSection(title: Run History)',
      );
      expect(outerFinder, findsOneWidget);

      expect(find.textContaining('Run ID:'), findsNWidgets(2));

      bool isCardLike(Widget widget) {
        if (widget is Container) {
          final decoration = widget.decoration;
          return decoration is BoxDecoration &&
              hasFilledRoundedDecoration(decoration);
        }
        if (widget is Ink) {
          final decoration = widget.decoration;
          return decoration is BoxDecoration &&
              hasFilledRoundedDecoration(decoration);
        }
        return false;
      }

      final cardLikeFinder = find.descendant(
        of: outerFinder,
        matching: find.byWidgetPredicate(
          isCardLike,
          description: 'Container/Ink with BoxDecoration{color, borderRadius}',
        ),
      );

      expect(
        cardLikeFinder,
        findsNWidgets(2),
        reason:
            'Run History section must contain exactly two decorated surfaces '
            '(the two per-run rows); the section itself (NmtkSection) is frame-less '
            '(zeta-theming-migration Requirement 5.2).',
      );
    },
  );

  testWidgets('Run History section has no NmtkSurfaceCard descendants', (
    WidgetTester tester,
  ) async {
    await pumpTimeline(tester);

    final outerFinder = find.byWidgetPredicate(
      (widget) => widget is NmtkSection && widget.title == 'Run History',
      description: 'NmtkSection(title: Run History)',
    );
    expect(outerFinder, findsOneWidget);

    final allCards = find.byType(NmtkSurfaceCard);
    expect(
      allCards,
      findsNothing,
      reason:
          'Run History must render no NmtkSurfaceCard (it uses NmtkSection, '
          'which is frame-less); no nested cards '
          '(zeta-theming-migration Requirement 5.1).',
    );
  });
}
