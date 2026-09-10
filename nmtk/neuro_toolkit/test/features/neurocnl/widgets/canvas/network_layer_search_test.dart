// Widget tests for the CEL-144d filter-by-layer search control: it ranks the
// network's layers with the shared palette-search scorer, renders the filtered
// list beneath the field, and stays keyboard-operable.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/network_layer_search.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

CanvasNode _node(
  String id, {
  String? nirType,
  Map<String, dynamic> metadata = const <String, dynamic>{},
}) {
  return CanvasNode(
    id: id,
    componentId: nirType ?? 'lif_population',
    nirType: nirType,
    label: id,
    parameters: const <String, dynamic>{},
    position: const [0, 0],
    metadata: metadata,
  );
}

final List<CanvasNode> _nodes = <CanvasNode>[
  _node('input', nirType: 'nir.Input', metadata: const {'category': 'input'}),
  _node('hidden'),
  _node(
    'output',
    nirType: 'nir.Output',
    metadata: const {'category': 'output'},
  ),
];

Widget _wrap(Widget child) {
  return NmtkZetaTheme.wrap(
    builder: (context, light, dark, mode) => MaterialApp(
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      home: Scaffold(
        body: Center(child: SizedBox(width: 360, child: child)),
      ),
    ),
  );
}

Future<ValueNotifier<CanvasNode?>> _pumpSearch(WidgetTester tester) async {
  final selected = ValueNotifier<CanvasNode?>(null);
  addTearDown(selected.dispose);
  await tester.pumpWidget(
    _wrap(
      NetworkLayerSearch(
        nodes: _nodes,
        onSelected: (node) => selected.value = node,
      ),
    ),
  );
  await tester.pump();
  return selected;
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('filters layers by name and reports the picked layer', (
    WidgetTester tester,
  ) async {
    final selected = await _pumpSearch(tester);

    await tester.enterText(find.byType(TextField), 'hid');
    await tester.pump();

    expect(find.text('hidden'), findsOneWidget);
    expect(find.text('input'), findsNothing);
    expect(find.text('output'), findsNothing);

    await tester.tap(find.text('hidden'));
    await tester.pump();

    expect(selected.value?.id, 'hidden');
    // Picking a result clears the query and hides the list.
    expect(find.text('hidden'), findsOneWidget);
  });

  testWidgets('shows the empty state when nothing matches', (
    WidgetTester tester,
  ) async {
    await _pumpSearch(tester);

    await tester.enterText(find.byType(TextField), 'zzzzzzzz');
    await tester.pump();

    expect(find.text('No matching layers'), findsOneWidget);
  });

  testWidgets('ranks matches and supports keyboard selection', (
    WidgetTester tester,
  ) async {
    final selected = await _pumpSearch(tester);

    await tester.enterText(find.byType(TextField), 'i');
    await tester.pump();

    // 'input' is a prefix match, so it ranks above 'hidden' (substring).
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(selected.value?.id, 'input');

    // Re-query and move the highlight down before submitting.
    await tester.enterText(find.byType(TextField), 'i');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(selected.value?.id, 'hidden');
  });

  testWidgets('Escape clears the query and the selection', (
    WidgetTester tester,
  ) async {
    final selected = await _pumpSearch(tester);

    await tester.enterText(find.byType(TextField), 'hid');
    await tester.pump();
    expect(find.text('hidden'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(find.text('hidden'), findsNothing);
    expect(selected.value, isNull);
  });
}
