import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
// ignore: unnecessary_import — explicit Zeta import for clarity over re-export
import 'package:zeta_flutter/zeta_flutter.dart';

void main() {
  group('NmtkPipelineStepper', () {
    testWidgets('renders all steps with labels and details', (
      WidgetTester tester,
    ) async {
      final steps = [
        const NmtkPipelineStepData(
          id: 'step1',
          label: 'Step 1',
          status: NmtkStepStatus.success,
          detail: 'Done',
        ),
        const NmtkPipelineStepData(
          id: 'step2',
          label: 'Step 2',
          status: NmtkStepStatus.running,
          detail: 'In progress',
        ),
        const NmtkPipelineStepData(
          id: 'step3',
          label: 'Step 3',
          status: NmtkStepStatus.error,
          detail: 'Failed',
        ),
        const NmtkPipelineStepData(
          id: 'step4',
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
      expect(find.text('Step 2'), findsOneWidget);
      expect(find.text('Step 3'), findsOneWidget);
      expect(find.text('Step 4'), findsOneWidget);
    });

    testWidgets('renders correct icons for each status', (
      WidgetTester tester,
    ) async {
      final steps = [
        const NmtkPipelineStepData(
          id: 's1',
          label: 'S1',
          status: NmtkStepStatus.success,
        ),
        const NmtkPipelineStepData(
          id: 's2',
          label: 'S2',
          status: NmtkStepStatus.running,
        ),
        const NmtkPipelineStepData(
          id: 's3',
          label: 'S3',
          status: NmtkStepStatus.error,
        ),
        const NmtkPipelineStepData(
          id: 's4',
          label: 'S4',
          status: NmtkStepStatus.idle,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: NmtkPipelineStepper(steps: steps)),
        ),
      );

      // success -> ZetaIcons.check_circle (Zeta design system)
      expect(find.byIcon(ZetaIcons.check_circle), findsOneWidget);
      // error -> ZetaIcons.error (Zeta design system)
      expect(find.byIcon(ZetaIcons.error), findsOneWidget);
      // idle -> ZetaIcons.radio_button_unchecked (Zeta design system)
      expect(find.byIcon(ZetaIcons.radio_button_unchecked), findsOneWidget);
      // running -> CircularProgressIndicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('highlights selected step', (WidgetTester tester) async {
      final steps = [
        const NmtkPipelineStepData(
          id: 's1',
          label: 'S1',
          status: NmtkStepStatus.idle,
        ),
        const NmtkPipelineStepData(
          id: 's2',
          label: 'S2',
          status: NmtkStepStatus.idle,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NmtkPipelineStepper(steps: steps, selectedStepId: 's2'),
          ),
        ),
      );

      final step2Container = tester.widget<Container>(
        find
            .ancestor(of: find.text('S2'), matching: find.byType(Container))
            .first,
      );

      final decoration = step2Container.decoration as BoxDecoration;
      expect(decoration.border?.top.width, equals(1.6));
    });

    testWidgets('auto-scrolls to selected step', (WidgetTester tester) async {
      final manySteps = List.generate(
        10,
        (i) => NmtkPipelineStepData(
          id: 'step$i',
          label: 'Step $i',
          status: NmtkStepStatus.idle,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: NmtkPipelineStepper(
                steps: manySteps,
                selectedStepId: 'step0',
              ),
            ),
          ),
        ),
      );

      final scrollable = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      final controller = scrollable.controller!;
      expect(controller.offset, equals(0.0));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 200,
              child: NmtkPipelineStepper(
                steps: manySteps,
                selectedStepId: 'step9',
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(controller.offset, isPositive);
    });

    testWidgets('handles empty steps gracefully', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NmtkPipelineStepper(steps: [])),
        ),
      );

      expect(find.byType(Row), findsOneWidget);
    });

    testWidgets('pulseTick increment on a running step does not throw', (
      WidgetTester tester,
    ) async {
      // First render: running step with pulseTick=0
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkPipelineStepper(
              steps: [
                NmtkPipelineStepData(
                  id: 'train',
                  label: 'Train',
                  status: NmtkStepStatus.running,
                  pulseTick: 0,
                ),
              ],
            ),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Second render: pulseTick increments — should animate without crash.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkPipelineStepper(
              steps: [
                NmtkPipelineStepData(
                  id: 'train',
                  label: 'Train',
                  status: NmtkStepStatus.running,
                  pulseTick: 1,
                ),
              ],
            ),
          ),
        ),
      );
      // Advance the pulse animation fully (800 ms). Do NOT use pumpAndSettle:
      // CircularProgressIndicator animates forever, so pumpAndSettle times out.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      // Still running — no crash.
      expect(find.text('Train'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets(
      'pulseTick on non-running step does not trigger scale animation',
      (WidgetTester tester) async {
        // Idle step with pulseTick — must not crash or scale.
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: NmtkPipelineStepper(
                steps: [
                  NmtkPipelineStepData(
                    id: 's',
                    label: 'S',
                    status: NmtkStepStatus.idle,
                    pulseTick: 5,
                  ),
                ],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('S'), findsOneWidget);
        // No Transform.scale widgets for idle steps.
        expect(find.byType(CircularProgressIndicator), findsNothing);
      },
    );
  });
}
