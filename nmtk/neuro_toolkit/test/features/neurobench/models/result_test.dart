import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';

void main() {
  group('BenchmarkResult.fromJson', () {
    test('parses metric_provenance field', () {
      final json = <String, dynamic>{
        'id': 'r1',
        'benchmark_id': 'b1',
        'network_spec_hash': 'hash',
        'timestamp': '2026-01-01T00:00:00Z',
        'params': <String, dynamic>{},
        'metrics': <String, dynamic>{'accuracy': 0.9},
        'wall_time_seconds': 1.0,
        'seed': 42,
        'metric_provenance': 'on_device',
      };
      final result = BenchmarkResult.fromJson(json);
      expect(result.metricProvenance, equals('on_device'));
    });

    test('skips null metric placeholders from hardware-pending runs', () {
      final json = <String, dynamic>{
        'id': 'r1',
        'benchmark_id': 'yolov8n_axelera',
        'network_spec_hash': 'hash',
        'timestamp': '2026-01-01T00:00:00Z',
        'params': <String, dynamic>{},
        'metrics': <String, dynamic>{
          'cpu_latency_ms': null,
          'aipu_latency_ms': null,
          'speedup': 1.2,
        },
        'wall_time_seconds': 1.0,
        'seed': 42,
      };
      final result = BenchmarkResult.fromJson(json);
      expect(result.metrics.keys, ['speedup']);
      expect(result.metrics['speedup'], 1.2);
    });

    test('defaults to cpu_estimated when metric_provenance absent', () {
      final json = <String, dynamic>{
        'id': 'r1',
        'benchmark_id': 'b1',
        'network_spec_hash': 'hash',
        'timestamp': '2026-01-01T00:00:00Z',
        'params': <String, dynamic>{},
        'metrics': <String, dynamic>{'accuracy': 0.9},
        'wall_time_seconds': 1.0,
        'seed': 42,
        // no metric_provenance key
      };
      final result = BenchmarkResult.fromJson(json);
      expect(result.metricProvenance, equals('cpu_estimated'));
    });
  });
}
