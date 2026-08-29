import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/validation.dart'
    as canvas_validation;
import 'package:neuro_toolkit/features/neurocnl/models/error_detail.dart';
import 'package:neuro_toolkit/features/neurocnl/models/layer2_check.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart' as api_provider;
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/sync_provider.dart'
    as canvas_sync;
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/canvas_api_client.dart' as canvas_api;
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/parse_results_table.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/validation_panel.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../providers_test.mocks.dart';

/// Minimal fake for canvas/sync_provider.dart's ApiClient — just enough to
/// let CanonicalDocController.updateFromCnl (invoked via
/// specTextProvider.notifier.set) resolve without a real network call.
class _FakeCanvasApiClient extends canvas_api.ApiClient {
  _FakeCanvasApiClient() : super(baseUrl: 'http://localhost:8000');

  @override
  Future<ParseCnlResponse> parseCnlCanonical(String specText) async {
    return ParseCnlResponse(
      document: CanonicalEditorDocument(
        irJson: const <String, dynamic>{},
        cnlText: specText,
      ),
      diagnostics: const [],
    );
  }

  @override
  Future<canvas_validation.ValidationResult> validateGraph(
    CanvasGraph graph,
  ) async {
    return canvas_validation.ValidationResult(valid: true, errors: const []);
  }
}

Widget _validationPanelTestApp() {
  return const MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: ValidationPanel()),
  );
}

void main() {
  setUp(() async {
    WorkspaceController.debugSetDebounces(
      persist: Duration.zero,
      serverSync: Duration.zero,
    );
    SharedPreferences.setMockInitialValues({
      'neurocnl_server_url': 'http://localhost:8000',
    });
    await ServerConfigService.initialize();
  });

  testWidgets('ParseResultsTable shows structured parse hints and examples', (
    WidgetTester tester,
  ) async {
    const parseResult = ParseResult(
      sentences: [
        ParseSentence(
          line: 2,
          raw: 'Make a neuron that goes zap fast.',
          valid: false,
          error: 'The sentence does not match any supported CNL grammar.',
          errorDetail: ErrorDetail(
            code: 'unsupported_sentence_family',
            message: 'The sentence does not match any supported CNL grammar.',
            hint: 'This sentence family is not in the supported CNL grammar.',
            examples: [
              'The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0',
            ],
            line: 2,
          ),
        ),
      ],
      total: 1,
      errors: 1,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pipelineProvider.overrideWith(
            () => _FakePipelineController(
              const PipelineState(parseResult: parseResult),
            ),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(height: 400, child: ParseResultsTable()),
          ),
        ),
      ),
    );

    expect(
      find.text('This sentence family is not in the supported CNL grammar.'),
      findsOneWidget,
    );
    expect(find.text('Examples'), findsOneWidget);
    // SelectionArea check removed as NmtkErrorCard text is now selectable
    expect(
      find.text(
        'The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0',
      ),
      findsOneWidget,
    );
  });

  testWidgets(
    'ValidationPanel shows normalized Layer 2 codes instead of Unknown',
    (WidgetTester tester) async {
      const validationResult = ValidationResult(
        layer1: Layer1Result(
          overall: true,
          passed: [],
          failed: [],
          warnings: [
            InvariantResult(
              name: 'loihi_timestep_resolution_mismatch',
              description:
                  'Declared network_timestep differs from Loihi timing resolution.',
              result: true,
              severity: 'warning',
            ),
          ],
        ),
        layer2: Layer2Result(
          overall: false,
          checksPassed: [],
          checksFailed: [
            Layer2Check(
              name: 'zero_weight_synapse',
              description: 'Connection has zero weight.',
              code: 'zero_weight_synapse',
              message: 'Connection has zero weight.',
              lines: [3],
              params: {
                'code': 'zero_weight_synapse',
                'message': 'Connection has zero weight.',
              },
            ),
          ],
          neuronsFound: ['sensory neuron', 'motor neuron'],
        ),
        overall: false,
        backendSupport: BackendSupportResult(
          backend: 'loihi',
          verdict: 'approximate',
          warnings: [
            'Declared network_timestep differs from backend timing resolution.',
          ],
          approximatedConcepts: ['network_topology'],
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pipelineProvider.overrideWith(
              () => _FakePipelineController(
                const PipelineState(validateResult: validationResult),
              ),
            ),
          ],
          child: _validationPanelTestApp(),
        ),
      );

      expect(
        find.textContaining('Connection has zero weight.'),
        findsOneWidget,
      );
      // SelectionArea check removed as NmtkErrorCard text is now selectable
      expect(find.text('Unknown'), findsNothing);
      expect(find.text('zero weight synapse'), findsOneWidget);
      expect(find.text('zero_weight_synapse'), findsNothing);
    },
  );

  testWidgets(
    'ValidationPanel shows passed Layer 1 invariants once with readable labels',
    (WidgetTester tester) async {
      const validationResult = ValidationResult(
        layer1: Layer1Result(
          overall: true,
          passed: [
            InvariantResult(
              name: 'threshold_above_resting',
              description: "Invariant 'threshold_above_resting' satisfied",
              result: true,
            ),
          ],
          failed: [],
        ),
        layer2: Layer2Result(
          overall: true,
          checksPassed: [],
          checksFailed: [],
          neuronsFound: [],
        ),
        overall: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pipelineProvider.overrideWith(
              () => _FakePipelineController(
                const PipelineState(validateResult: validationResult),
              ),
            ),
          ],
          child: _validationPanelTestApp(),
        ),
      );

      await tester.tap(find.textContaining('Layer 1').first);
      await tester.pumpAndSettle();

      expect(
        find.text("Invariant 'threshold above resting' satisfied"),
        findsOneWidget,
      );
      expect(
        find.textContaining("Invariant 'threshold_above_resting' satisfied"),
        findsNothing,
      );
      expect(find.text('threshold above resting'), findsNothing);
      expect(find.text('No warnings or failures.'), findsNothing);
    },
  );

  testWidgets('ValidationPanel shows passed Layer 2 checks when expanded', (
    WidgetTester tester,
  ) async {
    const validationResult = ValidationResult(
      layer1: Layer1Result(overall: true, passed: [], failed: []),
      layer2: Layer2Result(
        overall: true,
        checksPassed: ['no_zero_weight_synapses'],
        checksFailed: [],
        neuronsFound: [],
      ),
      overall: true,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pipelineProvider.overrideWith(
            () => _FakePipelineController(
              const PipelineState(validateResult: validationResult),
            ),
          ),
        ],
        child: _validationPanelTestApp(),
      ),
    );

    await tester.tap(find.textContaining('Layer 2').first);
    await tester.pumpAndSettle();

    expect(find.text('no zero weight synapses'), findsOneWidget);
    expect(find.text('No warnings or failures.'), findsNothing);
  });

  testWidgets('ValidationPanel tolerates repeated parse errors', (
    WidgetTester tester,
  ) async {
    const validationResult = ValidationResult(
      layer1: Layer1Result(
        overall: false,
        passed: [],
        failed: [
          InvariantResult(
            name: 'ParseError',
            description: 'Unexpected character.',
            result: false,
          ),
          InvariantResult(
            name: 'ParseError',
            description: 'Missing required keyword.',
            result: false,
          ),
        ],
      ),
      layer2: Layer2Result(
        overall: false,
        checksPassed: [],
        checksFailed: [
          Layer2Check(
            name: 'ParseError',
            description: 'Unexpected character.',
            message: 'Unexpected character.',
            params: {},
          ),
          Layer2Check(
            name: 'ParseError',
            description: 'Missing required keyword.',
            message: 'Missing required keyword.',
            params: {},
          ),
        ],
        neuronsFound: [],
      ),
      overall: false,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pipelineProvider.overrideWith(
            () => _FakePipelineController(
              const PipelineState(validateResult: validationResult),
            ),
          ),
        ],
        child: _validationPanelTestApp(),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('Unexpected character.'), findsWidgets);
    expect(find.textContaining('Missing required keyword.'), findsWidgets);
  });

  test(
    'validationPanelSnapshotProvider does not notify on spec edits when validation state is unchanged',
    () async {
      final mockApi = MockApiClient();
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

      final container = ProviderContainer(
        overrides: [
          api_provider.apiClientProvider.overrideWithValue(mockApi),
          canvas_sync.apiClientProvider.overrideWithValue(
            _FakeCanvasApiClient(),
          ),
        ],
      );
      addTearDown(container.dispose);

      var notifications = 0;
      final sub = container.listen(
        validationPanelSnapshotProvider,
        (_, _) => notifications++,
        fireImmediately: true,
      );
      addTearDown(sub.close);

      expect(notifications, 1);

      await container.read(specTextProvider.notifier).set('edited spec');

      expect(
        container
            .read(workspaceProvider)
            .activeFile
            ?.canonicalDocument
            ?.cnlText,
        'edited spec',
      );
      expect(notifications, 1);
    },
  );
}

class _FakePipelineController extends PipelineController {
  _FakePipelineController(this._initial);
  final PipelineState _initial;
  @override
  PipelineState build() => _initial;
}
