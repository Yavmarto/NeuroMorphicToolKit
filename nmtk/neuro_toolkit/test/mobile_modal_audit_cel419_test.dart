// CEL-419 mobile modal audit — Studio deployment / workflow surfaces.
//
// Pumps the audited dialog and sheet surfaces at the two required mobile widths
// (375x667 iPhone SE class, 390x844 iPhone 14) and fails on a RenderFlex
// overflow, so a fixed desktop width or a non-scrolling body cannot regress.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/running_notebook_tasks_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/hub/publish_results_dialog/publish_results_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/deploy_review_step/compare_targets_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workflow/steps/results_step/neuron_detail_sheet.dart';
import 'package:neuro_toolkit/features/neurocnl/features/studio/workspace/presentation/running_tasks_dialog.dart';

const Size _iphoneSe = Size(375, 667);
const Size _iphone14 = Size(390, 844);

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

void _useViewport(WidgetTester tester, Size size, {double keyboard = 0}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.reset);
}

Widget _plainScope(Widget child) => ProviderScope(child: child);

Future<void> _pumpApp(
  WidgetTester tester, {
  required Widget Function(BuildContext context) openButton,
  Widget Function(Widget child) scope = _plainScope,
}) async {
  final app = ZetaProvider(
    initialContrast: ZetaContrast.aa,
    initialThemeMode: ThemeMode.light,
    builder: (context, light, dark, mode) => MaterialApp(
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      home: Scaffold(
        body: Center(child: Builder(builder: openButton)),
      ),
    ),
  );
  await tester.pumpWidget(scope(app));
  await tester.pump();
}

class _FakeRunningTasksNotifier extends RunningNotebookTasksNotifier {
  _FakeRunningTasksNotifier(this.tasks);

  final List<RunningNotebookTask> tasks;

  @override
  Future<List<RunningNotebookTask>> build() async => tasks;
}

List<RunningNotebookTask> _manyTasks() => <RunningNotebookTask>[
  for (var i = 0; i < 12; i++)
    RunningNotebookTask(
      id: 'task-$i',
      source: RunningNotebookTaskSource.run,
      label: 'Long running notebook task number $i that should never clip',
      isExecuting: true,
    ),
];

void main() {
  group('NmtkDialogSurface', () {
    testWidgets('shrinks to near-full width on a phone', (tester) async {
      _useViewport(tester, _iphoneSe);
      late BoxConstraints constraints;
      await _pumpApp(
        tester,
        openButton: (context) {
          constraints = NmtkDialogSurface.constraints(
            context,
            maxWidth: 1100,
            maxHeight: 780,
          );
          return const SizedBox.shrink();
        },
      );
      expect(constraints.maxWidth, lessThanOrEqualTo(375));
      expect(constraints.maxWidth, greaterThan(375 - 48));
      expect(constraints.maxHeight, lessThanOrEqualTo(667));
    });
  });

  group('CompareTargetsDialog', () {
    for (final size in <Size>[_iphoneSe, _iphone14]) {
      testWidgets('fits ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await _pumpApp(
            tester,
            openButton: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) =>
                    const CompareTargetsDialog(initialSelection: <String>{}),
              ),
              child: const Text('open'),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
        });
        expect(find.text('Compare targets'), findsOneWidget);
        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });
    }
  });

  group('RunningTasksDialog', () {
    for (final size in <Size>[_iphoneSe, _iphone14]) {
      testWidgets('fits ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await _pumpApp(
            tester,
            scope: (child) => ProviderScope(
              overrides: [
                runningNotebookTasksProvider.overrideWith(
                  () => _FakeRunningTasksNotifier(_manyTasks()),
                ),
              ],
              child: child,
            ),
            openButton: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => RunningTasksDialog(onCancel: (_) async {}),
              ),
              child: const Text('open'),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
        });
        expect(find.text('Notebook Tasks'), findsOneWidget);
        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });
    }
  });

  group('PublishResultsDialog', () {
    for (final size in <Size>[_iphoneSe, _iphone14]) {
      testWidgets('fits ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await _pumpApp(
            tester,
            openButton: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const PublishResultsDialog(),
              ),
              child: const Text('open'),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
        });
        expect(find.text('Publish to NeuroHub'), findsOneWidget);
        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });
    }
  });

  group('NeuronDetailSheet', () {
    for (final size in <Size>[_iphoneSe, _iphone14]) {
      testWidgets('fits ${size.width.toInt()}x${size.height.toInt()}', (
        tester,
      ) async {
        _useViewport(tester, size);
        final overflows = await _captureOverflows(() async {
          await _pumpApp(
            tester,
            openButton: (context) => ElevatedButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => NeuronDetailSheet(
                  neuronIndex: 3,
                  weights: Float32List.fromList(
                    List<double>.generate(16, (i) => i / 8 - 1),
                  ),
                  side: 4,
                  vmax: 1.0,
                  nInputs: 16,
                ),
              ),
              child: const Text('open'),
            ),
          );
          await tester.tap(find.text('open'));
          await tester.pumpAndSettle();
        });
        expect(find.text('Neuron 3'), findsOneWidget);
        expect(overflows, isEmpty, reason: overflows.join('\n'));
      });
    }
  });
}
