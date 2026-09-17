import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_connect_palette.dart';

const List<CanvasConnectPaletteEntry> _entries = <CanvasConnectPaletteEntry>[
  CanvasConnectPaletteEntry(
    id: 'spikeEncoder',
    label: 'Spike Encoder',
    icon: Icons.bolt,
    accent: Color(0xFF1E88E5),
    ports: <CanvasConnectPalettePort>[
      CanvasConnectPalettePort(id: 'data', label: 'data'),
    ],
  ),
  CanvasConnectPaletteEntry(
    id: 'forwardPass',
    label: 'Forward Pass',
    icon: Icons.arrow_forward,
    accent: Color(0xFF43A047),
    ports: <CanvasConnectPalettePort>[
      CanvasConnectPalettePort(id: 'input', label: 'input'),
      CanvasConnectPalettePort(id: 'model', label: 'model'),
    ],
  ),
];

/// Mutable holder so a test can assert on the palette's result after it closes.
class _Outcome {
  bool closed = false;
  CanvasConnectPaletteResult? result;
}

/// Pumps a host with an open palette. `NmtkShellTokens.of` falls back to
/// deriving tokens from the ColorScheme, so no theme extension is needed.
Future<_Outcome> _openPalette(
  WidgetTester tester, {
  CanvasConnectDirection direction = CanvasConnectDirection.fromOutput,
  List<CanvasConnectPaletteEntry> entries = _entries,
}) async {
  await tester.binding.setSurfaceSize(const Size(1200, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final _Outcome outcome = _Outcome();

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () async {
              outcome.result = await showCanvasConnectPalette(
                context: context,
                direction: direction,
                entries: entries,
              );
              outcome.closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return outcome;
}

void main() {
  testWidgets('renders one tile per entry, with a row per facing port', (
    WidgetTester tester,
  ) async {
    await _openPalette(tester);

    expect(find.text('Spike Encoder'), findsOneWidget);
    expect(find.text('Forward Pass'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('palette_port_spikeEncoder_data')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('palette_port_forwardPass_input')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('palette_port_forwardPass_model')),
      findsOneWidget,
    );
  });

  testWidgets('the wording states which side the wire attaches to', (
    WidgetTester tester,
  ) async {
    await _openPalette(tester);
    expect(find.text('Pick the input port to wire into.'), findsOneWidget);
  });

  testWidgets('an input-side palette asks for an output port instead', (
    WidgetTester tester,
  ) async {
    await _openPalette(tester, direction: CanvasConnectDirection.fromInput);
    expect(find.text('Pick the output port to wire from.'), findsOneWidget);
  });

  testWidgets('tapping a port row resolves to that entry and port', (
    WidgetTester tester,
  ) async {
    final _Outcome outcome = await _openPalette(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('palette_port_forwardPass_model')),
    );
    await tester.pumpAndSettle();

    expect(outcome.result, isNotNull);
    expect(outcome.result!.entryId, 'forwardPass');
    expect(outcome.result!.portId, 'model');
  });

  testWidgets('tapping the tile body takes the first port', (
    WidgetTester tester,
  ) async {
    final _Outcome outcome = await _openPalette(tester);

    await tester.tap(find.text('Forward Pass'));
    await tester.pumpAndSettle();

    expect(outcome.result!.entryId, 'forwardPass');
    expect(outcome.result!.portId, 'input');
  });

  testWidgets('the search field narrows the grid and Enter picks the top hit', (
    WidgetTester tester,
  ) async {
    final _Outcome outcome = await _openPalette(tester);

    await tester.enterText(find.byType(TextField), 'forward');
    await tester.pumpAndSettle();

    expect(find.text('Forward Pass'), findsOneWidget);
    expect(find.text('Spike Encoder'), findsNothing);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(outcome.result!.entryId, 'forwardPass');
  });

  testWidgets('a port-id query surfaces a node whose label does not match', (
    WidgetTester tester,
  ) async {
    await _openPalette(tester);

    await tester.enterText(find.byType(TextField), 'model');
    await tester.pumpAndSettle();

    expect(find.text('Forward Pass'), findsOneWidget);
    expect(find.text('Spike Encoder'), findsNothing);
  });

  testWidgets('an unmatched query says so rather than showing a blank grid', (
    WidgetTester tester,
  ) async {
    await _openPalette(tester);

    await tester.enterText(find.byType(TextField), 'zzzzzzzz');
    await tester.pumpAndSettle();

    expect(find.text('No matching nodes'), findsOneWidget);
    expect(find.text('Forward Pass'), findsNothing);
  });

  testWidgets('dismissing resolves to null', (WidgetTester tester) async {
    final _Outcome outcome = await _openPalette(tester);

    Navigator.of(tester.element(find.text('Forward Pass'))).pop();
    await tester.pumpAndSettle();

    expect(outcome.closed, isTrue);
    expect(outcome.result, isNull);
  });
}
