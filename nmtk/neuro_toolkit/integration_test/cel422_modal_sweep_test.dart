// CEL-422 real-device narrow-width modal sweep.
//
// Runs the audited popup / dialog / bottom-sheet surfaces on a real Android
// device (real fonts and renderer) so widget-test-font artifacts do not create
// false overflow reports. Each surface is laid out at the two required phone
// viewports by overriding the test view size inside the running app:
//   375x667  (iPhone SE class) and 390x844 (iPhone 14).
// Prints one RESULT line per surface per viewport with the RenderFlex
// overflows seen.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/layer2_check.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hub/hub_share_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_connect_palette.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/export_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/pipeline_settings_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/cnl_sentence_builder_dialog.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/validation_overlay.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

const List<Size> _logicalSizes = <Size>[Size(375, 667), Size(390, 844)];

Future<List<String>> _collect(Future<void> Function() body) async {
  final overflows = <String>[];
  final original = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final message = details.exceptionAsString();
    if (message.contains('overflowed by')) {
      overflows.add(message.split('\n').first);
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

void _applySize(WidgetTester tester, Size logical) {
  tester.view.devicePixelRatio = 3.0;
  tester.view.physicalSize = Size(logical.width * 3, logical.height * 3);
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  await tester.pumpWidget(
    ZetaProvider(
      initialContrast: ZetaContrast.aa,
      initialThemeMode: ThemeMode.light,
      builder: (context, light, dark, mode) => ProviderScope(
        child: MaterialApp(
          theme: light,
          darkTheme: dark,
          themeMode: mode,
          home: home,
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

ValidationResult _manyFailures() => ValidationResult(
  overall: false,
  layer1: Layer1Result(
    overall: false,
    passed: const <InvariantResult>[],
    failed: <InvariantResult>[
      for (var i = 0; i < 25; i++)
        InvariantResult(
          name: 'invariant_$i',
          description: 'Invariant $i',
          result: false,
          message:
              'Invariant $i failed: the produced value is out of the allowed '
              'range for this layer.',
        ),
    ],
  ),
  layer2: const Layer2Result(
    overall: false,
    checksPassed: <String>[],
    checksFailed: <Layer2Check>[],
    neuronsFound: <String>[],
  ),
);

List<CanvasConnectPaletteEntry> _paletteEntries() => <CanvasConnectPaletteEntry>[
  const CanvasConnectPaletteEntry(
    id: 'lif_population',
    label: 'LIF Population',
    icon: Icons.memory,
    accent: Colors.blue,
    ports: <CanvasConnectPalettePort>[
      CanvasConnectPalettePort(id: 'in_spikes', label: 'in_spikes'),
    ],
  ),
  const CanvasConnectPaletteEntry(
    id: 'synapse',
    label: 'Synapse',
    icon: Icons.cable,
    accent: Colors.green,
    ports: <CanvasConnectPalettePort>[
      CanvasConnectPalettePort(id: 'excitatory', label: 'excitatory'),
    ],
  ),
];

void _report(String name, Size size, List<String> overflows) {
  final label = '${size.width.toInt()}x${size.height.toInt()}';
  // ignore: avoid_print
  print('RESULT $name @ $label overflows=${overflows.length} $overflows');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('viewport probe', (tester) async {
    addTearDown(tester.view.reset);
    for (final size in _logicalSizes) {
      _applySize(tester, size);
      await _pump(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) {
              final mq = MediaQuery.of(context);
              // ignore: avoid_print
              print(
                'VIEWPORT requested=${size.width.toInt()}x${size.height.toInt()} '
                'actual=${mq.size.width.toInt()}x${mq.size.height.toInt()} '
                'dpr=${mq.devicePixelRatio}',
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    }
  });

  testWidgets('ValidationPopup long content', (tester) async {
    addTearDown(tester.view.reset);
    for (final size in _logicalSizes) {
      _applySize(tester, size);
      final overflows = await _collect(() async {
        await _pump(
          tester,
          Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: ValidationPopup(
                parseErrors: 1,
                layer1Failures: 25,
                layer2Failures: 0,
                validationResult: _manyFailures(),
                onClose: () {},
              ),
            ),
          ),
        );
      });
      _report('ValidationPopup', size, overflows);
    }
  });

  testWidgets('NmtkContentDialog long content', (tester) async {
    addTearDown(tester.view.reset);
    for (final size in _logicalSizes) {
      _applySize(tester, size);
      final overflows = await _collect(() async {
        await _pump(
          tester,
          Scaffold(
            body: NmtkContentDialog(
              title: 'Pipeline report',
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (var i = 0; i < 60; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Report line $i — a sentence long enough to wrap.',
                      ),
                    ),
                ],
              ),
              actions: const <Widget>[
                Text('Cancel'),
                Text('Copy'),
                Text('Save'),
              ],
            ),
          ),
        );
      });
      _report('NmtkContentDialog', size, overflows);
    }
  });

  testWidgets('NmtkCommandPalette', (tester) async {
    addTearDown(tester.view.reset);
    for (final size in _logicalSizes) {
      _applySize(tester, size);
      final overflows = await _collect(() async {
        await _pump(
          tester,
          Scaffold(
            body: NmtkCommandPalette(
              commands: <NmtkCommand>[
                for (var i = 0; i < 30; i++)
                  NmtkCommand(
                    id: 'cmd_$i',
                    label: 'Command number $i with a long label',
                    description: 'Runs the thing for command $i',
                    icon: Icons.settings,
                    onExecute: () {},
                  ),
              ],
              onDismiss: () {},
            ),
          ),
        );
      });
      _report('NmtkCommandPalette', size, overflows);
    }
  });

  testWidgets('HubShareDialog', (tester) async {
    addTearDown(tester.view.reset);
    for (final size in _logicalSizes) {
      _applySize(tester, size);
      final overflows = await _collect(() async {
        await _pump(
          tester,
          Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) =>
                        HubShareDialog(benchmark: false, onSave: (_) {}),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      });
      _report('HubShareDialog', size, overflows);
    }
  });

  testWidgets('CnlSentenceBuilderDialog', (tester) async {
    addTearDown(tester.view.reset);
    for (final size in _logicalSizes) {
      _applySize(tester, size);
      final overflows = await _collect(() async {
        await _pump(tester, const Scaffold(body: CnlSentenceBuilderDialog()));
      });
      _report('CnlSentenceBuilderDialog', size, overflows);
    }
  });

  testWidgets('ExportDialog', (tester) async {
    addTearDown(tester.view.reset);
    for (final size in _logicalSizes) {
      _applySize(tester, size);
      final overflows = await _collect(() async {
        await _pump(
          tester,
          const Scaffold(body: ExportDialog(graphJson: <String, dynamic>{})),
        );
      });
      _report('ExportDialog', size, overflows);
    }
  });

  testWidgets('showPipelineSettingsDialog', (tester) async {
    addTearDown(tester.view.reset);
    for (final size in _logicalSizes) {
      _applySize(tester, size);
      final overflows = await _collect(() async {
        await _pump(
          tester,
          Scaffold(
            body: Center(
              child: Consumer(
                builder: (context, ref, _) => ElevatedButton(
                  onPressed: () => showPipelineSettingsDialog(context, ref),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      });
      _report('PipelineSettingsDialog', size, overflows);
    }
  });

  testWidgets('showCanvasConnectPalette sheet', (tester) async {
    addTearDown(tester.view.reset);
    for (final size in _logicalSizes) {
      _applySize(tester, size);
      final overflows = await _collect(() async {
        await _pump(
          tester,
          Scaffold(
            body: Center(
              child: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () => showCanvasConnectPalette(
                    context: context,
                    direction: CanvasConnectDirection.fromOutput,
                    entries: _paletteEntries(),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
      });
      _report('CanvasConnectPalette', size, overflows);
    }
  });

  testWidgets('CanvasConnectPalette keyboard + tap targets', (tester) async {
    addTearDown(tester.view.reset);
    _applySize(tester, const Size(375, 667));
    await _pump(
      tester,
      Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCanvasConnectPalette(
                context: context,
                direction: CanvasConnectDirection.fromOutput,
                entries: _paletteEntries(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final portRows = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('palette_port_'),
    );
    for (final element in portRows.evaluate()) {
      final key = (element.widget.key! as ValueKey<String>).value;
      final s = tester.getSize(find.byKey(ValueKey<String>(key)));
      // ignore: avoid_print
      print('PORT_TAP $key ${s.width}x${s.height}');
    }

    final beforeField = tester.getRect(find.byType(TextField).first);
    // ignore: avoid_print
    print(
      'KEYBOARD beforeOpen field=${beforeField.top}..${beforeField.bottom}',
    );
  });

  testWidgets('CanvasConnectPalette keyboard inset (keyboard open first)',
      (tester) async {
    addTearDown(tester.view.reset);
    _applySize(tester, const Size(375, 667));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await _pump(
      tester,
      Scaffold(
        body: Center(
          child: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showCanvasConnectPalette(
                context: context,
                direction: CanvasConnectDirection.fromOutput,
                entries: _paletteEntries(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final field = tester.getRect(find.byType(TextField).first);
    // ignore: avoid_print
    print(
      'KEYBOARD withKeyboard field=${field.top}..${field.bottom} '
      'keyboardTop=367',
    );
  });
}
