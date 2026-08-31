import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart' show ZetaButton;
import 'package:neuro_toolkit/features/neurocnl/screens/analysis_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/analysis_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/models/fault_injection_report.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/loading_shimmer.dart';

class MockAnalysisController extends AnalysisController {
  MockAnalysisController(this._initialState);
  final AnalysisState _initialState;

  @override
  AnalysisState build() => _initialState;

  @override
  Future<void> runFaultInjection(String spec, double errorRate) async {}

  @override
  Future<void> runEnergyProfile(String spec) async {}

  @override
  Future<void> runQuantization(String spec, List<int> bits) async {}

  @override
  void reset() {}
}

class MockSpecTextController extends SpecTextController {
  MockSpecTextController(this._initialState);
  final String _initialState;

  @override
  String build() => _initialState;

  @override
  Future<void> update(String text) async {}

  @override
  Future<void> set(String text) async {}

  @override
  Future<void> flush() async {}
}

void main() {
  group('Fault Injection Tab Tests', () {
    Widget buildTestWidget(AnalysisState mockState, {String spec = ''}) {
      return ProviderScope(
        overrides: [
          analysisProvider.overrideWith(
            () => MockAnalysisController(mockState),
          ),
          specTextProvider.overrideWith(() => MockSpecTextController(spec)),
        ],
        child: const MaterialApp(home: Scaffold(body: AnalysisScreen())),
      );
    }

    testWidgets('Empty State - Initial Render', (WidgetTester tester) async {
      await tester.pumpWidget(buildTestWidget(const AnalysisState()));
      // We must tap the 3rd tab to see it
      await tester.tap(find.text('Fault Injection'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Set an error rate and run analysis to measure\nnetwork resilience under fault conditions.',
        ),
        findsOneWidget,
      );
      expect(find.text('Load a spec in the Studio tab first.'), findsOneWidget);

      final Finder buttonFinder = find.byType(ZetaButton);
      final ZetaButton button = tester.widget<ZetaButton>(
        buttonFinder.last,
      ); // There are 3 buttons (one for each tab), but since we tapped Fault Injection it should be the active one.
      expect(button.onPressed, isNull);
    });

    testWidgets('Loading State', (WidgetTester tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          const AnalysisState(faultInjectionStatus: AnalysisStatus.loading),
          spec: 'some spec',
        ),
      );
      await tester.tap(find.text('Fault Injection'));
      await tester.pump();
      await tester.pump(
        const Duration(milliseconds: 300),
      ); // wait for tab animation

      expect(find.text('Running…'), findsOneWidget);
      expect(find.byType(LoadingShimmer), findsWidgets);
    });

    testWidgets('Populated State', (WidgetTester tester) async {
      const mockReport = FaultInjectionReport(
        errorRate: 0.1,
        baselineAccuracy: 0.95,
        degradedAccuracy: 0.85,
        failedNodes: ['sensor_node'],
        resilienceScore: 0.89,
      );

      await tester.pumpWidget(
        buildTestWidget(
          const AnalysisState(
            faultInjectionStatus: AnalysisStatus.complete,
            faultInjectionReport: mockReport,
          ),
          spec: 'some spec',
        ),
      );
      await tester.tap(find.text('Fault Injection'));
      await tester.pump();
      await tester.pump(
        const Duration(milliseconds: 300),
      ); // wait for tab animation

      expect(find.text('95.0%'), findsOneWidget); // Baseline
      expect(find.text('85.0%'), findsOneWidget); // Degraded
      expect(find.text('89.0%'), findsOneWidget); // Resilience
      expect(find.text('sensor_node'), findsOneWidget); // Failed Node
    });
  });
}
