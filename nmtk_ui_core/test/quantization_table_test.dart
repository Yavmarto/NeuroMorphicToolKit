import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('NmtkQuantizationTable', () {
    testWidgets('renders report data into data table correctly', (WidgetTester tester) async {
      const report = QuantizationReport(
        bitWidths: [8, 4],
        accuracyDrops: [0.01, 0.06],
        sparsity: [0.5, 0.8],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NmtkQuantizationTable(report: report)),
        ),
      );

      // Verify Headers
      expect(find.text('Bit Width'), findsOneWidget);
      expect(find.text('Accuracy Drop'), findsOneWidget);
      expect(find.text('Sparsity'), findsOneWidget);

      // Verify Rows Data
      expect(find.text('8-bit'), findsOneWidget);
      expect(find.text('4-bit'), findsOneWidget);
      expect(find.text('1.00%'), findsOneWidget);
      expect(find.text('6.00%'), findsOneWidget);
      expect(find.text('50.0%'), findsOneWidget);
      expect(find.text('80.0%'), findsOneWidget);
    });

    testWidgets('renders empty state gracefully when report is empty', (WidgetTester tester) async {
      const report = QuantizationReport(
        bitWidths: [],
        accuracyDrops: [],
        sparsity: [],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NmtkQuantizationTable(report: report)),
        ),
      );

      // No data cells or tables
      expect(find.byType(DataTable), findsNothing);
      expect(find.text('No quantization data'), findsOneWidget);
    });
  });
}
