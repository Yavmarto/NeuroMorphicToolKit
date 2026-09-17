import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canonical_editor_document.dart';
import 'package:neuro_toolkit/features/neurocnl/models/health_status.dart';
import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/src/features/studio/domain/workspace_file.dart';

void main() {
  group('ParsedSpec Serialization', () {
    test('ParsedSpec.fromJson correctly parses valid JSON', () {
      final json = {
        'concept': 'threshold_firing',
        'subject': 'sensory_neuron',
        'action': 'fire',
        'verb': 'MUST',
        'negated': false,
        'condition': 'potential > 1.0',
      };
      final spec = ParsedSpec.fromJson(json);
      expect(spec.concept, 'threshold_firing');
      expect(spec.subject, 'sensory_neuron');
      expect(spec.action, 'fire');
      expect(spec.verb, 'MUST');
      expect(spec.negated, false);
      expect(spec.condition, 'potential > 1.0');
    });

    test('ParseSentence.fromJson correctly parses valid JSON', () {
      final json = {
        'line': 1,
        'raw': 'The sensory neuron MUST fire ONLY IF potential > 1.0',
        'parsed': {
          'concept': 'threshold_firing',
          'subject': 'sensory_neuron',
          'action': 'fire',
          'verb': 'MUST',
          'negated': false,
          'condition': 'potential > 1.0',
        },
        'valid': true,
        'error': null,
      };
      final sentence = ParseSentence.fromJson(json);
      expect(sentence.line, 1);
      expect(
        sentence.raw,
        'The sensory neuron MUST fire ONLY IF potential > 1.0',
      );
      expect(sentence.valid, true);
      expect(sentence.parsed, isNotNull);
      expect(sentence.parsed!.concept, 'threshold_firing');
    });

    test('ParseSentence.fromJson parses structured error details', () {
      final json = {
        'line': 2,
        'raw': 'Make a neuron that goes zap fast.',
        'parsed': null,
        'valid': false,
        'error': 'The sentence does not match any supported CNL grammar.',
        'error_detail': {
          'code': 'unsupported_sentence_family',
          'message': 'The sentence does not match any supported CNL grammar.',
          'hint': 'This sentence family is not in the supported CNL grammar.',
          'examples': [
            'The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0',
          ],
          'line': 2,
        },
      };

      final sentence = ParseSentence.fromJson(json);
      expect(sentence.valid, false);
      expect(sentence.errorDetail, isNotNull);
      expect(sentence.errorDetail!.primaryCode, 'unsupported_sentence_family');
      expect(sentence.errorDetail!.examples, isNotEmpty);
    });

    test('ParseResult.fromJson correctly parses valid JSON', () {
      final json = {
        'sentences': [
          {'line': 1, 'raw': 'Valid sentence', 'valid': true},
        ],
        'total': 1,
        'errors': 0,
      };
      final result = ParseResult.fromJson(json);
      expect(result.total, 1);
      expect(result.errors, 0);
      expect(result.sentences.length, 1);
      expect(result.sentences[0].raw, 'Valid sentence');
    });
  });

  group('SimulationResult Serialization', () {
    test('ProbeData.fromJson correctly parses spike_raster JSON', () {
      final json = {
        'type': 'spike_raster',
        'times': [0.1, 0.2, 0.3],
        'neuron_indices': [0, 1, 0],
      };
      final probe = ProbeData.fromJson(json);
      expect(probe.type, 'spike_raster');
      expect(probe.times, [0.1, 0.2, 0.3]);
      expect(probe.neuronIndices, [0, 1, 0]);
      expect(probe.values, isNull);
    });

    test('ProbeData.fromJson correctly parses continuous JSON', () {
      final json = {
        'type': 'continuous',
        'times': [0.0, 0.001, 0.002],
        'values': [0.5, 0.55, 0.6],
      };
      final probe = ProbeData.fromJson(json);
      expect(probe.type, 'continuous');
      expect(probe.times, [0.0, 0.001, 0.002]);
      expect(probe.values, [0.5, 0.55, 0.6]);
      expect(probe.neuronIndices, isNull);
    });

    test('SimulationSummary.fromJson correctly parses valid JSON', () {
      final json = {
        'sensory_spike_count': 100,
        'motor_spike_count': 50,
        'sensory_mean_rate': 10.5,
        'motor_mean_rate': 5.2,
        'first_output_spike': 0.12,
        'input_to_output_latency': 0.005,
      };
      final summary = SimulationSummary.fromJson(json);
      expect(summary.sensorySpikeCount, 100);
      expect(summary.motorSpikeCount, 50);
      expect(summary.sensoryMeanRate, 10.5);
      expect(summary.motorMeanRate, 5.2);
      expect(summary.firstOutputSpike, 0.12);
      expect(summary.inputToOutputLatency, 0.005);
    });

    test('SimulationResult.fromJson correctly parses valid JSON', () {
      final json = {
        'duration': 1.0,
        'dt': 0.001,
        'timesteps': 1000,
        'probes': {
          'sensory': {
            'type': 'spike_raster',
            'times': [0.1],
            'neuron_indices': [0],
          },
        },
        'summary': {
          'sensory_spike_count': 1,
          'motor_spike_count': 0,
          'sensory_mean_rate': 1.0,
          'motor_mean_rate': 0.0,
        },
        'wall_time_seconds': 0.5,
      };
      final result = SimulationResult.fromJson(json);
      expect(result.duration, 1.0);
      expect(result.dt, 0.001);
      expect(result.timesteps, 1000);
      expect(result.probes.containsKey('sensory'), true);
      expect(result.summary.sensorySpikeCount, 1);
      expect(result.wallTimeSeconds, 0.5);
    });

    test('SimulationResult round-trips through JSON', () {
      const result = SimulationResult(
        duration: 1.0,
        dt: 0.001,
        timesteps: 1000,
        wallTimeSeconds: 0.5,
        probes: <String, ProbeData>{
          'sensory': ProbeData(
            type: 'spike_raster',
            times: <double>[0.1],
            neuronIndices: <int>[0],
          ),
          'voltage': ProbeData(
            type: 'continuous',
            times: <double>[0.0, 0.001],
            values: <double>[0.5, 0.6],
          ),
        },
        summary: SimulationSummary(
          sensorySpikeCount: 1,
          motorSpikeCount: 0,
          sensoryMeanRate: 1.0,
          motorMeanRate: 0.0,
        ),
      );

      final decoded = SimulationResult.fromJson(result.toJson());

      expect(decoded.duration, result.duration);
      expect(decoded.probes['sensory']?.neuronIndices, <int>[0]);
      expect(decoded.probes['voltage']?.values, <double>[0.5, 0.6]);
      expect(decoded.summary.sensorySpikeCount, 1);
    });
  });

  group('Workspace Pipeline Cache Serialization', () {
    const network = NetworkGraph(
      nodes: <NetworkNode>[
        NetworkNode(
          id: 'n1',
          type: 'ensemble',
          subtype: 'lif',
          label: 'Neuron',
          params: <String, Object?>{'n_neurons': 10},
          position: NodePosition(x: 1, y: 2),
        ),
      ],
      edges: <NetworkEdge>[
        NetworkEdge(
          id: 'e1',
          source: 'n1',
          target: 'n2',
          isInhibitory: false,
          hasLearningRule: false,
          hasDelay: false,
          params: <String, Object?>{'weight': 1.0},
        ),
      ],
    );
    const generateResult = GenerateResult(
      network: network,
      cnlDocument: 'round-trip cnl',
      nirCode: 'nir code',
    );
    const simulationResult = SimulationResult(
      duration: 1.0,
      dt: 0.001,
      timesteps: 1000,
      wallTimeSeconds: 0.5,
      probes: <String, ProbeData>{},
      summary: SimulationSummary(
        sensorySpikeCount: 0,
        motorSpikeCount: 0,
        sensoryMeanRate: 0,
        motorMeanRate: 0,
      ),
    );

    test('GenerateResult round-trips graph and generated code outputs', () {
      final decoded = GenerateResult.fromJson(generateResult.toJson());

      expect(decoded.cnlDocument, 'round-trip cnl');
      expect(decoded.nirCode, 'nir code');
      expect(decoded.network.nodes.single.position?.x, 1);
      expect(decoded.network.edges.single.params['weight'], 1.0);
    });

    test('WorkspaceFile round-trips with pipeline cache', () {
      const content = 'The neuron MUST fire';
      final file = WorkspaceFile(
        id: 'file-a',
        name: 'A.cnl',
        canonicalDocument: const CanonicalEditorDocument(
          irJson: {},
          cnlText: content,
        ),
        pipelineCache: WorkspacePipelineCache(
          sourceHash: WorkspacePipelineCache.sourceHashFor(content),
          generatedAt: '2026-05-11T12:00:00.000',
          simulatedAt: '2026-05-11T12:00:01.000',
          generateResult: generateResult,
          simulationResult: simulationResult,
        ),
        nirArtifactCache: WorkspaceNirArtifactCache.fromBytes(
          content: content,
          filename: 'network.nir',
          mimeType: 'application/octet-stream',
          payload: Uint8List.fromList(const <int>[1, 2, 3, 4]),
          savedAt: '2026-05-11T12:00:02.000',
        ),
      );

      final decoded = WorkspaceFile.fromJson(file.toJson());

      expect(decoded.pipelineCache, isNotNull);
      expect(decoded.pipelineCache!.isValidForContent(content), isTrue);
      expect(decoded.pipelineCache!.generateResult.nirCode, 'nir code');
      expect(decoded.pipelineCache!.simulationResult?.duration, 1.0);
      expect(decoded.nirArtifactCache?.filename, 'network.nir');
      expect(decoded.nirArtifactCache?.payloadBytes, <int>[1, 2, 3, 4]);
    });

    test('WorkspaceFile ignores malformed pipeline cache data', () {
      final file = WorkspaceFile.fromJson(<String, dynamic>{
        'id': 'file-a',
        'name': 'A.cnl',
        'canonicalDocument': <String, dynamic>{
          'ir_json': <String, dynamic>{},
          'cnl_text': 'content',
        },
        'pipelineCache': <String, dynamic>{'generateResult': 'bad'},
      });

      expect(file.canonicalDocument?.cnlText, 'content');
      expect(file.pipelineCache, isNull);
    });
  });

  group('ValidationResult Serialization', () {
    test('Layer2 failures prefer normalized fields over legacy fallback', () {
      final json = {
        'layer1': {
          'overall': true,
          'passed': <Object>[],
          'failed': <Object>[],
          'warnings': [
            {
              'name': 'loihi_timestep_resolution_mismatch',
              'message':
                  'Declared network_timestep differs from Loihi timing resolution.',
              'severity': 'warning',
            },
          ],
        },
        'layer2': {
          'overall': false,
          'checks_passed': <Object>[],
          'checks_failed': [
            {
              'check': 'zero_weight_synapse',
              'detail': 'legacy detail',
              'code': 'zero_weight_synapse',
              'message': 'Connection has zero weight.',
              'lines': [3],
            },
          ],
          'neurons_found': ['sensory neuron', 'motor neuron'],
        },
        'overall': false,
        'backend_support': {
          'backend': 'loihi',
          'verdict': 'approximate',
          'warnings': [
            'Declared network_timestep differs from Loihi timing resolution.',
          ],
          'supported_concepts': ['threshold_firing'],
          'approximated_concepts': ['network_topology'],
          'unsupported_concepts': <Object>[],
        },
      };

      final result = ValidationResult.fromJson(json);
      expect(
        result.layer2.checksFailed.single.primaryName,
        'zero_weight_synapse',
      );
      expect(
        result.layer2.checksFailed.single.primaryMessage,
        'Connection has zero weight.',
      );
      expect(result.layer2.checksFailed.single.lines, [3]);
      expect(result.layer1.warnings.single.severity, 'warning');
      expect(result.backendSupport, isNotNull);
      expect(result.backendSupport!.backend, 'loihi');
      expect(result.backendSupport!.verdict, 'approximate');
    });
  });

  group('HealthStatus Serialization', () {
    test('HealthStatus.fromJson tolerates missing disk payload', () {
      final json = {
        'status': 'ok',
        'neurocnl_version': '0.3.0',
        'timestamp': '2026-04-03T12:00:00Z',
        'modules': {
          'nengo': {'available': true, 'version': '4.0.0'},
        },
        'nengo_available': true,
        'mujoco_available': false,
      };

      final status = HealthStatus.fromJson(json);

      expect(status.status, 'ok');
      expect(status.disk.totalGb, 0);
      expect(status.modules['nengo']?.available, true);
      expect(status.nengoAvailable, true);
      expect(status.mujocoAvailable, false);
    });
  });
}
