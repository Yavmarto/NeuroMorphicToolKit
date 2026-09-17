import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/custom_node_source.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/custom_node_source_editor.dart';

const _validSource = '''
from nmtk_sdk import CustomNode

class TestNode(CustomNode):
    name = "Test"
    category = "neurons"
    canvases = ["model"]
    frameworks = ["nengo"]
    base_component_id = "lif_population"
''';

class _EditorApiClient extends ApiClient {
  _EditorApiClient({required this.isCustom})
    : super(baseUrl: 'http://localhost:0');

  final bool isCustom;

  @override
  Future<CustomNodeSource> fetchCustomNodeSource({
    required String componentId,
    required String displayName,
    required String category,
    required Map<String, dynamic> parameters,
    String? nirType,
    String? pipelineType,
    String? canvasContext,
    List<Map<String, dynamic>> parameterDefinitions = const [],
    List<Map<String, dynamic>> ports = const [],
  }) async {
    return CustomNodeSource(
      source: _validSource,
      componentId: isCustom ? 'custom_test_12345678' : componentId,
      isCustom: isCustom,
      saveMode: isCustom ? 'update' : 'create',
      filename: isCustom ? 'test_12345678.py' : null,
      revision: isCustom ? 'revision' : null,
    );
  }

  @override
  Future<CustomNodeValidation> validateCustomNodeSource(String source) async {
    return const CustomNodeValidation(valid: true, diagnostics: []);
  }
}

CanvasNode _node({required bool custom}) => CanvasNode(
  id: 'node',
  componentId: custom ? 'custom_test_12345678' : 'lif_population',
  nirType: custom ? null : 'nir.LIF',
  label: 'Test node',
  parameters: const <String, dynamic>{'tau': 0.02},
  position: const <double>[0, 0],
);

Widget _app({required bool custom}) {
  return ProviderScope(
    overrides: [
      apiClientProvider.overrideWithValue(_EditorApiClient(isCustom: custom)),
    ],
    child: MaterialApp(
      home: CustomNodeSourceEditor(node: _node(custom: custom), nodeType: null),
    ),
  );
}

void main() {
  testWidgets('built-in source can only be saved as a custom node', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(custom: false));
    await tester.pumpAndSettle();

    expect(find.text('Built-in'), findsOneWidget);
    expect(find.text('Save as custom'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsNothing);
  });

  testWidgets('existing custom source exposes Save and Save as custom', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_app(custom: true));
    await tester.pumpAndSettle();

    expect(find.text('Custom'), findsOneWidget);
    expect(find.text('Save as custom'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
  });
}
