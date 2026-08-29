import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/quantization_report.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/quantization_curve_chart.dart';

void main() {
  group('QuantizationCurveChart', () {
    testWidgets('renders report data at the active layout width', (
      WidgetTester tester,
    ) async {
      const report = QuantizationReport(
        bitWidths: [8, 4],
        accuracyDrops: [0.01, 0.06],
        sparsity: [0.5, 0.8],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: QuantizationCurveChart(report: report)),
        ),
      );

      expect(find.text('8-bit'), findsOneWidget);
      expect(find.text('4-bit'), findsOneWidget);
      expect(find.textContaining('Drop 1.00%'), findsOneWidget);
      expect(find.textContaining('Sparsity 80.0%'), findsOneWidget);
    });

    testWidgets('renders empty state gracefully when report is empty', (
      WidgetTester tester,
    ) async {
      const report = QuantizationReport(
        bitWidths: [],
        accuracyDrops: [],
        sparsity: [],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: QuantizationCurveChart(report: report)),
        ),
      );

      // No data cells or tables
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('No quantization data'), findsOneWidget);
    });
  });
}
