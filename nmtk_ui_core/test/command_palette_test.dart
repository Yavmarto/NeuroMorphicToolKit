import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

Widget _wrap(Widget child, {Size size = const Size(1000, 700)}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

List<NmtkCommand> _commands({VoidCallback? onOpen, VoidCallback? onRun}) {
  return [
    NmtkCommand(
      id: 'open',
      label: 'Open workspace',
      description: 'Open the selected module workspace',
      icon: Icons.open_in_new,
      category: 'Workspace',
      onExecute: onOpen ?? () {},
    ),
    NmtkCommand(
      id: 'run',
      label: 'Run preflight',
      description: 'Check launcher readiness',
      icon: Icons.play_arrow,
      category: 'Launcher',
      onExecute: onRun ?? () {},
    ),
  ];
}

void main() {
  group('NmtkCommandPalette', () {
    testWidgets('caps panel width on desktop viewports', (tester) async {
      await tester.pumpWidget(
        _wrap(NmtkCommandPalette(commands: _commands(), onDismiss: () {})),
      );
      await tester.pump();

      final panelSize = tester.getSize(
        find.byKey(const ValueKey<String>('nmtk-command-palette-panel')),
      );
      expect(panelSize.width, 600);
      expect(tester.takeException(), isNull);
    });

    testWidgets('insets panel on narrow viewports', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _wrap(
          NmtkCommandPalette(commands: _commands(), onDismiss: () {}),
          size: const Size(320, 640),
        ),
      );
      await tester.pump();

      final panelSize = tester.getSize(
        find.byKey(const ValueKey<String>('nmtk-command-palette-panel')),
      );
      expect(panelSize.width, 288);
      expect(find.text('Open workspace'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keyboard navigation works while search field has focus', (
      tester,
    ) async {
      var dismissCount = 0;
      var openCount = 0;
      var runCount = 0;

      await tester.pumpWidget(
        _wrap(
          NmtkCommandPalette(
            commands: _commands(
              onOpen: () => openCount++,
              onRun: () => runCount++,
            ),
            onDismiss: () => dismissCount++,
          ),
        ),
      );
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();

      expect(openCount, 0);
      expect(runCount, 1);
      expect(dismissCount, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(dismissCount, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('command rows expose button and selected semantics', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(NmtkCommandPalette(commands: _commands(), onDismiss: () {})),
      );
      await tester.pump();

      final openNode = tester.getSemantics(
        find.byKey(const ValueKey<String>('nmtk-command-open')),
      );
      final runNode = tester.getSemantics(
        find.byKey(const ValueKey<String>('nmtk-command-run')),
      );

      expect(openNode.label, contains('Open workspace'));
      expect(openNode.flagsCollection.isButton, isTrue);
      expect(openNode.flagsCollection.isSelected, ui.Tristate.isTrue);
      expect(runNode.flagsCollection.isButton, isTrue);
      expect(runNode.flagsCollection.isSelected, ui.Tristate.isFalse);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();

      final selectedRunNode = tester.getSemantics(
        find.byKey(const ValueKey<String>('nmtk-command-run')),
      );
      expect(selectedRunNode.flagsCollection.isSelected, ui.Tristate.isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
