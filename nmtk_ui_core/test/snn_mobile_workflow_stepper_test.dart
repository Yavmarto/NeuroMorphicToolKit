import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

Widget _wrap(Widget child) => ZetaProvider(
  initialContrast: ZetaContrast.aa,
  initialThemeMode: ThemeMode.dark,
  builder: (context, light, dark, mode) => MaterialApp(
    theme: light,
    darkTheme: dark,
    themeMode: mode,
    home: Scaffold(body: child),
  ),
);

void main() {
  group('SnnMobileWorkflowStepper', () {
    testWidgets('shows current step title', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SnnMobileWorkflowStepper(
            currentPhase: SnnWorkflowPhase.defineModel,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Design · Model'), findsOneWidget);
    });

    testWidgets('labels the final phase Review', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SnnMobileWorkflowStepper(
            currentPhase: SnnWorkflowPhase.deployReview,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Execute · Review'), findsOneWidget);
    });

    testWidgets('locked chip has 0.3 opacity', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const SnnMobileWorkflowStepper(
            currentPhase: SnnWorkflowPhase.selectData,
            lockedPhases: {
              SnnWorkflowPhase.run,
              SnnWorkflowPhase.deployHardware,
              SnnWorkflowPhase.deployReview,
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final opacityWidgets = tester.widgetList<Opacity>(find.byType(Opacity));
      expect(
        opacityWidgets.any((o) => o.opacity == 0.3),
        isTrue,
        reason: 'A fully locked stage chip should render at 0.3 opacity',
      );
    });

    testWidgets('tapping completed step calls onPhaseSelected', (tester) async {
      SnnWorkflowPhase? selected;
      await tester.pumpWidget(
        _wrap(
          SnnMobileWorkflowStepper(
            currentPhase: SnnWorkflowPhase.defineModel,
            onPhaseSelected: (p) => selected = p,
          ),
        ),
      );
      await tester.pumpAndSettle();
      // selectData (index 0) is completed when current is defineModel (index 1)
      await tester.tap(find.text('1'));
      await tester.pumpAndSettle();
      expect(selected, SnnWorkflowPhase.selectData);
    });

    testWidgets('title updates when currentPhase changes', (tester) async {
      SnnWorkflowPhase phase = SnnWorkflowPhase.selectData;
      final notifier = ValueNotifier(phase);
      await tester.pumpWidget(
        _wrap(
          ValueListenableBuilder<SnnWorkflowPhase>(
            valueListenable: notifier,
            builder: (_, p, _) => SnnMobileWorkflowStepper(currentPhase: p),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Setup · Prepare'), findsOneWidget);

      notifier.value = SnnWorkflowPhase.defineModel;
      await tester.pumpAndSettle();
      expect(find.text('Design · Model'), findsOneWidget);
    });
  });
}
