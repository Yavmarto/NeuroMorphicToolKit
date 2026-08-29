import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';
import 'package:neuro_toolkit/features/neurobench/services/api_client.dart';

part 'benchmarks_provider.g.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final benchmarksProvider = FutureProvider<List<BenchmarkDefinition>>((
  ref,
) async {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.getBenchmarks();
});

@riverpod
class ActiveBenchmarkId extends _$ActiveBenchmarkId {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

@riverpod
class SelectedBaselineId extends _$SelectedBaselineId {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

@riverpod
class SelectedResultId extends _$SelectedResultId {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

@riverpod
class ActiveJobId extends _$ActiveJobId {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

final activeBenchmarkProvider = Provider<BenchmarkDefinition?>((ref) {
  final benchmarks = ref.watch(benchmarksProvider).value ?? [];
  final activeId = ref.watch(activeBenchmarkIdProvider);
  if (activeId == null) return null;
  for (final benchmark in benchmarks) {
    if (benchmark.id == activeId) {
      return benchmark;
    }
  }
  return null;
});

final benchmarkResultsProvider =
    FutureProvider.family<List<BenchmarkResult>, String>((
  ref,
  benchmarkId,
) async {
  final apiClient = ref.watch(apiClientProvider);
  final allResults = await apiClient.getResults();
  return allResults.where((r) => r.benchmarkId == benchmarkId).toList();
});

final activeBenchmarkResultsProvider = FutureProvider<List<BenchmarkResult>>((
  ref,
) async {
  final activeId = ref.watch(activeBenchmarkIdProvider);
  if (activeId == null) return [];
  return ref.watch(benchmarkResultsProvider(activeId).future);
});

final baselinesProvider = FutureProvider<List<BenchmarkResult>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  return apiClient.getBaselines();
});

final activeBaselineProvider = Provider<BenchmarkResult?>((ref) {
  final activeId = ref.watch(activeBenchmarkIdProvider);
  final selectedBaselineId = ref.watch(selectedBaselineIdProvider);
  final baselinesAsync = ref.watch(baselinesProvider);
  final baselines = baselinesAsync.when(
    data: (data) => data,
    loading: () => <BenchmarkResult>[],
    error: (_, _) => <BenchmarkResult>[],
  );
  if (activeId == null) return null;
  final matches = baselines.where((b) => b.benchmarkId == activeId).toList();
  if (matches.isEmpty) return null;
  if (selectedBaselineId != null) {
    for (final baseline in matches) {
      if (baseline.id == selectedBaselineId) {
        return baseline;
      }
    }
  }
  return matches.last;
});

final activeComparisonResultProvider = Provider<BenchmarkResult?>((ref) {
  final selectedResultId = ref.watch(selectedResultIdProvider);
  final resultsAsync = ref.watch(activeBenchmarkResultsProvider);

  return resultsAsync.when(
    data: (results) {
      if (results.isEmpty) {
        return null;
      }
      if (selectedResultId != null) {
        for (final result in results) {
          if (result.id == selectedResultId) {
            return result;
          }
        }
      }
      return results.last;
    },
    loading: () => null,
    error: (_, _) => null,
  );
});

final activeDiffProvider = FutureProvider<DiffResult?>((ref) async {
  final activeId = ref.watch(activeBenchmarkIdProvider);
  final currentResult = ref.watch(activeComparisonResultProvider);
  final baseline = ref.watch(activeBaselineProvider);

  if (activeId == null || currentResult == null || baseline == null) {
    return null;
  }
  final apiClient = ref.watch(apiClientProvider);

  try {
    return await apiClient.compareResults(baseline.id, currentResult.id);
  } catch (e) {
    return null;
  }
});
