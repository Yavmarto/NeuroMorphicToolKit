import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/snn_dynamics_view.dart';

void main() {
  group('SnnDynamicsView', () {
    testWidgets('renders spike raster when only spikes are provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SnnDynamicsView(
              spikes: {
                '0': [5.0, 15.0, 25.0],
                '1': [10.0, 20.0, 30.0],
              },
              duration: 50.0,
              populationName: 'pop1',
            ),
          ),
        ),
      );

      expect(find.text('pop1 Dynamics'), findsOneWidget);
      expect(find.text('Population Firing Rate'), findsOneWidget);
      // Spike raster should be present (no voltage traces label)
      expect(find.text('Membrane Potential (mV)'), findsNothing);
    });

    testWidgets(
      'renders raster + voltage + firing rate when all data is provided',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SnnDynamicsView(
                spikes: {
                  '0': [5.0, 15.0, 25.0],
                  '1': [10.0, 20.0, 30.0],
                },
                voltages: {
                  '0': [-65.0, -60.0, -55.0, -50.0, -48.0],
                  '1': [-66.0, -62.0, -58.0, -54.0, -50.0],
                },
                duration: 50.0,
                populationName: 'pop1',
              ),
            ),
          ),
        );

        expect(find.text('pop1 Dynamics'), findsOneWidget);
        expect(find.text('Population Firing Rate'), findsOneWidget);
        expect(find.text('Membrane Potential (mV)'), findsOneWidget);
        // Voltage legend should show neuron labels
        expect(find.text('0'), findsWidgets);
      },
    );

    testWidgets('shows empty state when no data is provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SnnDynamicsView(spikes: {}, duration: 100.0)),
        ),
      );

      expect(
        find.text('No data recorded for this population.'),
        findsOneWidget,
      );
    });
  });
}
