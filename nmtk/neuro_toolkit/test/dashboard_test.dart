import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/screens/dashboard.dart';
import 'package:provider/provider.dart';
import 'mock_dashboard_provider.dart';

void main() {
  testWidgets('DashboardScreen shows empty state when no modules are installed',
      (WidgetTester tester) async {
    final mockProvider = MockDashboardProvider();
    mockProvider.setInstalledModules([]);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: mockProvider,
          child: const DashboardScreen(),
        ),
      ),
    );

    expect(
      find.text(
        'No modules installed yet. Go to the Catalog to install modules.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('DashboardScreen shows installed modules and responds to buttons',
      (WidgetTester tester) async {
    final mockProvider = MockDashboardProvider();
    final installedModule = Module(
      id: 'test_module',
      name: 'Test Module',
      description: 'Test description',
      directory: 'dir',
      status: ModuleStatus.installed,
    );
    mockProvider.setInstalledModules([installedModule]);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: mockProvider,
          child: const DashboardScreen(),
        ),
      ),
    );

    expect(find.text('Test Module'), findsOneWidget);
    expect(find.text('Test description'), findsOneWidget);

    // Find the Start button
    final startButton = find.text('Start');
    expect(startButton, findsOneWidget);

    // Tap the Start button
    await tester.tap(startButton);
    await tester.pump();

    expect(mockProvider.launchCalls, contains('test_module'));

    // Update status to running
    final runningModule =
        installedModule.copyWith(status: ModuleStatus.running);
    mockProvider.setInstalledModules([runningModule]);
    await tester.pump();

    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);

    // Tap the Stop button
    await tester.tap(find.text('Stop'));
    await tester.pump();

    expect(mockProvider.stopCalls, contains('test_module'));

    // Tap the Uninstall button
    await tester.tap(find.byIcon(Icons.delete));
    await tester.pump();

    expect(mockProvider.uninstallCalls, contains('test_module'));
  });

  testWidgets('DashboardScreen handles Open button click',
      (WidgetTester tester) async {
    final mockProvider = MockDashboardProvider();
    final runningModule = Module(
      id: 'test_module',
      name: 'Test Module',
      description: 'Test description',
      directory: 'dir',
      status: ModuleStatus.running,
    );
    mockProvider.setInstalledModules([runningModule]);

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: mockProvider,
          child: const DashboardScreen(),
        ),
      ),
    );

    expect(find.text('Open'), findsOneWidget);
  });
}
