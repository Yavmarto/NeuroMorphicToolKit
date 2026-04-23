import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  testWidgets('NmtkSurfaceCard renders header and body content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NmtkSurfaceCard(
            title: 'Launcher Section',
            subtitle: 'Shared subtitle',
            child: Text('Body content'),
          ),
        ),
      ),
    );

    expect(find.text('Launcher Section'), findsOneWidget);
    expect(find.text('Shared subtitle'), findsOneWidget);
    expect(find.text('Body content'), findsOneWidget);
    expect(find.byType(Card), findsOneWidget);
  });

  testWidgets('NmtkEmptyState shows action button and handles tap', (
    WidgetTester tester,
  ) async {
    var tapped = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NmtkEmptyState(
            title: 'Nothing Here',
            message: 'Install a module to continue.',
            icon: Icons.widgets_outlined,
            action: NmtkPrimaryButton(
              label: 'Install',
              onPressed: () {
                tapped = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(find.text('Nothing Here'), findsOneWidget);
    expect(find.text('Install a module to continue.'), findsOneWidget);
    expect(find.text('Install'), findsOneWidget);

    await tester.tap(find.text('Install'));
    await tester.pump();

    expect(tapped, isTrue);
  });

  testWidgets('NmtkStatusBadge applies label and icon', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: NmtkStatusBadge(
            label: 'Running',
            tone: NmtkTone.success,
            icon: Icons.check_circle,
          ),
        ),
      ),
    );

    expect(find.text('Running'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });
}
