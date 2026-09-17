import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/time_series_chart.dart';

void main() {
  group('TimeSeriesChart', () {
    testWidgets('renders traces correctly', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TimeSeriesChart(
              traces: [
                [-65.0, -60.0, -55.0, -50.0],
                [-66.0, -62.0, -58.0, -54.0],
              ],
              time: [0.0, 1.0, 2.0, 3.0],
              labels: ['n0', 'n1'],
              title: 'Test Voltages',
            ),
          ),
        ),
      );

      expect(find.text('Test Voltages'), findsOneWidget);
    });

    testWidgets('shows empty state for no traces', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: TimeSeriesChart(traces: [], time: [], labels: []),
          ),
        ),
      );

      expect(find.text('No traces to display.'), findsOneWidget);
    });
  });
}
