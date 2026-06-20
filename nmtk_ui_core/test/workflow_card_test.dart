import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
// ignore: unnecessary_import — explicit Zeta import for clarity over re-export
import 'package:zeta_flutter/zeta_flutter.dart';

Widget buildHarness(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  group('NmtkWorkflowCard', () {
    const stages = [
      NmtkWorkflowStage(
        title: 'Prepare Inputs',
        detail: 'Validate the selected workspace configuration.',
        state: NmtkWorkflowStageState.upcoming,
      ),
      NmtkWorkflowStage(
        title: 'Build Artifact',
        detail: 'Compile the current graph into deployable outputs.',
        state: NmtkWorkflowStageState.active,
      ),
      NmtkWorkflowStage(
        title: 'Publish Output',
        detail: 'Write the resulting bundle into the staging directory.',
        state: NmtkWorkflowStageState.done,
      ),
      NmtkWorkflowStage(
        title: 'Verify Result',
        detail: 'Surface validation issues before release.',
        state: NmtkWorkflowStageState.error,
      ),
    ];

    testWidgets('renders default title subtitle and one tile per stage', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildHarness(const NmtkWorkflowCard(stages: stages)),
      );

      expect(find.text('Workflow'), findsOneWidget);
      expect(
        find.text('Each stage stays visible so the next action is obvious.'),
        findsOneWidget,
      );
      expect(find.text('Prepare Inputs'), findsOneWidget);
      expect(find.text('Build Artifact'), findsOneWidget);
      expect(find.text('Publish Output'), findsOneWidget);
      expect(find.text('Verify Result'), findsOneWidget);
      expect(find.byType(Icon), findsNWidgets(4));
    });

    testWidgets('maps each workflow state to the expected icon family', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildHarness(
          const NmtkWorkflowCard(
            title: 'Deployment Workflow',
            subtitle: 'Follow the highlighted stage to continue.',
            stages: stages,
          ),
        ),
      );

      expect(find.text('Deployment Workflow'), findsOneWidget);
      expect(
        find.text('Follow the highlighted stage to continue.'),
        findsOneWidget,
      );
      expect(
        find.text('Validate the selected workspace configuration.'),
        findsOneWidget,
      );
      expect(
        find.text('Compile the current graph into deployable outputs.'),
        findsOneWidget,
      );
      expect(
        find.text('Write the resulting bundle into the staging directory.'),
        findsOneWidget,
      );
      expect(
        find.text('Surface validation issues before release.'),
        findsOneWidget,
      );
      // workflow_card uses ZetaIcons (Zeta design system migration)
      expect(find.byIcon(ZetaIcons.radio_button_unchecked), findsOneWidget);
      expect(find.byIcon(ZetaIcons.play_circle), findsOneWidget);
      expect(find.byIcon(ZetaIcons.check_circle), findsOneWidget);
      expect(find.byIcon(ZetaIcons.error), findsOneWidget);
    });
  });
}
