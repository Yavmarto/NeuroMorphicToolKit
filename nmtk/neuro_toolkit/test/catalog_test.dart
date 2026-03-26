import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/screens/catalog.dart';
import 'package:provider/provider.dart';
import 'mock_module_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('CatalogScreen shows all 7 modules', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 2000);
    tester.view.devicePixelRatio = 1.0;

    final provider = MockModuleProvider();
    provider.loadModules();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: provider,
          child: const CatalogScreen(),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('CNL Studio'), findsOneWidget);
    expect(find.text('NeuroSim'), findsOneWidget);
    expect(find.text('NeuroChip'), findsOneWidget);
    expect(find.text('NeuroBench'), findsOneWidget);
    expect(find.text('NeuroSense'), findsOneWidget);
    expect(find.text('NeuroHub'), findsOneWidget);
    expect(find.text('NDH Simulator'), findsOneWidget);

    addTearDown(tester.view.resetPhysicalSize);
  });

  testWidgets('CatalogScreen handles Install button click', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;

    final provider = MockModuleProvider();
    provider.loadModules();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: provider,
          child: const CatalogScreen(),
        ),
      ),
    );

    await tester.pump();

    // Find the Install button for CNL Studio
    final installButton = find.descendant(
      of: find.ancestor(of: find.text('CNL Studio'), matching: find.byType(Card)),
      matching: find.text('Install'),
    );

    expect(installButton, findsOneWidget);
    await tester.tap(installButton);
    await tester.pump();

    expect(provider.installCalls, contains('neurocnl'));
    expect(find.text('Installing'), findsOneWidget);

    addTearDown(tester.view.resetPhysicalSize);
  });
}
