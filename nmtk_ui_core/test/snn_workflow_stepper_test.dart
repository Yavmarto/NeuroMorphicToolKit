import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

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

      expect(find.text('1. Setup'), findsOneWidget);
      expect(find.text('2. Design'), findsOneWidget);
      expect(find.text('3. Execute'), findsOneWidget);
      expect(find.text('Model').hitTestable(), findsOneWidget);
      expect(find.text('Training').hitTestable(), findsOneWidget);
      expect(find.text('Evaluation').hitTestable(), findsOneWidget);
      expect(find.text('Data & Targets').hitTestable(), findsNothing);
      expect(find.text('Run').hitTestable(), findsNothing);
    });

    testWidgets('uses text-only, equal-size destination pills', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SnnWorkflowStepper(currentPhase: SnnWorkflowPhase.defineTrain),
        ),
      );

      final stage = find.byKey(const ValueKey('workflow-stage-2'));
      final model = find.byKey(const ValueKey('pipeline-step-defineModel'));
      final training = find.byKey(const ValueKey('pipeline-step-defineTrain'));
      final evaluation = find.byKey(const ValueKey('pipeline-step-defineEval'));

      expect(tester.getSize(model).height, tester.getSize(stage).height);
      expect(tester.getSize(model).width, tester.getSize(stage).width);
      expect(tester.getSize(model).width, tester.getSize(training).width);
      expect(tester.getSize(training).width, tester.getSize(evaluation).width);
      expect(
        find.descendant(of: stage, matching: find.byType(Icon)),
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

      final stageMaterial = tester.widget<Material>(stage);
      final trainingContainer = tester.widget<Container>(training);
      final trainingDecoration = trainingContainer.decoration! as BoxDecoration;
      expect(trainingDecoration.color, stageMaterial.color);
      expect(
        trainingDecoration.border!.top.color,
        (stageMaterial.shape! as RoundedRectangleBorder).side.color,
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

      await tester.tap(find.text('2. Design'));
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
              SnnWorkflowPhase.review,
              SnnWorkflowPhase.deployHardware,
            },
            onPhaseSelected: (next) => selected = next,
          ),
        ),
      );

      await tester.tap(find.text('3. Execute'));
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

    testWidgets('accordion uses 180 ms full-distance horizontal motion', (
      tester,
    ) async {
      final phase = ValueNotifier<SnnWorkflowPhase>(
        SnnWorkflowPhase.defineTrain,
      );
      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder<SnnWorkflowPhase>(
            valueListenable: phase,
            builder: (context, value, child) => SizedBox(
              width: 640,
              child: SnnWorkflowStepper(currentPhase: value),
            ),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TweenAnimationBuilder<double> &&
              widget.duration == const Duration(milliseconds: 180),
        ),
        findsNWidgets(3),
      );
      expect(find.byKey(const ValueKey('design-children')), findsOneWidget);

      phase.value = SnnWorkflowPhase.run;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      final outgoing = tester.widget<FractionalTranslation>(
        find
            .descendant(
              of: find.byKey(const ValueKey('design-children')),
              matching: find.byType(FractionalTranslation),
            )
            .first,
      );
      final incoming = tester.widget<FractionalTranslation>(
        find
            .descendant(
              of: find.byKey(const ValueKey('execute-children')),
              matching: find.byType(FractionalTranslation),
            )
            .first,
      );
      expect(outgoing.translation.dx, inExclusiveRange(-1, 0));
      expect(incoming.translation.dx, inExclusiveRange(-1, 0));

      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('execute-children')), findsOneWidget);
      expect(find.text('Deploy').hitTestable(), findsOneWidget);
    });

    testWidgets('panel keeps the widest natural stage width', (tester) async {
      final phase = ValueNotifier<SnnWorkflowPhase>(
        SnnWorkflowPhase.selectData,
      );
      await tester.pumpWidget(
        _wrap(
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1000),
              child: ValueListenableBuilder<SnnWorkflowPhase>(
                valueListenable: phase,
                builder: (context, value, child) =>
                    SnnWorkflowStepper(currentPhase: value),
              ),
            ),
          ),
        ),
      );

      final panel = find.byKey(const ValueKey('snn-workflow-panel'));
      final setupWidth = tester.getSize(panel).width;
      expect(setupWidth, lessThan(1000));

      phase.value = SnnWorkflowPhase.defineTrain;
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, setupWidth);

      phase.value = SnnWorkflowPhase.run;
      await tester.pumpAndSettle();
      expect(tester.getSize(panel).width, setupWidth);
    });

    testWidgets('child phases stay horizontally scrollable in narrow space', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SizedBox(
            width: 360,
            child: SnnWorkflowStepper(
              currentPhase: SnnWorkflowPhase.defineTrain,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SingleChildScrollView &&
              widget.scrollDirection == Axis.horizontal,
        ),
        findsNWidgets(3),
      );
    });

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
      width.value = 300;
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

    testWidgets('reduced motion removes accordion transition duration', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const SnnWorkflowStepper(currentPhase: SnnWorkflowPhase.defineModel),
          disableAnimations: true,
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TweenAnimationBuilder<double> &&
              widget.duration == Duration.zero,
        ),
        findsNWidgets(3),
      );
    });
  });
}
