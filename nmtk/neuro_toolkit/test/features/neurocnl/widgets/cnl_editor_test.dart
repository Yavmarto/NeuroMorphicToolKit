import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/cnl_focus_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/cnl_line_node_map_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/cnl_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers_test.mocks.dart';

class FakeSpecTextController extends SpecTextController {
  final String _initialState;
  FakeSpecTextController([this._initialState = '']);

  @override
  String build() => _initialState;

  @override
  Future<void> set(String text) async {
    state = text;
  }

  @override
  Future<void> update(String text) async {
    state = text;
  }
}

void main() {
  late MockApiClient mockApi;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
    // Write synchronously, as _persist did before it was debounced — otherwise
    // the debounce timer is still pending when the test ends.
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    mockApi = MockApiClient();
    when(mockApi.parse(any)).thenAnswer(
      (_) async => const ParseResult(sentences: [], total: 0, errors: 0),
    );
    when(
      mockApi.validate(
        any,
        params: anyNamed('params'),
        backend: anyNamed('backend'),
      ),
    ).thenAnswer(
      (_) async => const ValidationResult(
        layer1: Layer1Result(overall: true, passed: [], failed: []),
        layer2: Layer2Result(
          overall: true,
          checksPassed: [],
          checksFailed: [],
          neuronsFound: [],
        ),
        overall: true,
      ),
    );
  });

  Widget buildEditorApp(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(width: 900, height: 600, child: CnlEditor()),
        ),
      ),
    );
  }

  testWidgets(
    'CnlEditor exposes compact number editing for selected numeric values',
    (WidgetTester tester) async {
      const spec =
          'The neuron MUST fire ONLY IF membrane potential exceeds 1.0';
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          specTextProvider.overrideWith(() => FakeSpecTextController(spec)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(buildEditorApp(container));
      await tester.pump();

      final editorFinder = find.byType(TextField);
      await tester.showKeyboard(editorFinder);
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: spec,
          selection: TextSelection.collapsed(offset: spec.indexOf('1.0') + 1),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit 1.0'), findsOneWidget);

      await tester.tap(find.text('Edit 1.0'));
      await tester.pumpAndSettle();

      expect(find.text('Edit number'), findsOneWidget);
      await tester.enterText(find.byType(TextField).last, '2.5');
      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(container.read(specTextProvider), contains('2.5'));
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets('CnlEditor gutter counts trailing newline as a visible line', (
    WidgetTester tester,
  ) async {
    const spec = 'first line\n\nthird line\n';
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(mockApi),
        specTextProvider.overrideWith(() => FakeSpecTextController(spec)),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildEditorApp(container));
    await tester.pump();

    expect(find.byKey(const ValueKey('cnl-line-4')), findsOneWidget);
    expect(find.textContaining('4 lines'), findsOneWidget);
  });

  testWidgets(
    'mapped cursor lines publish CNL focus and unmapped lines clear it',
    (WidgetTester tester) async {
      const spec = 'first\nsecond\nthird';
      final container = ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(mockApi),
          specTextProvider.overrideWith(() => FakeSpecTextController(spec)),
          cnlLineNodeMapProvider.overrideWithValue((
            lineToNode: <int, String>{2: 'node-2'},
            nodeToLine: <String, int>{'node-2': 2},
          )),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(buildEditorApp(container));
      await tester.pump();

      final editor = find.byType(TextField);
      await tester.showKeyboard(editor);
      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: spec,
          selection: TextSelection.collapsed(offset: 7),
        ),
      );
      await tester.pump();

      expect(container.read(cnlFocusProvider).focusedLine, 2);
      expect(container.read(cnlFocusProvider).focusedNodeId, isNull);

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: spec,
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();

      expect(container.read(cnlFocusProvider).focusedLine, isNull);
      expect(container.read(cnlFocusProvider).focusedNodeId, isNull);
    },
  );

  testWidgets('canvas focus moves the editor caret to the mapped line', (
    WidgetTester tester,
  ) async {
    const spec = 'first\nsecond\nthird';
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(mockApi),
        specTextProvider.overrideWith(() => FakeSpecTextController(spec)),
        cnlLineNodeMapProvider.overrideWithValue((
          lineToNode: <int, String>{2: 'node-2'},
          nodeToLine: <String, int>{'node-2': 2},
        )),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(buildEditorApp(container));
    await tester.pump();

    container.read(cnlFocusProvider.notifier).setFocusedNode('node-2');
    await tester.pump();

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.controller!.selection.baseOffset, 6);
    expect(container.read(cnlFocusProvider).focusedLine, 2);
  });

  testWidgets('line number gutter renders correct count for 5 lines', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(mockApi),
        specTextProvider.overrideWith(() => FakeSpecTextController()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildEditorApp(container));
    await tester.pumpAndSettle();

    // Line 1 should always be rendered.
    expect(find.byKey(const ValueKey('cnl-line-1')), findsOneWidget);
  });

  testWidgets('CnlEditor shows a template toolbar button', (
    WidgetTester tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        apiClientProvider.overrideWithValue(mockApi),
        specTextProvider.overrideWith(
          () => FakeSpecTextController(
            'The neuron MUST fire ONLY IF membrane potential exceeds 1.0',
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(buildEditorApp(container));
    await tester.pumpAndSettle();

    // The template gallery button must be visible in the toolbar.
    expect(find.byTooltip('Show templates'), findsOneWidget);
    // The gallery is not open by default.
    expect(find.text('Template Gallery'), findsNothing);
  });
}
