import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

void main() {
  group('NmtkNavigationRail', () {
    const destinations = [
      NavigationDestinationData(
        icon: Icons.dashboard_outlined,
        selectedIcon: Icons.dashboard,
        label: 'Dashboard',
      ),
      NavigationDestinationData(
        icon: Icons.store_outlined,
        selectedIcon: Icons.store,
        label: 'Catalog',
      ),
    ];

    testWidgets('renders correctly with destinations', (tester) async {
      // Set a larger screen size to ensure widgets are on-screen
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NmtkNavigationRail(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: destinations,
            ),
          ),
        ),
      );

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Catalog'), findsOneWidget);
    });

    testWidgets('triggers onDestinationSelected callback', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int? selectedIndex;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NmtkNavigationRail(
              selectedIndex: 0,
              onDestinationSelected: (index) => selectedIndex = index,
              destinations: destinations,
            ),
          ),
        ),
      );

      // Tap by icon to be safer, or ensure text is visible
      await tester.tap(find.byIcon(Icons.store_outlined));
      await tester.pump();

      expect(selectedIndex, 1);
    });

    testWidgets('renders leading and trailing widgets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NmtkNavigationRail(
              selectedIndex: 0,
              onDestinationSelected: (_) {},
              destinations: destinations,
              leading: const Text('Leading'),
              trailing: const Text('Trailing'),
            ),
          ),
        ),
      );

      expect(find.text('Leading'), findsOneWidget);
      expect(find.text('Trailing'), findsOneWidget);
    });
  });
}
