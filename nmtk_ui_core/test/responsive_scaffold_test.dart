import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('ResponsiveScaffold', () {
    const destinations = [
      NavigationDestinationData(icon: Icons.dashboard, label: 'Dashboard'),
      NavigationDestinationData(icon: Icons.settings, label: 'Settings'),
    ];

    Widget buildScaffold(Size size) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Scaffold(
            body: ResponsiveScaffold(
              currentIndex: 0,
              onNavigationTargetSelected: (_) {},
              destinations: destinations,
              body: const Text('Main Content'),
            ),
          ),
        ),
      );
    }

    testWidgets('renders Mobile layout (< 600px) with NavigationBar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildScaffold(const Size(500, 800)));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NmtkNavigationRail), findsNothing);
      expect(find.text('Main Content'), findsOneWidget);
    });

    testWidgets(
      'renders Tablet layout (600px <= w < 1240px) with NmtkNavigationRail',
      (tester) async {
        tester.view.physicalSize = const Size(800, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);

        await tester.pumpWidget(buildScaffold(const Size(800, 800)));

        expect(find.byType(NavigationBar), findsNothing);
        expect(find.byType(NmtkNavigationRail), findsOneWidget);
        expect(find.text('Main Content'), findsOneWidget);
      },
    );

    testWidgets('renders Desktop layout (>= 1240px) with Custom Drawer', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1300, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildScaffold(const Size(1300, 800)));

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NmtkNavigationRail), findsNothing);
      expect(find.text('NMTK Hub'), findsOneWidget); // Header in custom drawer
      expect(find.text('Main Content'), findsOneWidget);

      // Verify list items in custom drawer
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('desktop sidebar can collapse and expand', (tester) async {
      tester.view.physicalSize = const Size(1300, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildScaffold(const Size(1300, 800)));

      final sidebarFinder = find.byKey(
        const ValueKey('responsive-desktop-sidebar'),
      );

      expect(find.byTooltip('Collapse sidebar'), findsOneWidget);
      expect(find.text('NMTK Hub'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(tester.getSize(sidebarFinder).width, 256);

      await tester.tap(find.byKey(const ValueKey('responsive-sidebar-toggle')));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Expand sidebar'), findsOneWidget);
      expect(find.text('NMTK Hub'), findsNothing);
      expect(find.text('Dashboard'), findsNothing);
      expect(tester.getSize(sidebarFinder).width, 88);

      await tester.tap(find.byKey(const ValueKey('responsive-sidebar-toggle')));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Collapse sidebar'), findsOneWidget);
      expect(find.text('NMTK Hub'), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(tester.getSize(sidebarFinder).width, 256);
    });
  });
}
