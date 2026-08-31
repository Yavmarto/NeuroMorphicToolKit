import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/workflow/snn_workflow_stepper.dart';

Widget _wrap(Widget child, {bool disableAnimations = false}) => ZetaProvider(
  initialContrast: ZetaContrast.aa,
  initialThemeMode: ThemeMode.dark,
  builder: (context, light, dark, mode) => MaterialApp(
    theme: light,
    darkTheme: dark,
    themeMode: mode,
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  ),
);

void main() {
  group('SnnWorkflowStepper', () {
    testWidgets('shows three stages and only active stage children', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SnnWorkflowStepper(currentPhase: SnnWorkflowPhase.defineTrain),
        ),
      );

      expect(find.text('Setup'), findsOneWidget);
      expect(find.text('Design'), findsOneWidget);
      expect(find.text('Execute'), findsOneWidget);
      expect(find.text('Model').hitTestable(), findsOneWidget);
      expect(find.text('Training').hitTestable(), findsOneWidget);
      expect(find.text('Evaluation').hitTestable(), findsOneWidget);
      expect(find.text('Data & Targets').hitTestable(), findsNothing);
      expect(find.text('Run').hitTestable(), findsNothing);
    });

    testWidgets('uses text-only stage pills and equal-size phase pills', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SnnWorkflowStepper(currentPhase: SnnWorkflowPhase.defineTrain),
        ),
      );

      // Setup is not the active stage here, so its pill stays collapsed to
      // plain text — no icons at all.
      final collapsedStage = find.byKey(const ValueKey('workflow-stage-1'));
      final model = find.byKey(const ValueKey('pipeline-step-defineModel'));
      final training = find.byKey(const ValueKey('pipeline-step-defineTrain'));
      final evaluation = find.byKey(const ValueKey('pipeline-step-defineEval'));

      expect(tester.getSize(model).width, tester.getSize(training).width);
      expect(tester.getSize(training).width, tester.getSize(evaluation).width);
      expect(
        find.descendant(of: collapsedStage, matching: find.byType(Icon)),
        findsNothing,
      );
      expect(
        find.descendant(of: training, matching: find.byType(Icon)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: training,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );
    });

    testWidgets('stage tap reopens its last visited unlocked child', (
      tester,
    ) async {
      final phase = ValueNotifier<SnnWorkflowPhase>(
        SnnWorkflowPhase.defineTrain,
      );
      SnnWorkflowPhase? selected;
      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder<SnnWorkflowPhase>(
            valueListenable: phase,
            builder: (context, value, child) => SnnWorkflowStepper(
              currentPhase: value,
              onPhaseSelected: (next) => selected = next,
            ),
          ),
        ),
      );
      phase.value = SnnWorkflowPhase.run;
      await tester.pumpAndSettle();

      await tester.tap(find.text('Design'));
      expect(selected, SnnWorkflowPhase.defineTrain);
    });

    testWidgets('fully locked stage cannot be selected', (tester) async {
      SnnWorkflowPhase? selected;
      await tester.pumpWidget(
        _wrap(
          SnnWorkflowStepper(
            currentPhase: SnnWorkflowPhase.selectData,
            lockedPhases: const {
              SnnWorkflowPhase.run,
              SnnWorkflowPhase.deployHardware,
              SnnWorkflowPhase.deployReview,
            },
            onPhaseSelected: (next) => selected = next,
          ),
        ),
      );

      await tester.tap(find.text('Execute'));
      expect(selected, isNull);
    });

    testWidgets('split controls preserve adjacent same-stage pair', (
      tester,
    ) async {
      (String, String)? split;
      await tester.pumpWidget(
        _wrap(
          SnnWorkflowStepper(
            currentPhase: SnnWorkflowPhase.defineTrain,
            onSplitBetween: (left, right) => split = (left, right),
          ),
        ),
      );

      await tester.tap(find.byTooltip('Open split view').first);
      expect(split, ('defineModel', 'defineTrain'));
    });

    testWidgets('cross-stage secondary phase is ignored', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SnnWorkflowStepper(
            currentPhase: SnnWorkflowPhase.defineModel,
            secondaryPhase: SnnWorkflowPhase.selectData,
            splitStep: 'selectData',
          ),
        ),
      );

      expect(find.text('Data & Targets').hitTestable(), findsNothing);
      expect(find.text('Training').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Close left pane'), findsNothing);
      expect(find.byTooltip('Close right pane'), findsNothing);
    });

    testWidgets('cross-stage split controls are not exposed', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SnnWorkflowStepper(
            currentPhase: SnnWorkflowPhase.defineEval,
            secondaryPhase: SnnWorkflowPhase.run,
            splitStep: 'run',
            onSplitBetween: (_, _) {},
            onCollapseStep: (_) {},
          ),
        ),
      );

      expect(find.byTooltip('Open Run beside Evaluation'), findsNothing);
      expect(find.byTooltip('Close right pane'), findsNothing);
      expect(find.byTooltip('Open split view'), findsOneWidget);
    });

    testWidgets('stage rail exposes selected semantics', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          const SnnWorkflowStepper(currentPhase: SnnWorkflowPhase.defineModel),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics &&
              widget.properties.label == 'Stage 2, Design',
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets(
      'stage switch nests the new stage sub-steps inline and drops the old ones',
      (tester) async {
        final phase = ValueNotifier<SnnWorkflowPhase>(
          SnnWorkflowPhase.defineTrain,
        );
        await tester.pumpWidget(
          _wrap(
            ValueListenableBuilder<SnnWorkflowPhase>(
              valueListenable: phase,
              builder: (context, value, child) => SizedBox(
                width: 800,
                child: SnnWorkflowStepper(currentPhase: value),
              ),
            ),
          ),
        );

        expect(find.text('Training').hitTestable(), findsOneWidget);
        expect(find.text('Run').hitTestable(), findsNothing);

        phase.value = SnnWorkflowPhase.run;
        await tester.pumpAndSettle();

        expect(find.text('Training').hitTestable(), findsNothing);
        expect(find.text('Run').hitTestable(), findsOneWidget);
        expect(find.text('Deploy').hitTestable(), findsOneWidget);
        expect(find.text('Review').hitTestable(), findsOneWidget);
      },
    );

    testWidgets('panel size is consistent across phase changes', (
      tester,
    ) async {
      final phase = ValueNotifier<SnnWorkflowPhase>(
        SnnWorkflowPhase.selectData,
      );
      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder<SnnWorkflowPhase>(
            valueListenable: phase,
            builder: (context, value, child) =>
                SnnWorkflowStepper(currentPhase: value),
          ),
        ),
      );

      final panel = find.byKey(const ValueKey('snn-workflow-panel'));
      final initialWidth = tester.getSize(panel).width;
      final initialHeight = tester.getSize(panel).height;

      phase.value = SnnWorkflowPhase.defineTrain;
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, initialWidth);
      expect(tester.getSize(panel).height, initialHeight);

      phase.value = SnnWorkflowPhase.run;
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, initialWidth);
      expect(tester.getSize(panel).height, initialHeight);
    });

    testWidgets(
      'active stage substeps nest inside its own pill, left-aligned',
      (tester) async {
        final phase = ValueNotifier<SnnWorkflowPhase>(
          SnnWorkflowPhase.defineModel,
        );
        addTearDown(phase.dispose);
        await tester.pumpWidget(
          _wrap(
            ValueListenableBuilder<SnnWorkflowPhase>(
              valueListenable: phase,
              builder: (context, value, child) =>
                  SnnWorkflowStepper(currentPhase: value),
            ),
          ),
        );

        // The substep chip sits just right of the stage's own label, inside
        // the same pill — not centred, not off in a separate row.
        final stageLeft = tester
            .getTopLeft(find.byKey(const ValueKey('workflow-stage-2')))
            .dx;
        final substepLeft = tester
            .getTopLeft(find.byKey(const ValueKey('pipeline-step-defineModel')))
            .dx;
        expect(substepLeft, greaterThan(stageLeft + 100));
        expect(substepLeft, lessThan(stageLeft + 140));

        // A single-substep stage must stay left-aligned within its reserved
        // width, not drift to the centre.
        phase.value = SnnWorkflowPhase.selectData;
        await tester.pumpAndSettle();
        final setupStageLeft = tester
            .getTopLeft(find.byKey(const ValueKey('workflow-stage-1')))
            .dx;
        final prepareLeft = tester
            .getTopLeft(find.byKey(const ValueKey('pipeline-step-selectData')))
            .dx;
        expect(prepareLeft, greaterThan(setupStageLeft + 100));
        expect(prepareLeft, lessThan(setupStageLeft + 140));
      },
    );

    testWidgets(
      'active stage phases stay horizontally scrollable in narrow space',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const SizedBox(
              width: 500,
              child: SnnWorkflowStepper(
                currentPhase: SnnWorkflowPhase.defineTrain,
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        // defineTrain's stage is Design (stage 2); its nested phase rail is
        // the horizontally-scrollable region under test here. The stage row
        // itself also scrolls horizontally, so this must be scoped to the
        // active stage's pill rather than matching the whole tree.
        final activeStage = find.byKey(const ValueKey('workflow-stage-2'));
        expect(
          find.descendant(
            of: activeStage,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is SingleChildScrollView &&
                  widget.scrollDirection == Axis.horizontal,
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('shrinking between stages clips the outgoing child row', (
      tester,
    ) async {
      final phase = ValueNotifier<SnnWorkflowPhase>(
        SnnWorkflowPhase.defineTrain,
      );
      final width = ValueNotifier<double>(640);
      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (context, value, child) => ValueListenableBuilder(
              valueListenable: phase,
              builder: (context, currentPhase, child) => SizedBox(
                width: value,
                child: SnnWorkflowStepper(currentPhase: currentPhase),
              ),
            ),
          ),
        ),
      );

      phase.value = SnnWorkflowPhase.selectData;
      width.value = 400;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('running and completion states are announced', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _wrap(
          const SnnWorkflowStepper(
            currentPhase: SnnWorkflowPhase.run,
            runningPhase: SnnWorkflowPhase.run,
          ),
        ),
      );

      final setup = tester.getSemantics(
        find.bySemanticsLabel('Stage 1, Setup'),
      );
      final execute = tester.getSemantics(
        find.bySemanticsLabel('Stage 3, Execute'),
      );
      expect(setup.value, 'Completed');
      expect(execute.value, 'Running');
      handle.dispose();
    });

    testWidgets('stage pills activate from the keyboard', (tester) async {
      SnnWorkflowPhase? selected;
      await tester.pumpWidget(
        _wrap(
          SnnWorkflowStepper(
            currentPhase: SnnWorkflowPhase.defineModel,
            onPhaseSelected: (phase) => selected = phase,
          ),
        ),
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);

      expect(selected, SnnWorkflowPhase.run);
    });

    testWidgets('reduced motion swaps substep rails instantly', (tester) async {
      final phase = ValueNotifier<SnnWorkflowPhase>(
        SnnWorkflowPhase.defineModel,
      );
      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder<SnnWorkflowPhase>(
            valueListenable: phase,
            builder: (context, value, child) =>
                SnnWorkflowStepper(currentPhase: value),
          ),
          disableAnimations: true,
        ),
      );

      expect(find.text('Model').hitTestable(), findsOneWidget);

      phase.value = SnnWorkflowPhase.run;
      await tester.pump();

      expect(find.text('Model').hitTestable(), findsNothing);
      expect(find.text('Run').hitTestable(), findsOneWidget);
    });
  });
}
