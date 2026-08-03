import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nmtk_ui_core/visualization/tile_grid_renderer.dart';

void main() {
  group('TileActivityFrame', () {
    test('tileCount is rows * cols', () {
      final frame = TileActivityFrame(
        totalNeuronCount: 1000,
        tileActivity: Float32List(6),
        tileConcentration: Float32List(6),
        tileRows: 2,
        tileCols: 3,
        simulationTimeMs: 0,
      );
      expect(frame.tileCount, 6);
    });

    test('filledTileCount is tileCount when the grid is exactly filled', () {
      final frame = TileActivityFrame(
        totalNeuronCount: 6,
        tileActivity: Float32List(6),
        tileConcentration: Float32List(6),
        tileRows: 2,
        tileCols: 3,
        simulationTimeMs: 0,
      );
      expect(frame.filledTileCount, 6);
    });

    test('filledTileCount clamps to the buffers on a padded grid', () {
      // 10 neurons bin into a 3x4 grid -> 12 tiles, 2 of them empty.
      final frame = TileActivityFrame(
        totalNeuronCount: 10,
        tileActivity: Float32List(10),
        tileConcentration: Float32List(10),
        tileRows: 3,
        tileCols: 4,
        simulationTimeMs: 0,
      );
      expect(frame.tileCount, 12);
      expect(frame.filledTileCount, 10);
    });

    test('neuronsForTile divides total neuron count evenly across tiles', () {
      final frame = TileActivityFrame(
        totalNeuronCount: 800,
        tileActivity: Float32List(8),
        tileConcentration: Float32List(8),
        tileRows: 2,
        tileCols: 4,
        simulationTimeMs: 0,
      );
      expect(frame.neuronsForTile(0), 100);
    });
  });

  testWidgets(
    'TileGridNeuronRenderer shows a loading indicator before the first frame',
    (tester) async {
      final renderer = TileGridNeuronRenderer();
      addTearDown(renderer.dispose);
      renderer.attach(const Size(200, 200));

      await tester.pumpWidget(
        MaterialApp(home: Builder(builder: renderer.buildSurface)),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets('TileGridNeuronRenderer paints a grid after pushFrame', (
    tester,
  ) async {
    final renderer = TileGridNeuronRenderer();
    addTearDown(renderer.dispose);
    renderer.attach(const Size(200, 200));

    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.buildSurface)),
    );

    renderer.pushFrame(
      TileActivityFrame(
        totalNeuronCount: 100,
        tileActivity: Float32List.fromList([0.5, 0.8, 0.1, 0.9]),
        tileConcentration: Float32List.fromList([0.2, 0.7, 0.0, 1.0]),
        tileRows: 2,
        tileCols: 2,
        simulationTimeMs: 33.0,
      ),
    );
    await tester.pump();

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('paints a padded grid whose tileCount exceeds the buffers', (
    tester,
  ) async {
    // Regression: binning N neurons into a near-square grid leaves trailing
    // tiles with no value (10 neurons -> 3x4 -> 12 tiles). The painter used
    // to bound its index against tileCount (== 12), so it read past the
    // length-10 buffers and threw RangeError on every single paint.
    final renderer = TileGridNeuronRenderer();
    addTearDown(renderer.dispose);
    renderer.attach(const Size(200, 200));

    await tester.pumpWidget(
      MaterialApp(home: Builder(builder: renderer.buildSurface)),
    );

    renderer.pushFrame(
      TileActivityFrame(
        totalNeuronCount: 10,
        tileActivity: Float32List(10),
        tileConcentration: Float32List(10),
        tileRows: 3,
        tileCols: 4,
        simulationTimeMs: 0,
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
