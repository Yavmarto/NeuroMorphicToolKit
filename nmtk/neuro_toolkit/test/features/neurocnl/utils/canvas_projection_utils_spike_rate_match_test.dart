// Tests for matchSpikeRatesToNodeIds: resolves backend `layer_spike_rates`
// keys back to the canvas node ids they describe. The backend derives each
// key from the exported NIR graph's node id (a canvas node's own `id`), so
// the primary match is id-based (exact, never ambiguous); display-name
// matching (a sanitized NIR population name compared with non-alphanumeric
// characters stripped and lowercased) is only a fallback for imported NIR
// files with real human-authored names.

import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_projection_utils.dart';

CanvasNode _node(String id, {String? label}) {
  return CanvasNode(
    id: id,
    componentId: 'lif_population',
    label: label,
    parameters: const <String, dynamic>{},
    position: const <double>[0, 0],
  );
}

void main() {
  group('matchSpikeRatesToNodeIds', () {
    test('matches despite case/space/punctuation differences', () {
      final nodes = [_node('n1', label: 'LIF Layer 1')];
      final result = matchSpikeRatesToNodeIds({'lif_layer_1': 0.42}, nodes);
      expect(result, {'n1': 0.42});
    });

    test(
      'falls back to parameters[name] then id, like resolveNodeDisplayName',
      () {
        final byParam = CanvasNode(
          id: 'n2',
          componentId: 'lif_population',
          parameters: const <String, dynamic>{'name': 'Hidden'},
          position: const <double>[0, 0],
        );
        final result = matchSpikeRatesToNodeIds({'hidden': 0.1}, [byParam]);
        expect(result, {'n2': 0.1});
      },
    );

    test('drops unmatched keys instead of guessing', () {
      final nodes = [_node('n1', label: 'LIF 1')];
      final result = matchSpikeRatesToNodeIds({'no_such_node': 0.9}, nodes);
      expect(result, isEmpty);
    });

    test('drops ambiguous keys when two nodes share a display name', () {
      final nodes = [_node('n1', label: 'LIF'), _node('n2', label: 'lif')];
      final result = matchSpikeRatesToNodeIds({'lif': 0.5}, nodes);
      expect(result, isEmpty);
    });

    test('only resolvable keys are kept when mixed with unmatched ones', () {
      final nodes = [_node('n1', label: 'Output')];
      final result = matchSpikeRatesToNodeIds({
        'output': 0.75,
        'unknown_layer': 0.2,
      }, nodes);
      expect(result, {'n1': 0.75});
    });

    test('matches by id even when two nodes share the same generic label', () {
      // Reproduces the real bug: a Studio-built network's two LIF nodes both
      // get label "LIF" (the generic type name), but the backend keys
      // layer_spike_rates by each node's own unique canvas id.
      final nodes = [
        _node('lif_1738383021123', label: 'LIF'),
        _node('lif_1738383029999', label: 'LIF'),
      ];
      final result = matchSpikeRatesToNodeIds({
        'lif_1738383021123': 0.2,
        'lif_1738383029999': 0.6,
      }, nodes);
      expect(result, {'lif_1738383021123': 0.2, 'lif_1738383029999': 0.6});
    });

    test('id match takes priority over an ambiguous label match', () {
      final nodes = [
        _node('lif_1', label: 'LIF'),
        _node('lif_2', label: 'LIF'),
      ];
      final result = matchSpikeRatesToNodeIds({'lif_1': 0.9}, nodes);
      expect(result, {'lif_1': 0.9});
    });
  });
}
