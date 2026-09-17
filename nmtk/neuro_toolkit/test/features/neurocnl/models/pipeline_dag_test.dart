import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_dag.dart';

void main() {
  group('PipelineDAG', () {
    test('copyWithNode adds node', () {
      const dag = PipelineDAG();
      const node = PipelineDagNode(
        id: 'n1',
        type: PipelineDagNodeType.dataLoader,
        x: 10,
        y: 20,
      );
      final updated = dag.copyWithNode(node);
      expect(updated.nodes.length, 1);
      expect(updated.nodes.first.id, 'n1');
    });

    test('copyWithNode upserts existing node', () {
      const node = PipelineDagNode(
        id: 'n1',
        type: PipelineDagNodeType.dataLoader,
        x: 10,
        y: 20,
      );
      final dag = const PipelineDAG(nodes: [node]);
      final updated = dag.copyWithNode(node.copyWith(x: 99));
      expect(updated.nodes.length, 1);
      expect(updated.nodes.first.x, 99);
    });

    test('withoutNode removes node and its edges', () {
      const node1 = PipelineDagNode(
        id: 'n1',
        type: PipelineDagNodeType.dataLoader,
      );
      const node2 = PipelineDagNode(
        id: 'n2',
        type: PipelineDagNodeType.forwardPass,
      );
      const edge = PipelineDagEdge(
        id: 'e1',
        sourceNodeId: 'n1',
        sourcePort: 'data',
        targetNodeId: 'n2',
        targetPort: 'data',
      );
      final dag = const PipelineDAG(nodes: [node1, node2], edges: [edge]);
      final updated = dag.withoutNode('n1');
      expect(updated.nodes.length, 1);
      expect(updated.edges, isEmpty);
    });

    test('movedNode updates position by delta', () {
      const node = PipelineDagNode(
        id: 'n1',
        type: PipelineDagNodeType.dataLoader,
        x: 100,
        y: 100,
      );
      final dag = const PipelineDAG(nodes: [node]);
      final updated = dag.movedNode('n1', 50, -30);
      expect(updated.nodes.first.x, 150);
      expect(updated.nodes.first.y, 70);
    });
  });

  group('PipelinePhases', () {
    test('dagFor returns correct phase', () {
      const train = PipelineDAG(
        nodes: [PipelineDagNode(id: 't', type: PipelineDagNodeType.dataLoader)],
      );
      const phases = PipelinePhases(train: train);
      expect(phases.dagFor(PipelinePhaseId.train).nodes.first.id, 't');
      expect(phases.dagFor(PipelinePhaseId.eval).nodes, isEmpty);
    });

    test('copyWith preserves unchanged phases', () {
      const train = PipelineDAG(
        nodes: [PipelineDagNode(id: 't', type: PipelineDagNodeType.dataLoader)],
      );
      const phases = PipelinePhases(train: train);
      final updated = phases.copyWith(
        eval: const PipelineDAG(
          nodes: [
            PipelineDagNode(id: 'e', type: PipelineDagNodeType.testLoader),
          ],
        ),
      );
      expect(updated.train.nodes.first.id, 't');
      expect(updated.eval.nodes.first.id, 'e');
    });
  });

  group('PipelineDagNode serialization', () {
    test('toJson / fromJson round-trips', () {
      const node = PipelineDagNode(
        id: 'x',
        type: PipelineDagNodeType.adamOptimiser,
        customComponentId: 'custom_adam_12345678',
        x: 100,
        y: 200,
        parameters: {'lr': 0.001},
      );
      final decoded = PipelineDagNode.fromJson(node.toJson());
      expect(decoded.id, 'x');
      expect(decoded.type, PipelineDagNodeType.adamOptimiser);
      expect(decoded.customComponentId, 'custom_adam_12345678');
      expect(decoded.x, 100);
      expect(
        (decoded.parameters['lr'] as num).toDouble(),
        closeTo(0.001, 1e-9),
      );
    });
  });

  group('PipelineDagNodeType.validationLoop', () {
    test('label is Validation Loop', () {
      expect(PipelineDagNodeType.validationLoop.label, 'Validation Loop');
    });

    test('category is timeControl', () {
      expect(
        PipelineDagNodeType.validationLoop.category,
        PipelineDagCategory.timeControl,
      );
    });

    test('defaultParameters has the expected keys and defaults', () {
      final params = PipelineDagNodeType.validationLoop.defaultParameters;
      expect(
        params.containsKey('epochs'),
        isFalse,
        reason:
            'epochs is owned by the outer pipeline config only, to avoid a '
            'second, divergent source of truth for epoch count',
      );
      expect(params['every_n_epochs'], 1);
      expect(params['save_best_checkpoint'], true);
      expect(params['checkpoint_metric'], 'val_accuracy');
      expect(params['checkpoint_mode'], 'max');
    });

    test('inputPorts has model and optional val_data', () {
      final ports = PipelineDagNodeType.validationLoop.inputPorts;
      expect(ports.map((p) => p.id), containsAll(['model', 'val_data']));
      final model = ports.firstWhere((p) => p.id == 'model');
      expect(model.type, PortType.model);
      expect(model.optional, isFalse);
      final valData = ports.firstWhere((p) => p.id == 'val_data');
      expect(valData.type, PortType.data);
      expect(valData.optional, isTrue);
    });

    test('outputPorts has metrics', () {
      final ports = PipelineDagNodeType.validationLoop.outputPorts;
      expect(ports, hasLength(1));
      expect(ports.first.id, 'metrics');
      expect(ports.first.type, PortType.metrics);
    });

    test('toJson / fromJson round-trip preserves type: validationLoop', () {
      final node = PipelineDagNode(
        id: 'vl1',
        type: PipelineDagNodeType.validationLoop,
        parameters: Map<String, dynamic>.from(
          PipelineDagNodeType.validationLoop.defaultParameters,
        ),
      );
      final json = node.toJson();
      expect(json['type'], 'validationLoop');
      final decoded = PipelineDagNode.fromJson(json);
      expect(decoded.type, PipelineDagNodeType.validationLoop);
      expect(decoded.parameters['checkpoint_metric'], 'val_accuracy');
    });
  });

  group('PipelineDagNodeType.lbiOptimizer', () {
    test('label is Linearized Bregman Iteration', () {
      expect(
        PipelineDagNodeType.lbiOptimizer.label,
        'Linearized Bregman Iteration',
      );
    });

    test('category is optimiser', () {
      expect(
        PipelineDagNodeType.lbiOptimizer.category,
        PipelineDagCategory.optimiser,
      );
    });

    test('defaultParameters has the expected keys and defaults', () {
      final params = PipelineDagNodeType.lbiOptimizer.defaultParameters;
      expect(params['lr'], 0.001);
      expect(params['lambda_reg'], 0.01);
      expect(params['kappa'], 10.0);
    });

    test('inputPorts has gradients', () {
      final ports = PipelineDagNodeType.lbiOptimizer.inputPorts;
      expect(ports, hasLength(1));
      expect(ports.first.id, 'gradients');
      expect(ports.first.type, PortType.gradients);
      expect(ports.first.optional, isFalse);
    });

    test('outputPorts has model', () {
      final ports = PipelineDagNodeType.lbiOptimizer.outputPorts;
      expect(ports, hasLength(1));
      expect(ports.first.id, 'model');
      expect(ports.first.type, PortType.model);
    });

    test('toJson / fromJson round-trip preserves type: lbiOptimizer', () {
      final node = PipelineDagNode(
        id: 'lbi1',
        type: PipelineDagNodeType.lbiOptimizer,
        parameters: Map<String, dynamic>.from(
          PipelineDagNodeType.lbiOptimizer.defaultParameters,
        ),
      );
      final json = node.toJson();
      expect(json['type'], 'lbiOptimizer');
      final decoded = PipelineDagNode.fromJson(json);
      expect(decoded.type, PipelineDagNodeType.lbiOptimizer);
      expect(decoded.parameters['lr'], 0.001);
      expect(decoded.parameters['lambda_reg'], 0.01);
      expect(decoded.parameters['kappa'], 10.0);
    });
  });

  group('PipelineDagNodeType.customGradientStep', () {
    test('label is Custom Gradient Step', () {
      expect(
        PipelineDagNodeType.customGradientStep.label,
        'Custom Gradient Step',
      );
    });

    test('category is backward', () {
      expect(
        PipelineDagNodeType.customGradientStep.category,
        PipelineDagCategory.backward,
      );
    });

    test('defaultParameters has the expected keys and defaults', () {
      final params = PipelineDagNodeType.customGradientStep.defaultParameters;
      expect(params['expression'], '');
      expect(params['clip_value'], 0.0);
    });

    test('inputPorts has loss', () {
      final ports = PipelineDagNodeType.customGradientStep.inputPorts;
      expect(ports, hasLength(1));
      expect(ports.first.id, 'loss');
      expect(ports.first.type, PortType.loss);
      expect(ports.first.optional, isFalse);
    });

    test('outputPorts has gradients', () {
      final ports = PipelineDagNodeType.customGradientStep.outputPorts;
      expect(ports, hasLength(1));
      expect(ports.first.id, 'gradients');
      expect(ports.first.type, PortType.gradients);
    });

    test('toJson / fromJson round-trip preserves type: customGradientStep', () {
      final node = PipelineDagNode(
        id: 'cgs1',
        type: PipelineDagNodeType.customGradientStep,
        parameters: Map<String, dynamic>.from(
          PipelineDagNodeType.customGradientStep.defaultParameters,
        ),
      );
      final json = node.toJson();
      expect(json['type'], 'customGradientStep');
      final decoded = PipelineDagNode.fromJson(json);
      expect(decoded.type, PipelineDagNodeType.customGradientStep);
      expect(decoded.parameters['expression'], '');
      expect(decoded.parameters['clip_value'], 0.0);
    });
  });

  group('PipelineDagNodeType.spikeDomainFilter', () {
    test('label is Spike-Domain Filter', () {
      expect(
        PipelineDagNodeType.spikeDomainFilter.label,
        'Spike-Domain Filter',
      );
    });

    test('category is network', () {
      expect(
        PipelineDagNodeType.spikeDomainFilter.category,
        PipelineDagCategory.network,
      );
    });

    test('defaultParameters has the expected keys and defaults', () {
      final params = PipelineDagNodeType.spikeDomainFilter.defaultParameters;
      expect(params['filter_type'], 'threshold');
      expect(params['window'], 5);
      expect(params['threshold'], 0.5);
    });

    test('inputPorts has spikes', () {
      final ports = PipelineDagNodeType.spikeDomainFilter.inputPorts;
      expect(ports, hasLength(1));
      expect(ports.first.id, 'spikes');
      expect(ports.first.type, PortType.spikes);
      expect(ports.first.optional, isFalse);
    });

    test('outputPorts has spikes', () {
      final ports = PipelineDagNodeType.spikeDomainFilter.outputPorts;
      expect(ports, hasLength(1));
      expect(ports.first.id, 'spikes');
      expect(ports.first.type, PortType.spikes);
    });

    test('toJson / fromJson round-trip preserves type: spikeDomainFilter', () {
      final node = PipelineDagNode(
        id: 'sdf1',
        type: PipelineDagNodeType.spikeDomainFilter,
        parameters: Map<String, dynamic>.from(
          PipelineDagNodeType.spikeDomainFilter.defaultParameters,
        ),
      );
      final json = node.toJson();
      expect(json['type'], 'spikeDomainFilter');
      final decoded = PipelineDagNode.fromJson(json);
      expect(decoded.type, PipelineDagNodeType.spikeDomainFilter);
      expect(decoded.parameters['filter_type'], 'threshold');
      expect(decoded.parameters['window'], 5);
      expect(decoded.parameters['threshold'], 0.5);
    });
  });

  group('PipelineDagNodeType.testLoader (Task 6)', () {
    test('defaultParameters includes load_best_checkpoint: true', () {
      final params = PipelineDagNodeType.testLoader.defaultParameters;
      expect(params['load_best_checkpoint'], true);
      // Existing keys must be untouched by the new addition.
      expect(params['batch_size'], 32);
      expect(params['shuffle'], false);
      expect(params['format'], 'auto');
    });
  });

  group('earlyStopping / reduceLROnPlateau metric port', () {
    test('earlyStopping declares an optional metrics input port', () {
      final ports = PipelineDagNodeType.earlyStopping.inputPorts;
      expect(ports.any((p) => p.id == 'model'), isTrue);
      final metric = ports.firstWhere((p) => p.id == 'metric');
      expect(metric.type, PortType.metrics);
      expect(metric.optional, isTrue);
    });

    test('reduceLROnPlateau declares an optional metrics input port', () {
      final ports = PipelineDagNodeType.reduceLROnPlateau.inputPorts;
      expect(ports.any((p) => p.id == 'model'), isTrue);
      final metric = ports.firstWhere((p) => p.id == 'metric');
      expect(metric.type, PortType.metrics);
      expect(metric.optional, isTrue);
    });

    test(
      'stepLR/cosineAnnealingLR/exponentialLR/weightClip stay model-only',
      () {
        for (final type in [
          PipelineDagNodeType.stepLR,
          PipelineDagNodeType.cosineAnnealingLR,
          PipelineDagNodeType.exponentialLR,
          PipelineDagNodeType.weightClip,
        ]) {
          final ports = type.inputPorts;
          expect(ports, hasLength(1));
          expect(ports.first.id, 'model');
        }
      },
    );
  });

  group('buildDefaultPhases', () {
    test('snntorch_sim produces non-empty train DAG', () {
      final phases = buildDefaultPhases(
        frameworks: ['snntorch_sim'],
        dataset: 'nmnist',
      );
      expect(phases.train.nodes, isNotEmpty);
      expect(
        phases.train.nodes.any((n) => n.type == PipelineDagNodeType.dataLoader),
        isTrue,
      );
      expect(
        phases.train.nodes.any(
          (n) => n.type == PipelineDagNodeType.adamOptimiser,
        ),
        isTrue,
      );
    });

    test('default phases have edges connecting nodes', () {
      final phases = buildDefaultPhases(
        frameworks: ['snntorch_sim'],
        dataset: 'nmnist',
      );
      expect(phases.train.edges, isNotEmpty);
    });

    test('snntorch_sim train phase includes a validationLoop with its own '
        'val-loader (no cross-phase edge into eval)', () {
      final phases = buildDefaultPhases(
        frameworks: ['snntorch_sim'],
        dataset: 'nmnist',
      );
      final validationLoopNode = phases.train.nodes.firstWhere(
        (n) => n.type == PipelineDagNodeType.validationLoop,
      );
      final valLoaderNodes = phases.train.nodes.where(
        (n) => n.type == PipelineDagNodeType.testLoader,
      );
      expect(
        valLoaderNodes,
        isNotEmpty,
        reason:
            'Train phase needs its own val-loader node since cross-phase '
            'edges into the eval phase are not supported.',
      );

      final edgesIntoValidationLoop = phases.train.edges.where(
        (e) => e.targetNodeId == validationLoopNode.id,
      );
      expect(
        edgesIntoValidationLoop.any((e) => e.targetPort == 'val_data'),
        isTrue,
      );
      expect(
        edgesIntoValidationLoop.any((e) => e.targetPort == 'model'),
        isTrue,
      );
    });

    test('snntorch_sim produces non-empty eval DAG', () {
      final phases = buildDefaultPhases(
        frameworks: ['snntorch_sim'],
        dataset: 'nmnist',
      );
      expect(phases.eval.nodes, isNotEmpty);
      expect(phases.eval.edges, isNotEmpty);
    });

    test('lava produces non-empty eval DAG', () {
      final phases = buildDefaultPhases(frameworks: ['lava'], dataset: null);
      expect(phases.eval.nodes, isNotEmpty);
      expect(phases.eval.edges, isNotEmpty);
      expect(
        phases.eval.nodes.any(
          (n) => n.type == PipelineDagNodeType.accuracyMetric,
        ),
        isTrue,
      );
    });

    test('generic framework list produces non-empty eval DAG', () {
      final phases = buildDefaultPhases(
        frameworks: ['some_unknown_framework'],
        dataset: null,
      );
      expect(phases.eval.nodes, isNotEmpty);
      expect(phases.eval.edges, isNotEmpty);
      expect(
        phases.eval.nodes.any(
          (n) => n.type == PipelineDagNodeType.accuracyMetric,
        ),
        isTrue,
      );
    });
  });

  group('pipelineNodeTypesFor', () {
    // Reproduces the filter that used to be inlined in canvas_screen.dart, so a
    // drift between the bottom-bar palette and the port-anchored palette shows
    // up here rather than as two palettes offering different node sets.
    List<PipelineDagNodeType> reference(
      PipelinePhaseId phase,
      Set<PipelineDagCategory> categories,
      Set<String> platforms,
    ) {
      return PipelineDagNodeType.values.where((PipelineDagNodeType t) {
        final bool frameworkOk =
            t.frameworks.isEmpty || t.frameworks.any(platforms.contains);
        return frameworkOk && categories.contains(t.category);
      }).toList();
    }

    test('train offers the nine training categories', () {
      const platforms = <String>{'snntorch_sim'};
      expect(
        pipelineNodeTypesFor(PipelinePhaseId.train, platforms),
        reference(PipelinePhaseId.train, const <PipelineDagCategory>{
          PipelineDagCategory.data,
          PipelineDagCategory.timeControl,
          PipelineDagCategory.network,
          PipelineDagCategory.loss,
          PipelineDagCategory.backward,
          PipelineDagCategory.optimiser,
          PipelineDagCategory.scheduler,
          PipelineDagCategory.lava,
          PipelineDagCategory.export,
        }, platforms),
      );
    });

    test('eval offers metrics but not loss or optimisers', () {
      final types = pipelineNodeTypesFor(PipelinePhaseId.eval, const {
        'snntorch_sim',
      });
      expect(
        types.map((t) => t.category),
        contains(PipelineDagCategory.metrics),
      );
      expect(
        types.map((t) => t.category),
        isNot(contains(PipelineDagCategory.loss)),
      );
      expect(
        types.map((t) => t.category),
        isNot(contains(PipelineDagCategory.optimiser)),
      );
    });

    test('a framework-gated type only appears for its own platform', () {
      final PipelineDagNodeType gated = PipelineDagNodeType.values.firstWhere(
        (PipelineDagNodeType t) =>
            t.frameworks.isNotEmpty && t.category == PipelineDagCategory.lava,
      );

      expect(
        pipelineNodeTypesFor(PipelinePhaseId.train, gated.frameworks),
        contains(gated),
      );
      expect(
        pipelineNodeTypesFor(PipelinePhaseId.train, const {'no_such_platform'}),
        isNot(contains(gated)),
      );
    });

    test('an output-side candidate list excludes every zero-input type', () {
      // The direction-only filter the port-anchored palette applies: pressing
      // `+` on an output must never offer a source-only node like Data Loader.
      final candidates = pipelineNodeTypesFor(PipelinePhaseId.train, const {
        'snntorch_sim',
      }).where((PipelineDagNodeType t) => t.inputPorts.isNotEmpty).toList();

      expect(candidates, isNot(contains(PipelineDagNodeType.dataLoader)));
      expect(candidates, contains(PipelineDagNodeType.spikeEncoder));
      expect(
        candidates.every((PipelineDagNodeType t) => t.inputPorts.isNotEmpty),
        isTrue,
      );
    });

    test('an input-side candidate list excludes every zero-output type', () {
      final candidates = pipelineNodeTypesFor(PipelinePhaseId.train, const {
        'snntorch_sim',
      }).where((PipelineDagNodeType t) => t.outputPorts.isNotEmpty).toList();

      expect(candidates, contains(PipelineDagNodeType.dataLoader));
      expect(
        candidates.every((PipelineDagNodeType t) => t.outputPorts.isNotEmpty),
        isTrue,
      );
    });
  });
}
