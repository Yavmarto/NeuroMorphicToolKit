import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';
import 'package:neuro_toolkit/screens/tool_view.dart';
import 'package:neuro_toolkit/widgets/module_tab_bar.dart';
import 'ui_integration_mock_provider.dart';

void main() {
  testWidgets('ToolViewScreen tab management test',
      (WidgetTester tester) async {
    final mockProvider = MockModuleProvider();

    // Initial launch of m1
    await mockProvider.launchModule('m1');

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: mockProvider,
          child: const ToolViewScreen(initialModuleId: 'm1'),
        ),
      ),
    );

    await tester.pump();

    // Verify m1 is active
    expect(find.text('Module 1'), findsWidgets);
    expect(find.byType(ModuleTabBar), findsOneWidget);

    // Launch m2
    await mockProvider.launchModule('m2');
    await tester.pump();

    // Verify both tabs exist in the tab bar
    expect(find.text('Module 1'), findsWidgets);
    expect(find.text('Module 2'), findsWidgets);

    // Switch to m2 tab (tap the InkWell containing 'Module 2')
    await tester.tap(find.text('Module 2').last);
    await tester.pump();

    // Close m1 tab
    final closeButtonM1 = find.descendant(
      of: find.ancestor(
          of: find.text('Module 1').last, matching: find.byType(Row)),
      matching: find.byIcon(Icons.close),
    );

    await tester.tap(closeButtonM1);
    await tester.pump();

    // Verify m1 tab is gone
    expect(find.text('Module 1'), findsNothing);
    expect(find.text('Module 2'), findsWidgets);
  });

  testWidgets('Fallback to browser button exists', (WidgetTester tester) async {
    final mockProvider = MockModuleProvider();
    await mockProvider.launchModule('m1');

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<ModuleProvider>.value(
          value: mockProvider,
          child: const ToolViewScreen(initialModuleId: 'm1'),
        ),
      ),
    );

    await tester.pump();

    // Verify "Open in System Browser" icon button exists.
    // Use find.byTooltip to be more specific if possible, or just expect it to be there.
    expect(find.byIcon(Icons.open_in_browser), findsWidgets);

    // Verify wait screen elements (since it's not ready in the mock polling)
    expect(find.textContaining('Waiting for Module 1'), findsOneWidget);
    expect(find.text('Open in Browser instead'), findsOneWidget);
  });
}
