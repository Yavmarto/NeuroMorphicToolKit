import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('NmtkWorkspaceShell', () {
    const layoutId = 'deploy-flow';
    const splitLayoutKey = Key('deploy-flow-split-layout');
    const stackedLayoutKey = Key('deploy-flow-stacked-layout');
    const leftPaneKey = Key('deploy-flow-left-pane');
    const rightPaneKey = Key('deploy-flow-right-pane');

    final steps = [
      const NmtkPipelineStepData(id: 'prepare', label: 'Prepare', status: NmtkStepStatus.success),
      const NmtkPipelineStepData(id: 'deploy', label: 'Deploy', status: NmtkStepStatus.running),
    ];

    Future<void> pumpShell(WidgetTester tester, {required Size size}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: size),
            child: Scaffold(
              body: SizedBox.expand(
                child: NmtkWorkspaceShell(
                  layoutId: layoutId,
                  steps: steps,
                  leftPane: const Text('Configuration Pane'),
                  rightPane: const Text('Status Pane'),
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('uses split layout above breakpoint with keyed panes', (
      tester,
    ) async {
      await pumpShell(tester, size: const Size(1280, 900));

      expect(find.byKey(splitLayoutKey), findsOneWidget);
      expect(find.byKey(stackedLayoutKey), findsNothing);
      expect(find.byKey(leftPaneKey), findsOneWidget);
      expect(find.byKey(rightPaneKey), findsOneWidget);
      expect(find.text('Prepare'), findsOneWidget);
      expect(find.text('Deploy'), findsOneWidget);
      expect(find.text('Configuration Pane'), findsOneWidget);
      expect(find.text('Status Pane'), findsOneWidget);
    });

    testWidgets('uses stacked layout below breakpoint and keeps pane keys', (
      tester,
    ) async {
      await pumpShell(tester, size: const Size(900, 900));

      expect(find.byKey(splitLayoutKey), findsNothing);
      expect(find.byKey(stackedLayoutKey), findsOneWidget);
      expect(find.byKey(leftPaneKey), findsOneWidget);
      expect(find.byKey(rightPaneKey), findsOneWidget);

      final leftTopLeft = tester.getTopLeft(find.byKey(leftPaneKey));
      final rightTopLeft = tester.getTopLeft(find.byKey(rightPaneKey));

      expect(leftTopLeft.dy, lessThan(rightTopLeft.dy));
    });
  });
}
