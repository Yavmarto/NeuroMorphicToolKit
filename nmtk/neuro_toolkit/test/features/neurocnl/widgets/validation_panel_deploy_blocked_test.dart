// Tests that ValidationPanel renders a prominent "Deploy Blocked" banner when
// backendSupport.verdict == 'unsupported', and suppresses it otherwise.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/validation_panel.dart';

const _unsupportedBackendFixture = ValidationResult(
  layer1: Layer1Result(
    overall: true,
    passed: [
      InvariantResult(
        name: 'threshold_above_resting',
        description: 'Invariant satisfied',
        result: true,
      ),
    ],
    failed: [],
  ),
  layer2: Layer2Result(
    overall: true,
    checksPassed: ['no_zero_weight_synapses'],
    checksFailed: [],
    neuronsFound: [],
  ),
  overall: true,
  backendSupport: BackendSupportResult(
    backend: 'sinabs',
    verdict: 'unsupported',
    unsupportedConcepts: ['recurrent_connections'],
    warnings: [
      'sinabs requires sequential-only graphs; recurrent connections are not supported.',
    ],
  ),
);

const _unsupportedNoWarningsFixture = ValidationResult(
  layer1: Layer1Result(
    overall: true,
    passed: [
      InvariantResult(
        name: 'threshold_above_resting',
        description: 'Invariant satisfied',
        result: true,
      ),
    ],
    failed: [],
  ),
  layer2: Layer2Result(
    overall: true,
    checksPassed: ['no_zero_weight_synapses'],
    checksFailed: [],
    neuronsFound: [],
  ),
  overall: true,
  backendSupport: BackendSupportResult(
    backend: 'loihi',
    verdict: 'unsupported',
    warnings: [],
  ),
);

const _faithfulBackendFixture = ValidationResult(
  layer1: Layer1Result(
    overall: true,
    passed: [
      InvariantResult(
        name: 'threshold_above_resting',
        description: 'Invariant satisfied',
        result: true,
      ),
    ],
    failed: [],
  ),
  layer2: Layer2Result(
    overall: true,
    checksPassed: ['no_zero_weight_synapses'],
    checksFailed: [],
    neuronsFound: [],
  ),
  overall: true,
  backendSupport: BackendSupportResult(
    backend: 'nir',
    verdict: 'faithful',
    supportedConcepts: ['LIF', 'Linear'],
    warnings: [],
  ),
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

Future<void> _pumpWithFixture(
  WidgetTester tester,
  ValidationResult fixture,
) async {
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        pipelineProvider.overrideWith(
          () => _FakePipelineController(PipelineState(validateResult: fixture)),
        ),
      ],
      child: _validationPanelTestApp(),
    ),
  );
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
    'ValidationPanel shows Deploy Blocked banner when verdict is unsupported',
    (WidgetTester tester) async {
      await _pumpWithFixture(tester, _unsupportedBackendFixture);

      expect(
        find.descendant(
          of: find.byType(ValidationPanel),
          matching: find.textContaining('Deploy Blocked'),
        ),
        findsOneWidget,
        reason:
            'When backendSupport.verdict == "unsupported", the panel must '
            'render a "Deploy Blocked" indicator so the user understands '
            'hardware deploy is not possible.',
      );
    },
  );

  testWidgets(
    'ValidationPanel shows two NmtkStatusBanners when verdict is unsupported',
    (WidgetTester tester) async {
      await _pumpWithFixture(tester, _unsupportedBackendFixture);

      expect(
        find.descendant(
          of: find.byType(ValidationPanel),
          matching: find.byType(NmtkStatusBanner),
        ),
        findsNWidgets(2),
        reason:
            'Unsupported backend verdict must produce two banners: the overall '
            'validation status banner and the Deploy Blocked banner.',
      );
    },
  );

  testWidgets(
    'ValidationPanel does NOT show Deploy Blocked banner when verdict is faithful',
    (WidgetTester tester) async {
      await _pumpWithFixture(tester, _faithfulBackendFixture);

      expect(
        find.descendant(
          of: find.byType(ValidationPanel),
          matching: find.textContaining('Deploy Blocked'),
        ),
        findsNothing,
        reason:
            'When backendSupport.verdict == "faithful", no Deploy Blocked '
            'banner should appear.',
      );
      expect(
        find.descendant(
          of: find.byType(ValidationPanel),
          matching: find.byType(NmtkStatusBanner),
        ),
        findsOneWidget,
        reason:
            'Faithful verdict must produce exactly one banner (the overall '
            'status). No additional Deploy Blocked banner.',
      );
    },
  );

  testWidgets(
    'Deploy Blocked banner contains the first backend warning message',
    (WidgetTester tester) async {
      await _pumpWithFixture(tester, _unsupportedBackendFixture);

      expect(
        find.textContaining('sinabs requires sequential-only graphs'),
        findsOneWidget,
        reason:
            'The first warning from backendSupport.warnings must appear in '
            'the Deploy Blocked banner so the user understands the specific '
            'topology constraint.',
      );
    },
  );

  testWidgets(
    'Deploy Blocked banner uses backend name when warnings list is empty',
    (WidgetTester tester) async {
      await _pumpWithFixture(tester, _unsupportedNoWarningsFixture);

      expect(
        find.textContaining('loihi'),
        findsOneWidget,
        reason:
            'When backendSupport.warnings is empty, the banner must fall back '
            'to a message that includes the backend name.',
      );
      expect(
        find.textContaining('Deploy Blocked'),
        findsOneWidget,
        reason: 'The "Deploy Blocked" prefix must always appear.',
      );
    },
  );
}

class _FakePipelineController extends PipelineController {
  _FakePipelineController(this._initial);
  final PipelineState _initial;
  @override
  PipelineState build() => _initial;
}
