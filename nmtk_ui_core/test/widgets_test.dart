import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('NMTK UI Core Widgets Smoke Tests', () {
    testWidgets('NmtkPrimaryButton renders correctly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NmtkPrimaryButton(label: 'Test Button', onPressed: () {}),
          ),
        );

        expect(find.text('Action'), findsOneWidget);
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

        expect(find.text('Cancel'), findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);
        await tester.tap(find.byType(OutlinedButton));
        expect(pressed, isTrue);
      });
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

        expect(find.text('Total Energy'), findsOneWidget);
        expect(find.text('40.00 pJ'), findsOneWidget);
        expect(find.text('500'), findsOneWidget);
        expect(find.text('Layer1'), findsOneWidget);
        expect(find.text('15.00 pJ'), findsOneWidget);
        expect(find.text('Layer2'), findsOneWidget);
        expect(find.text('25.00 pJ'), findsOneWidget);
        expect(find.byType(LinearProgressIndicator), findsNWidgets(2));
      });
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
        );
        expect(find.text('No quantization data'), findsOneWidget);
      });

      testWidgets('renders table with accuracy indicators', (tester) async {
        const report = QuantizationReport(
          bitWidths: [8, 4, 2],
          accuracyDrops: [0.01, 0.04, 0.08], // Green, Orange, Red
          sparsity: [0.3, 0.6, 0.9],
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: NmtkQuantizationTable(report: report)),
            ),
          ),
        );

        expect(find.text('8-bit'), findsOneWidget);
        expect(find.text('4-bit'), findsOneWidget);
        expect(find.text('2-bit'), findsOneWidget);
        expect(find.text('1.00%'), findsOneWidget);
        expect(find.text('4.00%'), findsOneWidget);
        expect(find.text('8.00%'), findsOneWidget);
        expect(find.text('30.0%'), findsOneWidget);
        expect(find.text('60.0%'), findsOneWidget);
        expect(find.text('90.0%'), findsOneWidget);

        // Check for indicators (represented by circular Containers in _AccuracyDropIndicator)
        final indicators = tester.widgetList<Container>(
          find.descendant(
            of: find.byType(DataTable),
            matching: find.byType(Container),
          ),
        ).where((c) {
          final decoration = c.decoration as BoxDecoration?;
          return decoration?.shape == BoxShape.circle;
        });
        expect(indicators.length, 3);
      });
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

    group('Buttons', () {
      testWidgets('NmtkOutlinedButton renders correctly', (
        WidgetTester tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NmtkPipelineStepper(steps: steps),
            ),
          ),
        );

        expect(find.text('Start'), findsOneWidget);
        expect(find.text('Complete'), findsOneWidget);
        expect(find.byIcon(Icons.check_circle), findsOneWidget);

        expect(find.text('Processing'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        expect(find.text('Optional'), findsOneWidget);
        await tester.tap(find.text('Optional'));
        expect(tapped, isTrue);

        expect(find.text('End'), findsOneWidget);
        expect(find.text('Failed'), findsOneWidget);
        expect(find.byIcon(Icons.error), findsOneWidget);

        // Check for connectors (3 for 4 steps)
        expect(find.byIcon(Icons.arrow_forward_ios), findsNWidgets(3));
      });
    });
  });
}
