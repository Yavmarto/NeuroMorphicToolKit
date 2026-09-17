import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/cnl_line_node_map_provider.dart';

CanvasNode _node({
  required String id,
  String? label,
  Map<String, dynamic> parameters = const <String, dynamic>{},
}) => CanvasNode(
  id: id,
  componentId: 'lif_population',
  label: label,
  parameters: parameters,
  position: const <double>[0, 0],
);

ParseSentence _sentence({
  required int line,
  required String subject,
  bool valid = true,
}) => ParseSentence(
  line: line,
  raw: subject,
  valid: valid,
  parsed: valid
      ? ParsedSpec(
          concept: 'neuron',
          subject: subject,
          action: 'define',
          verb: 'define',
          negated: false,
        )
      : null,
);

void main() {
  group('buildCnlLineNodeMap', () {
    test('matches labels and parameter names case-insensitively', () {
      final map = buildCnlLineNodeMap(
        <ParseSentence>[
          _sentence(line: 2, subject: 'input layer'),
          _sentence(line: 5, subject: 'hidden'),
        ],
        <CanvasNode>[
          _node(id: 'input', label: 'Input Layer'),
          _node(
            id: 'hidden',
            parameters: const <String, dynamic>{'name': 'HIDDEN'},
          ),
        ],
      );

      expect(map.lineToNode, <int, String>{2: 'input', 5: 'hidden'});
      expect(map.nodeToLine, <String, int>{'input': 2, 'hidden': 5});
    });

    test('keeps the first matching CNL line for each node', () {
      final map = buildCnlLineNodeMap(
        <ParseSentence>[
          _sentence(line: 1, subject: 'hidden'),
          _sentence(line: 4, subject: 'hidden'),
        ],
        <CanvasNode>[_node(id: 'hidden', label: 'hidden')],
      );

      expect(map.lineToNode, <int, String>{1: 'hidden', 4: 'hidden'});
      expect(map.nodeToLine, <String, int>{'hidden': 1});
    });

    test('ignores invalid sentences and nodes that are no longer present', () {
      final map = buildCnlLineNodeMap(
        <ParseSentence>[
          _sentence(line: 1, subject: 'invalid', valid: false),
          _sentence(line: 2, subject: 'deleted'),
        ],
        <CanvasNode>[_node(id: 'active', label: 'active')],
      );

      expect(map.lineToNode, isEmpty);
      expect(map.nodeToLine, isEmpty);
    });
  });
}
