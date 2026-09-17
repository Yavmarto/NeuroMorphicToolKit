import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurobench/widgets/trend_chart.dart';

void main() {
  group('TrendChart', () {
    testWidgets('empty state shows no-data message', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: TrendChart(
                history: <double>[],
                metricName: 'accuracy',
              ),
            ),
          ),
        ),
      );
      expect(find.text('No data points recorded.'), findsOneWidget);
      expect(
        find.text('Chart visualisation not available in this build.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.show_chart), findsNothing);
    });

    testWidgets('shows metric name in header', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 200,
              child: TrendChart(
                history: <double>[],
                metricName: 'latency_ms',
              ),
            ),
          ),
        ),
      );
      expect(find.text('Trend: latency_ms'), findsOneWidget);
    });

    testWidgets('populated state renders data rows', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: TrendChart(
                history: [0.91, 0.93, 0.95],
                metricName: 'accuracy',
              ),
            ),
          ),
        ),
      );
      expect(find.text('0.91'), findsOneWidget);
      expect(find.text('0.95'), findsOneWidget);
      expect(
        find.text('Chart visualisation not available in this build.'),
        findsOneWidget,
      );
      expect(find.text('No data points recorded.'), findsNothing);
    });
  });
}
