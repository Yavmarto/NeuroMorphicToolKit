import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('NMTK UI Core Widgets Smoke Tests', () {
    testWidgets('NmtkPrimaryButton renders correctly', (
      WidgetTester tester,
    ) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NmtkPrimaryButton(
              label: 'Test Button',
              onPressed: () {
                pressed = true;
              },
              icon: Icons.add,
            ),
          ),
        ),
      );

      expect(find.text('Test Button'), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
      await tester.tap(find.byType(ElevatedButton));
      expect(pressed, isTrue);
    });

    testWidgets('NmtkEnergyBarChart renders correctly', (
      WidgetTester tester,
    ) async {
      const report = EnergyReport(
        perEnsemblePj: {'E1': 10.0, 'E2': 20.0},
        totalPj: 30.0,
        opsCount: 100,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NmtkEnergyBarChart(report: report)),
        ),
      );

      expect(find.text('Total Energy'), findsOneWidget);
      expect(find.text('30.00 pJ'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
      expect(find.text('E1'), findsOneWidget);
      expect(find.text('10.00 pJ'), findsOneWidget);
    });

    testWidgets('NmtkQuantizationTable renders correctly', (
      WidgetTester tester,
    ) async {
      const report = QuantizationReport(
        bitWidths: [8, 4],
        accuracyDrops: [0.01, 0.06],
        sparsity: [0.5, 0.8],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NmtkQuantizationTable(report: report)),
        ),
      );

      expect(find.text('8-bit'), findsOneWidget);
      expect(find.text('4-bit'), findsOneWidget);
      expect(find.text('1.00%'), findsOneWidget);
      expect(find.text('6.00%'), findsOneWidget);
    });

    testWidgets('NmtkSparklineChart renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkSparklineChart(
              values: [0.1, 0.5, 0.2, 0.8],
              color: Colors.blue,
              label: 'Test Sparkline',
            ),
          ),
        ),
      );
      expect(find.text('Test Sparkline'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('NmtkPipelineStepper renders correctly', (
      WidgetTester tester,
    ) async {
      final steps = [
        const NmtkPipelineStepData(
          label: 'Step 1',
          status: NmtkStepStatus.success,
          detail: 'Done',
        ),
        const NmtkPipelineStepData(
          label: 'Step 2',
          status: NmtkStepStatus.running,
          detail: 'In progress',
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NmtkPipelineStepper(steps: steps)),
        ),
      );

      expect(find.text('Step 1'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Step 2'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('NmtkOutlinedButton renders correctly', (
      WidgetTester tester,
    ) async {
      bool pressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NmtkOutlinedButton(
              label: 'Outline',
              onPressed: () {
                pressed = true;
              },
              icon: Icons.close,
            ),
          ),
        ),
      );

      expect(find.text('Outline'), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.tap(find.byType(OutlinedButton));
      expect(pressed, isTrue);
    });
  });
}
