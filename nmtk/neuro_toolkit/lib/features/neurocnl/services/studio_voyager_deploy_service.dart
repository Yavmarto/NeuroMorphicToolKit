import 'package:neuro_toolkit/features/neurobench/models/benchmark_job.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/services/api_client.dart';

/// NeuroBench `/run` client for the fixed YOLOv8n Voyager conventional-accelerator
/// benchmark (CEL-377). No CNL network input — compile+benchmark only.
class StudioVoyagerDeployService {
  StudioVoyagerDeployService({required ApiClient apiClient})
    : _apiClient = apiClient;

  final ApiClient _apiClient;

  static const String benchmarkId = 'yolov8n_axelera';
  static const String targetId = 'voyager_axelera';

  Future<String> submitBenchmark() {
    return _apiClient.submitBenchmarkRun(
      BenchmarkRunRequest(
        benchmarkId: benchmarkId,
        target: targetId,
        params: const <String, dynamic>{},
      ),
    );
  }

  Future<BenchmarkJob> fetchJob(String jobId) =>
      _apiClient.getBenchmarkJob(jobId);

  Future<BenchmarkResult> fetchResult(String jobId) =>
      _apiClient.getBenchmarkRunResult(jobId);
}

/// Parses NeuroBench result metrics, dropping null placeholders the backend
/// emits for hardware-pending Voyager runs.
Map<String, double> parseBenchmarkMetrics(Map<String, dynamic> raw) {
  final metrics = <String, double>{};
  for (final entry in raw.entries) {
    if (entry.value is num) {
      metrics[entry.key] = (entry.value as num).toDouble();
    }
  }
  return metrics;
}

bool benchmarkResultIsHardwarePending(BenchmarkResult result) {
  return result.spikeData?['hardware_status'] == 'pending_hardware';
}
