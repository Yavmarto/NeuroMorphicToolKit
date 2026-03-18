// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/main.dart';
import 'package:provider/provider.dart';
import 'package:neuro_toolkit/providers/module_provider.dart';

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ModuleProvider()),
        ],
        child: const NeuroToolkitApp(),
      ),
    );

    // Verify that the Dashboard is shown.
    expect(find.text('Dashboard'), findsWidgets);
  });
}
