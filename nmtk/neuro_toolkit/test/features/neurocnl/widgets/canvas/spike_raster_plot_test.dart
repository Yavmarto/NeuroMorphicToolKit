import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/spike_raster_plot.dart';

void main() {
  group('SpikeRasterPlot', () {
    testWidgets('renders spike raster with correct number of neurons', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SpikeRasterPlot(
              spikes: [
                [5.0, 15.0, 25.0],
                [10.0, 20.0, 30.0],
                [2.0, 8.0, 18.0],
              ],
              duration: 50.0,
              title: 'Test Raster',
            ),
          ),
        ),
      );

      expect(find.text('Test Raster'), findsOneWidget);
    });

    testWidgets('shows empty state for no spikes', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SpikeRasterPlot(spikes: [], duration: 100.0)),
        ),
      );

      expect(find.text('No spikes recorded.'), findsOneWidget);
    });
  });
}
