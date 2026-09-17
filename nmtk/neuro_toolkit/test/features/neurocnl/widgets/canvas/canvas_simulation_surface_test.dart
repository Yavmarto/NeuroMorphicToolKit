import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/bulk_spike_frame.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/preview.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/simulation_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/services/server_config_service.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_simulation_surface.dart';

class _FakeSimulationController extends SimulationController {
  _FakeSimulationController(this._initial);
  final SimulationState _initial;

  @override
  SimulationState build() => _initial;
}

CanvasNode _node(String id, {required List<double> position}) => CanvasNode(
  id: id,
  componentId: 'lif_population',
  label: id,
  parameters: const {},
  position: position,
  width: 100,
  height: 80,
);

Widget _buildApp(SimulationState state) {
  return ProviderScope(
    overrides: [
      simulationControllerProvider.overrideWith(
        () => _FakeSimulationController(state),
      ),
    ],
    child: const MaterialApp(home: Scaffold(body: CanvasSimulationSurface())),
  );
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ServerConfigService.initialize();
  });

  testWidgets(
    'renders one box per active bulk-frame node instead of the node dropdown',
    (tester) async {
      final bulkFrame = BulkSpikeFrame.fromJson({
        'nodes': {
          'pop_a': {
            'data': [0.0, 1.0],
            'density_grid': [0.5],
            'grid_w': 1,
            'grid_h': 1,
            'neuron_count': 6000,
          },
          'pop_b': {
            'data': <double>[],
            'density_grid': [0.0],
            'grid_w': 1,
            'grid_h': 1,
            'neuron_count': 6000,
          },
        },
        'scale_hint': 'particle',
      });

      final state = SimulationState(
        status: SimulationStatus.completed,
        playback: PreviewPlayback(durationMs: 100, bulkSpikeFrame: bulkFrame),
        graphNodes: [
          _node('pop_a', position: [0, 0]),
          _node('pop_b', position: [200, 0]),
        ],
      );

      await tester.pumpWidget(_buildApp(state));
      await tester.pump();

      expect(find.text('pop_a'), findsOneWidget);
      expect(find.text('pop_b'), findsOneWidget);
      // The small-network dropdown UI must not render alongside the bulk panel.
      expect(find.text('Selected population'), findsNothing);
    },
  );

  testWidgets('a graph node absent from the bulk frame is not rendered', (
    tester,
  ) async {
    final bulkFrame = BulkSpikeFrame.fromJson({
      'nodes': {
        'pop_a': {
          'data': [0.0, 1.0],
          'density_grid': [0.5],
          'grid_w': 1,
          'grid_h': 1,
          'neuron_count': 6000,
        },
      },
      'scale_hint': 'particle',
    });

    final state = SimulationState(
      status: SimulationStatus.completed,
      playback: PreviewPlayback(durationMs: 100, bulkSpikeFrame: bulkFrame),
      graphNodes: [
        _node('pop_a', position: [0, 0]),
        _node('idle_pop', position: [200, 0]),
      ],
    );

    await tester.pumpWidget(_buildApp(state));
    await tester.pump();

    expect(find.text('pop_a'), findsOneWidget);
    expect(find.text('idle_pop'), findsNothing);
  });
}
