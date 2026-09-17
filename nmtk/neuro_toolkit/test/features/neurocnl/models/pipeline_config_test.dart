import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_config.dart';

void main() {
  group('PipelineConfig defaults', () {
    test('default instance has expected field values', () {
      const cfg = PipelineConfig();
      expect(cfg.epochs, 50);
      expect(cfg.learningRate, closeTo(1e-3, 1e-10));
      expect(cfg.optimizer, PipelineOptimizer.adam);
      expect(cfg.batchSize, 32);
      expect(cfg.runEvaluation, isTrue);
      expect(cfg.exportNir, isFalse);
      expect(cfg.evalMetrics, equals(const ['accuracy', 'loss']));
      expect(cfg.generatePyDownload, isTrue);
    });
  });

  group('PipelineConfig.toJson()', () {
    test('serialises with snake_case keys', () {
      const cfg = PipelineConfig();
      final json = cfg.toJson();
      expect(json.containsKey('epochs'), isTrue);
      expect(json.containsKey('learning_rate'), isTrue);
      expect(json.containsKey('optimizer'), isTrue);
      expect(json.containsKey('batch_size'), isTrue);
      expect(json.containsKey('run_evaluation'), isTrue);
      expect(json.containsKey('export_nir'), isTrue);
      expect(json, containsPair('eval_metrics', const ['accuracy', 'loss']));
      expect(json, containsPair('generate_py_download', true));
      // dataset and framework are NOT in this model — provided by workspaceProvider
      expect(json.containsKey('dataset'), isFalse);
      expect(json.containsKey('framework'), isFalse);
    });

    test('optimizer serialises to backend id', () {
      const cfg = PipelineConfig(optimizer: PipelineOptimizer.sgd);
      expect(cfg.toJson()['optimizer'], 'SGD');
    });
  });

  group('PipelineConfig.fromJson()', () {
    test('round-trips through toJson()/fromJson()', () {
      const original = PipelineConfig(
        epochs: 100,
        learningRate: 5e-4,
        optimizer: PipelineOptimizer.adamw,
        batchSize: 64,
        runEvaluation: false,
        exportNir: true,
        evalMetrics: ['f1_score'],
        generatePyDownload: false,
      );
      final roundTripped = PipelineConfig.fromJson(original.toJson());
      expect(roundTripped, equals(original));
      expect(roundTripped.evalMetrics, equals(const ['f1_score']));
      expect(roundTripped.generatePyDownload, isFalse);
    });

    test('missing keys fall back to defaults', () {
      final cfg = PipelineConfig.fromJson(<String, dynamic>{});
      expect(cfg.epochs, 50);
      expect(cfg.optimizer, PipelineOptimizer.adam);
    });
  });

  group('PipelineConfig.copyWith()', () {
    test('copies with single field overridden', () {
      const original = PipelineConfig();
      final copy = original.copyWith(epochs: 200);
      expect(copy.epochs, 200);
      expect(copy.batchSize, original.batchSize);
      expect(copy.optimizer, original.optimizer);
    });

    test('original is unchanged after copyWith', () {
      const original = PipelineConfig(epochs: 50);
      original.copyWith(epochs: 999);
      expect(original.epochs, 50);
    });
  });

  group('PipelineOptimizer', () {
    test('fromBackendId resolves all known ids', () {
      expect(PipelineOptimizer.fromBackendId('Adam'), PipelineOptimizer.adam);
      expect(PipelineOptimizer.fromBackendId('SGD'), PipelineOptimizer.sgd);
      expect(PipelineOptimizer.fromBackendId('AdamW'), PipelineOptimizer.adamw);
    });
  });

  group('TrainingStrategy and LossFunction', () {
    test('defaults include trainingStrategy and lossFunction', () {
      final cfg = const PipelineConfig();
      expect(cfg.trainingStrategy, TrainingStrategy.surrogateGradient);
      expect(cfg.lossFunction, LossFunction.mseCount);
    });

    test('toJson includes training_strategy and loss_function', () {
      final json = const PipelineConfig().toJson();
      expect(json['training_strategy'], 'surrogate_gradient');
      expect(json['loss_function'], 'mse_count');
    });

    test('fromJson round-trips training_strategy and loss_function', () {
      final original = const PipelineConfig(
        trainingStrategy: TrainingStrategy.bptt,
        lossFunction: LossFunction.crossEntropy,
      );
      final decoded = PipelineConfig.fromJson(original.toJson());
      expect(decoded.trainingStrategy, TrainingStrategy.bptt);
      expect(decoded.lossFunction, LossFunction.crossEntropy);
    });
  });
}
