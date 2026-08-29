import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/analysis_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/hardware_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/spec_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/analysis_screen.dart';
import 'package:neuro_toolkit/features/neurocnl/screens/hardware_screen.dart';

class _TestAnalysisController extends AnalysisController {
  @override
  AnalysisState build() => const AnalysisState();
  @override
  set state(value) => super.state = value;
  _TestAnalysisController();

  @override
  Future<void> runEnergyProfile(String spec) async {}

  @override
  Future<void> runFaultInjection(String spec, double errorRate) async {}

  @override
  Future<void> runQuantization(String spec, List<int> bits) async {}

  @override
  void reset() {}
}

class _TestSpecTextController extends SpecTextController {
  @override
  String build() => '';
  @override
  set state(value) => super.state = value;
  _TestSpecTextController();

  @override
  Future<void> set(String text) async {}

  @override
  Future<void> update(String text) async {}

  @override
  Future<void> flush() async {}
}

class _TestHardwareController extends HardwareController {
  _TestHardwareController();

  @override
  Future<void> refreshPorts() async {}
}

void main() {
  Widget buildAnalysisHarness() {
    return ProviderScope(
      overrides: [
        analysisProvider.overrideWith(() => _TestAnalysisController()),
        specTextProvider.overrideWith(() => _TestSpecTextController()),
      ],
      child: const MaterialApp(home: Scaffold(body: AnalysisScreen())),
    );
  }

  Widget buildHardwareHarness() {
    return ProviderScope(
      overrides: [
        hardwareProvider.overrideWith(() => _TestHardwareController()),
      ],
      child: const MaterialApp(home: Scaffold(body: HardwareScreen())),
    );
  }

  testWidgets('analysis screen renders shared ownership guidance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildAnalysisHarness());
    await tester.pumpAndSettle();

    expect(find.text('Ownership Boundary'), findsOneWidget);
    expect(
      find.text(
        'Use Analysis for pre-handoff review inside Studio. Execution-specific diagnostics and runtime verification continue in Neurochip after target selection.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('authoring-stage readiness'), findsOneWidget);
  });

  testWidgets('hardware screen renders shared ownership guidance', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildHardwareHarness());
    await tester.pumpAndSettle();

    expect(find.text('Ownership Boundary'), findsOneWidget);
    expect(
      find.text(
        'Use Hardware for local authoring-stage serial checks while shaping a workflow in Studio.',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('recording ownership belong to NeuroSense'),
      findsOneWidget,
    );
    expect(
      find.textContaining('runtime diagnostics belong to Neurochip'),
      findsOneWidget,
    );
  });
}
