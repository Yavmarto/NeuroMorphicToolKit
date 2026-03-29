import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('NmtkPipelineStepper', () {
    testWidgets('renders all steps with labels and details', (WidgetTester tester) async {
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
        const NmtkPipelineStepData(
          label: 'Step 3',
          status: NmtkStepStatus.error,
          detail: 'Failed',
        ),
        const NmtkPipelineStepData(
          label: 'Step 4',
          status: NmtkStepStatus.idle,
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
      expect(find.text('Step 3'), findsOneWidget);
      expect(find.text('Failed'), findsOneWidget);
      expect(find.text('Step 4'), findsOneWidget);
    });

    testWidgets('renders correct icons for each status', (WidgetTester tester) async {
      final steps = [
        const NmtkPipelineStepData(
          label: 'S1',
          status: NmtkStepStatus.success,
        ),
        const NmtkPipelineStepData(
          label: 'S2',
          status: NmtkStepStatus.running,
        ),
        const NmtkPipelineStepData(
          label: 'S3',
          status: NmtkStepStatus.error,
        ),
        const NmtkPipelineStepData(
          label: 'S4',
          status: NmtkStepStatus.idle,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NmtkPipelineStepper(steps: steps)),
        ),
      );

      // success -> check icon
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      // error -> error icon
      expect(find.byIcon(Icons.error), findsOneWidget);
      // idle -> circle_outlined
      expect(find.byIcon(Icons.circle_outlined), findsOneWidget);
      // running -> CircularProgressIndicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('handles empty steps gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NmtkPipelineStepper(steps: [])),
        ),
      );

      // Verify no exceptions
      expect(find.byType(Row), findsOneWidget);
    });
  });
}
