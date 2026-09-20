import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/models/scaffold_models.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:zeta_flutter/zeta_flutter.dart';

void main() {
  testWidgets('NmtkMobileScaffold never wires a shell drawer or hamburger', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: NmtkMobileScaffold(
          mode: NmtkShellMode.command,
          navItems: const [
            NmtkSidebarItem(
              id: 'neurocnl',
              label: 'Neuro Studio',
              icon: Icons.science_outlined,
            ),
            NmtkSidebarItem(
              id: 'neurobench',
              label: 'Neurobench',
              icon: Icons.speed_outlined,
            ),
          ],
          selectedIndex: 0,
          pageTitle: 'NeuroToolkit',
          child: const Text('Module body'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(ZetaIcons.hamburger_menu_round), findsNothing);
    expect(find.byTooltip('Open navigation'), findsNothing);
    expect(find.byType(Drawer), findsNothing);
    expect(find.text('NMTK'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'NmtkMobileScaffold with showBottomNavigation false still omits drawer',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          home: NmtkMobileScaffold(
            mode: NmtkShellMode.command,
            navItems: [
              NmtkSidebarItem(
                id: 'neurocnl',
                label: 'Studio',
                icon: Icons.science_outlined,
              ),
            ],
            selectedIndex: 0,
            showBottomNavigation: false,
            child: Text('Single surface'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(ZetaIcons.hamburger_menu_round), findsNothing);
      expect(find.byType(Drawer), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
