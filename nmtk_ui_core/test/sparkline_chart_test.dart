import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('NmtkSparklineChart', () {
    testWidgets('renders chart with data and label', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkSparklineChart(
              values: [0.1, 0.5, 0.2, 0.8],
              color: Colors.blue,
              label: 'Test Sparkline',
            ),
          ),
        ),
      );

      expect(find.text('Test Sparkline'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders gracefully with single value', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkSparklineChart(
              values: [0.5],
              color: Colors.blue,
              label: 'Single Val',
            ),
          ),
        ),
      );

      expect(find.text('Single Val'), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets('renders gracefully with empty values', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkSparklineChart(
              values: [],
              color: Colors.blue,
              label: 'Empty',
            ),
          ),
        ),
      );

      expect(find.text('No data'), findsOneWidget);
    });

    testWidgets('respects missing label gracefully', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NmtkSparklineChart(values: [0.1, 0.9], color: Colors.red),
          ),
        ),
      );

      expect(find.byType(Text), findsNothing);
      expect(find.byType(CustomPaint), findsWidgets);
    });
  });
}
