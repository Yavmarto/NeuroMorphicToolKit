// The key-parameter line under a node's title. The Architecture cards showed
// a bare title while the Train/Eval cards already carried this second line, so
// the two headers read differently; nirNodeKeyParam is what closes that gap.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';
import 'package:neuro_toolkit/features/neurocnl/models/nir_node_type.dart';
import 'package:neuro_toolkit/features/neurocnl/utils/canvas_node_subtitle.dart';

NirNodeType _type(String id, List<NirParameterDef> parameters) => NirNodeType(
  id: id,
  displayName: id,
  category: 'test',
  icon: Icons.circle,
  ports: const <NirPortDef>[],
  parameters: parameters,
);

CanvasNode _node(Map<String, dynamic> parameters) => CanvasNode(
  id: 'n1',
  componentId: 'c',
  nirType: 'nir.LIF',
  label: 'LIF',
  parameters: parameters,
  position: const <double>[0, 0],
);

void main() {
  group('nirNodeKeyParam', () {
    test('reads the node\'s edited value in priority order', () {
      final String? subtitle = nirNodeKeyParam(
        _node(<String, dynamic>{'n_neurons': 64, 'tau': 0.02}),
        null,
      );

      expect(subtitle, 'n: 64 · τ: 0.02');
    });

    test('falls back to the type default when the node has no value', () {
      final String? subtitle = nirNodeKeyParam(
        _node(const <String, dynamic>{}),
        _type('nir.LIF', const [
          NirParameterDef(
            name: 'n_neurons',
            label: 'Neurons',
            type: 'int',
            defaultValue: 1,
          ),
        ]),
      );

      expect(subtitle, 'n: 1');
    });

    test('shape-defined layers report their weight dimensions instead', () {
      expect(
        nirNodeKeyParam(
          _node(<String, dynamic>{'rows': 10, 'cols': 784}),
          null,
        ),
        '784→10',
      );
      expect(
        nirNodeKeyParam(
          _node(<String, dynamic>{'weight_shape': '8, 1, 3, 3'}),
          null,
        ),
        '[8,1,3,3]',
      );
    });

    test('shows at most two fields, and nothing when there is nothing to '
        'show', () {
      final String? subtitle = nirNodeKeyParam(
        _node(<String, dynamic>{
          'n_neurons': 8,
          'tau': 0.02,
          'threshold': 1.0,
          'beta': 0.9,
        }),
        null,
      );

      expect(subtitle, 'n: 8 · τ: 0.02');
      expect(nirNodeKeyParam(_node(const <String, dynamic>{}), null), isNull);
    });

    test('trims float noise rather than printing a long tail', () {
      expect(
        nirNodeKeyParam(_node(<String, dynamic>{'tau': 1.0}), null),
        'τ: 1',
      );
    });
  });

  group('pipelineNodeKeyParam', () {
    test('reports the optimiser learning rate', () {
      expect(
        pipelineNodeKeyParam(
          const PipelineDagNode(
            id: 'o',
            type: PipelineDagNodeType.adamOptimiser,
            x: 0,
            y: 0,
            parameters: <String, dynamic>{'lr': 0.001},
          ),
        ),
        'lr: 0.001',
      );
    });

    test('returns null for a node with nothing worth showing', () {
      expect(
        pipelineNodeKeyParam(
          const PipelineDagNode(
            id: 'f',
            type: PipelineDagNodeType.forwardPass,
            x: 0,
            y: 0,
          ),
        ),
        isNull,
      );
    });
  });
}
