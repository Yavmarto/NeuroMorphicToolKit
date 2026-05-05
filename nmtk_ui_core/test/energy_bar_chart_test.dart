import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

void main() {
  group('NmtkEnergyBarChart', () {
    testWidgets('renders total energy correctly', (WidgetTester tester) async {
      const report = EnergyReport(
        perEnsemblePj: {'E1': 10.0, 'E2': 20.0},
        totalPj: 30.0,
        opsCount: 100,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NmtkEnergyBarChart(report: report)),
        ),
      );

      expect(find.text('Total Energy'), findsOneWidget);
      expect(find.text('30.00 pJ'), findsOneWidget);
      expect(find.text('100'), findsOneWidget);
    });

    testWidgets('renders ensemble breakdowns correctly', (
      WidgetTester tester,
    ) async {
      const report = EnergyReport(
        perEnsemblePj: {'E1': 10.0, 'E2': 20.0},
        totalPj: 30.0,
        opsCount: 100,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NmtkEnergyBarChart(report: report)),
        ),
      );

      expect(find.text('E1'), findsOneWidget);
      expect(find.text('10.00 pJ'), findsOneWidget);
      expect(find.text('E2'), findsOneWidget);
      expect(find.text('20.00 pJ'), findsOneWidget);

      // Verify visual components
      expect(find.byType(LinearProgressIndicator), findsWidgets);
    });

    testWidgets('handles empty ensembles gracefully', (
      WidgetTester tester,
    ) async {
      const report = EnergyReport(perEnsemblePj: {}, totalPj: 0.0, opsCount: 0);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: NmtkEnergyBarChart(report: report)),
        ),
      );

      expect(find.text('No ensemble data'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });
  });
}
