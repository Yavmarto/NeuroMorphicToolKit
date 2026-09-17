import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/simulation_dashboard.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/pipeline_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/l10n/app_localizations.dart';

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await ServerConfigService.initialize();
  });

  testWidgets(
    'SimulationDashboard shows placeholder when no preview is ready',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: SimulationDashboard()),
          ),
        ),
      );

      expect(
        find.text('Compile the current spec to inspect topology and NIR here.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('SimulationDashboard renders compiled topology and NIR preview', (
    WidgetTester tester,
  ) async {
    const result = GenerateResult(
      network: NetworkGraph(
        nodes: [
          NetworkNode(
            id: 'input',
            type: 'population',
            subtype: 'input',
            label: 'Input',
            params: {'size': 4},
          ),
          NetworkNode(
            id: 'output',
            type: 'population',
            subtype: 'output',
            label: 'Output',
            params: {'size': 2},
          ),
        ],
        edges: [
          NetworkEdge(
            id: 'input-output',
            source: 'input',
            target: 'output',
            isInhibitory: false,
            hasLearningRule: false,
            hasDelay: false,
            params: {'weight': 1.0},
          ),
        ],
      ),
      cnlDocument: 'round-trip cnl',
      nirCode: 'graph input -> output',
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pipelineProvider.overrideWith(
            () => _FakePipelineController(
              const PipelineState(
                generateStatus: StepStatus.success,
                simulateStatus: StepStatus.success,
                generateResult: result,
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SimulationDashboard()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Should not show placeholder
    expect(
      find.text('Compile the current spec to inspect topology and NIR here.'),
      findsNothing,
    );

    expect(find.text('Compiled Topology'), findsWidgets);
    expect(find.text('Nodes'), findsOneWidget);
    expect(find.text('Edges'), findsOneWidget);
    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Output'), findsOneWidget);
    expect(find.textContaining('graph input -> output'), findsOneWidget);
  });

  testWidgets('SimulationDashboard shows preview error when run fails', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pipelineProvider.overrideWith(
            () => _FakePipelineController(
              const PipelineState(
                generateStatus: StepStatus.success,
                simulateStatus: StepStatus.error,
                errorMessage:
                    'Simulation failed: ValueError: IR lowering error: Lowering for concept \'stdp_learning\' is not implemented in this phase.',
              ),
            ),
          ),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: SimulationDashboard()),
        ),
      ),
    );

    expect(find.text('Preview failed'), findsOneWidget);
    expect(find.textContaining('stdp_learning'), findsOneWidget);
    expect(
      find.text('Compile the current spec to inspect topology and NIR here.'),
      findsNothing,
    );
  });

  testWidgets(
    'SimulationDashboard prefers the preview error pane over stale generate output',
    (WidgetTester tester) async {
      const result = GenerateResult(
        network: NetworkGraph(
          nodes: [
            NetworkNode(
              id: 'input',
              type: 'population',
              subtype: 'input',
              label: 'Input',
              params: {'size': 4},
            ),
          ],
          edges: [],
        ),
        cnlDocument: 'round-trip cnl',
        nirCode: 'graph input',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pipelineProvider.overrideWith(
              () => _FakePipelineController(
                const PipelineState(
                  generateStatus: StepStatus.success,
                  simulateStatus: StepStatus.error,
                  generateResult: result,
                  errorMessage:
                      'Simulation failed: ApiException(410): {"detail":{"error":"nir_simulation_unsupported","messages":["Simulation is no longer supported on the NIR-only NeuroCNL surface."],"items":[{"code":"nir_simulation_unsupported","message":"Simulation is no longer supported on the NIR-only NeuroCNL surface.","hint":"Use /api/generate to inspect the compiled topology."}]}}',
                ),
              ),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: SimulationDashboard()),
          ),
        ),
      );

      expect(find.text('Not supported on this backend'), findsOneWidget);
      expect(
        find.text(
          'Simulation is no longer supported on the NIR-only NeuroCNL surface.',
        ),
        findsOneWidget,
      );
      expect(find.text('Compiled Topology'), findsNothing);
      expect(find.textContaining('/api/generate'), findsOneWidget);
    },
  );
}

class _FakePipelineController extends PipelineController {
  _FakePipelineController(this._initial);
  final PipelineState _initial;
  @override
  PipelineState build() => _initial;
}
