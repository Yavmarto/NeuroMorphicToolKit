import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/deploy/pynq_support_state_card.dart';
// ignore: unnecessary_import — explicit Zeta import for clarity over re-export
import 'package:zeta_flutter/zeta_flutter.dart';

void main() {
  group('PynqSupportStateCard', () {
    testWidgets('renders exportable state with correct label', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PynqSupportStateCard(
              supportState: PynqSupportState.exportable,
            ),
          ),
        ),
      );

      expect(find.text('Exportable — overlay package ready'), findsOneWidget);
      expect(find.byIcon(ZetaIcons.upload_file), findsOneWidget);
    });

    testWidgets('renders exportable_with_warnings state', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PynqSupportStateCard(
              supportState: PynqSupportState.exportableWithWarnings,
              warnings: ['Network uses 205/256 neurons (>80% capacity)'],
            ),
          ),
        ),
      );

      expect(find.text('Exportable — near capacity limits'), findsOneWidget);
      expect(find.byIcon(ZetaIcons.warning_outline), findsOneWidget);
      expect(find.textContaining('205/256 neurons'), findsOneWidget);
    });

    testWidgets('renders not_exportable state with rejections', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PynqSupportStateCard(
              supportState: PynqSupportState.notExportable,
              rejections: ['Exceeds neuron capacity'],
            ),
          ),
        ),
      );

      expect(find.text('Not Exportable — see rejections'), findsOneWidget);
      expect(find.byIcon(ZetaIcons.block), findsOneWidget);
      expect(find.textContaining('Exceeds neuron capacity'), findsOneWidget);
    });

    testWidgets('renders deployable state', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PynqSupportStateCard(
              supportState: PynqSupportState.deployable,
            ),
          ),
        ),
      );

      expect(find.text('Deployed — running on PYNQ board'), findsOneWidget);
      expect(find.byIcon(ZetaIcons.check_circle), findsOneWidget);
    });

    testWidgets('renders not_deployable state', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PynqSupportStateCard(
              supportState: PynqSupportState.notDeployable,
            ),
          ),
        ),
      );

      expect(find.text('Not Deployable — board unreachable'), findsOneWidget);
      expect(find.byIcon(ZetaIcons.cloud_off), findsOneWidget);
    });

    testWidgets('renders network summary when provided', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PynqSupportStateCard(
              supportState: PynqSupportState.exportable,
              networkSummary: {
                'n_neurons': 128,
                'n_synapses': 512,
                'estimated_memory_kb': 36.5,
              },
            ),
          ),
        ),
      );

      expect(find.textContaining('128 neurons'), findsOneWidget);
      expect(find.textContaining('512 synapses'), findsOneWidget);
      expect(find.textContaining('36.5 KB est.'), findsOneWidget);
    });

    testWidgets('does not render warnings section when list is empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PynqSupportStateCard(
              supportState: PynqSupportState.exportable,
              warnings: [],
            ),
          ),
        ),
      );

      expect(find.textContaining('⚠'), findsNothing);
    });

    testWidgets('does not render rejections section when list is empty', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PynqSupportStateCard(
              supportState: PynqSupportState.exportable,
              rejections: [],
            ),
          ),
        ),
      );

      expect(find.textContaining('✗'), findsNothing);
    });
  });
}
