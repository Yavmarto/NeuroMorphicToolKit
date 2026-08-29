// Regression test for zeta-card-reduction Task 6: ValidationPanel renders
// the Validate tab WITHOUT any NmtkSurfaceCard / NeurocnlSectionCard ancestor
// in its main subtree. Status surfaces use NmtkStatusBanner; expandable
// layers use ZetaAccordion (inCard: false); rows use ZetaListItem; the
// previously-nested "Neurons found" sub-card is now flat typography + chips.
//
// Validates the outcome of zeta-card-reduction Task 6: zero card nesting,
// Zeta primitives across the surface.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/layer2_check.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/deploy_readiness_result.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/validation_panel.dart';

const _validationFixture = ValidationResult(
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
    checksPassed: ['no_zero_weight_synapses'],
    checksFailed: [],
    // Non-empty so the inline "Neurons found" block actually renders.
    neuronsFound: ['sensory_neuron', 'motor_neuron'],
  ),
  overall: true,
);

const _parseFixture = ParseResult(
  sentences: [
    ParseSentence(
      line: 1,
      raw: 'Define a LIF named sensory.',
      valid: true,
      parsed: ParsedSpec(
        subject: 'sensory',
        concept: 'LIF',
        action: 'Define',
        verb: 'is',
        negated: false,
      ),
    ),
    ParseSentence(
      line: 2,
      raw: 'Make neuron go boom.',
      valid: false,
      error: 'Unsupported sentence family.',
    ),
  ],
  total: 2,
  errors: 1,
);

Widget _validationPanelTestApp() {
  return ZetaProvider(
    initialContrast: ZetaContrast.aa,
    initialThemeMode: ThemeMode.dark,
    builder: (context, light, dark, mode) => MaterialApp(
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: ValidationPanel()),
    ),
  );
}

Future<void> _pumpValidationPanel(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pipelineProvider.overrideWith(
          () => _FakePipelineController(
            const PipelineState(validateResult: _validationFixture),
          ),
        ),
      ],
      child: _validationPanelTestApp(),
    ),
  );
  // Two pumps let Zeta widgets settle without timing out the close-icon ripple.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 16));
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

  testWidgets(
    'Merged panel renders Parsing section first with accordion-styled rows',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pipelineProvider.overrideWith(
              () => _FakePipelineController(
                const PipelineState(
                  parseResult: _parseFixture,
                  validateResult: _validationFixture,
                ),
              ),
            ),
          ],
          child: _validationPanelTestApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      final parsingHeader = find.textContaining('Parsing');
      final statusBanner = find.byType(NmtkStatusBanner);
      final layer1Header = find.textContaining('Layer 1');

      expect(parsingHeader, findsWidgets);
      expect(find.text('Validation'), findsNothing);
      expect(statusBanner, findsOneWidget);
      expect(layer1Header, findsOneWidget);

      final parsingTop = tester.getTopLeft(parsingHeader.first).dy;
      final statusTop = tester.getTopLeft(statusBanner.first).dy;
      final layer1Top = tester.getTopLeft(layer1Header.first).dy;
      expect(statusTop, lessThan(parsingTop));
      expect(parsingTop, lessThan(layer1Top));

      await tester.tap(find.textContaining('Parsing').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      expect(find.text('Define a LIF named sensory.'), findsOneWidget);
      expect(find.text('Make neuron go boom.'), findsOneWidget);
    },
  );

  testWidgets(
    'ValidationPanel contains zero NmtkSurfaceCard in its main subtree',
    (WidgetTester tester) async {
      await _pumpValidationPanel(tester);

      // The validation panel is now flat: status banners + accordion + list
      // items. No NmtkSurfaceCard ancestor anywhere.
      expect(
        find.descendant(
          of: find.byType(ValidationPanel),
          matching: find.byType(NmtkSurfaceCard),
        ),
        findsNothing,
        reason:
            'ValidationPanel must render without any NmtkSurfaceCard ancestor '
            '(zeta-card-reduction Task 6 — no card nesting).',
      );
    },
  );

  testWidgets(
    'ValidationPanel uses NmtkStatusBanner for overall + backend support',
    (WidgetTester tester) async {
      await _pumpValidationPanel(tester);

      // The fixture overall=true so we expect the success banner.
      expect(
        find.descendant(
          of: find.byType(ValidationPanel),
          matching: find.byType(NmtkStatusBanner),
        ),
        findsOneWidget,
        reason:
            'ValidationPanel must use NmtkStatusBanner for the overall '
            'status banner (zeta-card-reduction Task 6). The fixture has no '
            'backendSupport, so only the overall banner renders.',
      );
      expect(
        find.descendant(
          of: find.byType(ValidationPanel),
          matching: find.byType(NmtkValidationChip),
        ),
        findsNothing,
        reason:
            'ValidationPanel should keep only a single top status banner '
            'and no separate validation chip.',
      );
    },
  );

  testWidgets('ValidationPanel uses parsing and validation accordions', (
    WidgetTester tester,
  ) async {
    await _pumpValidationPanel(tester);

    expect(
      find.descendant(
        of: find.byType(ValidationPanel),
        matching: find.byType(ZetaAccordion),
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Parsing'), findsWidgets);
    // Both layer titles render in the accordion header rows.
    expect(find.textContaining('Layer 1'), findsOneWidget);
    expect(find.textContaining('Layer 2'), findsOneWidget);
  });

  testWidgets(
    'Neurons found chips render flat inside Layer 2 (no card surface)',
    (WidgetTester tester) async {
      await _pumpValidationPanel(tester);

      // The accordion items render their title rows always, but their child
      // bodies only when expanded. Tap the Layer 2 header to expand and
      // reveal the inline "Neurons found" block.
      await tester.tap(find.textContaining('Layer 2').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // The "Neurons found" label is plain text — no card frame.
      expect(find.text('Neurons found'), findsOneWidget);

      // Both fixture neurons render as ZetaAssistChip labels.
      expect(find.text('sensory_neuron'), findsOneWidget);
      expect(find.text('motor_neuron'), findsOneWidget);

      // CRITICAL: No NmtkSurfaceCard ancestor wraps the "Neurons found"
      // typography block. This was the visible nested card in screenshot 2.
      final neuronsFoundFinder = find.text('Neurons found');
      expect(
        find.ancestor(
          of: neuronsFoundFinder,
          matching: find.byType(NmtkSurfaceCard),
        ),
        findsNothing,
        reason:
            'The "Neurons found" block must NOT be wrapped in NmtkSurfaceCard '
            '(zeta-card-reduction Task 6 — removes the nested card visible '
            'in the original screenshot 2).',
      );
    },
  );

  testWidgets(
    'Failure rows render as ZetaListItem in the validation panel subtree',
    (WidgetTester tester) async {
      const failureFixture = ValidationResult(
        layer1: Layer1Result(
          overall: false,
          passed: [],
          failed: [
            InvariantResult(
              name: 'threshold_above_resting',
              description: 'Threshold below resting potential.',
              result: false,
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
              params: {},
            ),
          ],
          neuronsFound: [],
        ),
        overall: false,
      );

      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pipelineProvider.overrideWith(
              () => _FakePipelineController(
                const PipelineState(validateResult: failureFixture),
              ),
            ),
          ],
          child: _validationPanelTestApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // Expand both layers to reveal failure rows.
      await tester.tap(find.textContaining('Layer 1').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tap(find.textContaining('Layer 2').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));

      // Two failure rows should be ZetaListItems.
      expect(
        find.descendant(
          of: find.byType(ValidationPanel),
          matching: find.byType(ZetaListItem),
        ),
        findsNWidgets(2),
        reason:
            'Each validation failure row must render as exactly one '
            'ZetaListItem (zeta-card-reduction Task 6). Re-introduction '
            'of the deleted NmtkItemCard wrapper is enforced at source '
            'level by the T13 governance tests.',
      );
    },
  );

  group('Deploy readiness section', () {
    Future<void> pumpWithReadiness(
      WidgetTester tester, {
      required StepStatus status,
      DeployReadinessResult? result,
    }) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pipelineProvider.overrideWith(
              () => _FakePipelineController(
                PipelineState(
                  validateResult: _validationFixture,
                  deployReadinessStatus: status,
                  deployReadinessResult: result,
                ),
              ),
            ),
          ],
          child: _validationPanelTestApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
    }

    testWidgets('idle status renders no deploy-readiness banner', (
      WidgetTester tester,
    ) async {
      await pumpWithReadiness(tester, status: StepStatus.idle);

      // Only the overall status banner should render.
      expect(
        find.descendant(
          of: find.byType(ValidationPanel),
          matching: find.byType(NmtkStatusBanner),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ok result renders a success "Ready to deploy" banner', (
      WidgetTester tester,
    ) async {
      await pumpWithReadiness(
        tester,
        status: StepStatus.success,
        result: const DeployReadinessResult.ok(),
      );

      expect(
        find.textContaining('Ready to deploy on sc_neurocore_fpga'),
        findsOneWidget,
      );
    });

    testWidgets(
      'unsupported(approximate) renders a warning banner with node chips',
      (WidgetTester tester) async {
        await pumpWithReadiness(
          tester,
          status: StepStatus.success,
          result: const DeployReadinessResult.unsupported(
            level: 'approximate',
            unsupportedNodes: ['adaptive_lif'],
            diagnostics: ['adaptive_lif approximated'],
          ),
        );

        expect(find.textContaining('Deploy Warning'), findsOneWidget);
        expect(find.text('adaptive_lif'), findsOneWidget);
      },
    );

    testWidgets(
      'unsupported(unsupported) renders a danger banner with node chips '
      'and diagnostics',
      (WidgetTester tester) async {
        await pumpWithReadiness(
          tester,
          status: StepStatus.success,
          result: const DeployReadinessResult.unsupported(
            level: 'unsupported',
            unsupportedNodes: ['stdp_synapse'],
            diagnostics: ['stdp_synapse not supported'],
          ),
        );

        expect(find.textContaining('Deploy Blocked'), findsOneWidget);
        expect(find.text('stdp_synapse'), findsOneWidget);
        expect(
          find.textContaining('stdp synapse not supported'),
          findsOneWidget,
        );
      },
    );

    testWidgets('error result renders a danger banner with the message', (
      WidgetTester tester,
    ) async {
      await pumpWithReadiness(
        tester,
        status: StepStatus.error,
        result: const DeployReadinessResult.error(message: 'network timeout'),
      );

      expect(
        find.textContaining('Deploy readiness check failed'),
        findsOneWidget,
      );
      expect(find.textContaining('network timeout'), findsOneWidget);
    });

    testWidgets('deploy-readiness banner is not wrapped in NmtkSurfaceCard', (
      WidgetTester tester,
    ) async {
      await pumpWithReadiness(
        tester,
        status: StepStatus.success,
        result: const DeployReadinessResult.unsupported(
          level: 'unsupported',
          unsupportedNodes: ['stdp_synapse'],
          diagnostics: [],
        ),
      );

      expect(
        find.descendant(
          of: find.byType(ValidationPanel),
          matching: find.byType(NmtkSurfaceCard),
        ),
        findsNothing,
      );
    });
  });
}

class _FakePipelineController extends PipelineController {
  _FakePipelineController(this._initial);
  final PipelineState _initial;
  @override
  PipelineState build() => _initial;
}
