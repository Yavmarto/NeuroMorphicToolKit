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

    testWidgets('renders Mobile layout (< 840px) with NavigationBar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(500, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildScaffold(const Size(500, 800)));

      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NmtkNavigationRail), findsNothing);
      expect(find.byType(NmtkTopAppBar), findsNothing);
      expect(find.text('Main Content'), findsOneWidget);
    });

    testWidgets('renders Tablet layout (>= 840px) with top navigation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildScaffold(const Size(900, 800)));

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NmtkNavigationRail), findsNothing);
      expect(find.byType(NmtkTopAppBar), findsOneWidget);
      expect(
        find.byKey(const ValueKey('responsive-topnav-brand')),
        findsOneWidget,
      );
      expect(find.text('Main Content'), findsOneWidget);
    });

    testWidgets('renders Desktop layout (>= 1240px) with top navigation', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1300, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildScaffold(const Size(1300, 800)));

      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(NmtkNavigationRail), findsNothing);
      expect(find.byType(NmtkTopAppBar), findsOneWidget);
      expect(find.text('NMTK Hub'), findsOneWidget);
      expect(find.text('Main Content'), findsOneWidget);

      expect(find.text('Dashboard'), findsWidgets);
      expect(find.text('Settings'), findsWidgets);
      expect(
        find.byKey(const ValueKey('responsive-desktop-sidebar')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('responsive-sidebar-toggle')),
        findsNothing,
      );
    });
  });
}
