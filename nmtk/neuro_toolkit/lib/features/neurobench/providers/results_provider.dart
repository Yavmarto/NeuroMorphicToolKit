import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/providers/benchmarks_provider.dart';

final resultsProvider = FutureProvider<List<BenchmarkResult>>((ref) async {
  final activeBenchmark = ref.watch(activeBenchmarkProvider);
  if (activeBenchmark == null) return <BenchmarkResult>[];

  final apiClient = ref.watch(apiClientProvider);
  final allResults = await apiClient.getResults();

  // Filter results for the active benchmark
  return allResults.where((r) => r.benchmarkId == activeBenchmark.id).toList();
});

final latestResultProvider = Provider<BenchmarkResult?>((ref) {
  final resultsAsync = ref.watch(resultsProvider);
  return resultsAsync.when(
    data: (results) => results.isEmpty ? null : results.last,
    loading: () => null,
    error: (_, _) => null,
  );
});
