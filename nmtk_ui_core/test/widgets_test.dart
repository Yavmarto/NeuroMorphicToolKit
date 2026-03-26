import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('NMTK UI Core Widgets Detailed Tests', () {
    group('Buttons', () {
      testWidgets('NmtkPrimaryButton triggers callback and shows icon', (tester) async {
        bool pressed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NmtkPrimaryButton(
                label: 'Action',
                icon: Icons.add,
                onPressed: () => pressed = true,
              ),
            ),
          ),
        );

        expect(find.text('Action'), findsOneWidget);
        expect(find.byIcon(Icons.add), findsOneWidget);
        await tester.tap(find.byType(ElevatedButton));
        expect(pressed, isTrue);
      });

      testWidgets('NmtkOutlinedButton triggers callback and shows icon', (tester) async {
        bool pressed = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: NmtkOutlinedButton(
                label: 'Cancel',
                icon: Icons.close,
                onPressed: () => pressed = true,
              ),
            ),
          ),
        );

        expect(find.text('Cancel'), findsOneWidget);
        expect(find.byIcon(Icons.close), findsOneWidget);
        await tester.tap(find.byType(OutlinedButton));
        expect(pressed, isTrue);
      });
    });

    group('NmtkEnergyBarChart', () {
      testWidgets('shows empty state', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: NmtkEnergyBarChart(
                report: EnergyReport(perEnsemblePj: {}, totalPj: 0, opsCount: 0),
              ),
            ),
          ),
        );
        expect(find.text('No ensemble data'), findsOneWidget);
      });

      testWidgets('shows summary chips and energy bars', (tester) async {
        const report = EnergyReport(
          perEnsemblePj: {'Layer1': 15.0, 'Layer2': 25.0},
          totalPj: 40.0,
          opsCount: 500,
        );

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                height: 500, // Ensure enough space for ListView
                child: NmtkEnergyBarChart(report: report),
              ),
            ),
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

    group('NmtkQuantizationTable', () {
      testWidgets('shows empty state', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: NmtkQuantizationTable(
                report: QuantizationReport(bitWidths: [], accuracyDrops: [], sparsity: []),
              ),
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

    group('NmtkSparklineChart', () {
      testWidgets('shows empty state', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: NmtkSparklineChart(values: [], color: Colors.blue),
            ),
          ),
        );
        expect(find.text('No data'), findsOneWidget);
      });

      testWidgets('renders label and custom paint', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: NmtkSparklineChart(
                values: [0, 1, 0, 1],
                color: Colors.red,
                label: 'Activity',
              ),
            ),
          ),
        );
        expect(find.text('Activity'), findsOneWidget);
        expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      });
    });

    group('NmtkPipelineStepper', () {
      testWidgets('renders all statuses and triggers onTap', (tester) async {
        bool tapped = false;
        final steps = [
          const NmtkPipelineStepData(
            label: 'Start',
            status: NmtkStepStatus.success,
            detail: 'Complete',
          ),
          const NmtkPipelineStepData(
            label: 'Processing',
            status: NmtkStepStatus.running,
            detail: '50%',
          ),
          NmtkPipelineStepData(
            label: 'Optional',
            status: NmtkStepStatus.idle,
            onTap: () => tapped = true,
          ),
          const NmtkPipelineStepData(
            label: 'End',
            status: NmtkStepStatus.error,
            detail: 'Failed',
          ),
        ];

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
