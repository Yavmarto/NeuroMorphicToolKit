import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:neuro_toolkit/features/neurocnl/services/admin_token_http_client.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/feature_launch_provider.dart';

part 'neurobench_panel_provider.g.dart';

/// Shared transport so panel requests carry the launcher's admin token when
/// the backend sits behind an authenticating tunnel.
final _authedHttpProvider = Provider<AdminTokenHttpClient>((ref) {
  final launchContext = ref.watch(featureLaunchContextProvider);
  final client = AdminTokenHttpClient(
    adminToken: launchContext.authentication.adminToken,
    onReportError: launchContext.onReportError,
    onRecovered: launchContext.onRecovered,
  );
  ref.onDispose(client.close);
  return client;
});

/// NeuroCNL's Studio calls Neurobench's own backend directly for the
/// in-canvas benchmark panel. Both modules are mounted on the same
/// root-known host (the suite_api monolith), so this swaps NeuroCNL's own
/// `/api/neurocnl` mount for Neurobench's `/api/neurobench` mount rather
/// than resolving a second, independent backend host.
final _neurobenchBaseUrlProvider = Provider<String>((ref) {
  final backendUri = ref.watch(featureLaunchContextProvider).backendUri;
  return backendUri.replace(path: '/api/neurobench').toString();
});
const _requestTimeout = Duration(seconds: 10);

// Minimal model — only the fields needed by the panel dropdown.
class NeurobenchBenchmarkSummary {
  const NeurobenchBenchmarkSummary({
    required this.id,
    required this.name,
    required this.primaryMetric,
  });

  final String id;
  final String name;
  final String primaryMetric;

  factory NeurobenchBenchmarkSummary.fromJson(Map<String, dynamic> json) {
    final scoring =
        (json['scoring'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    return NeurobenchBenchmarkSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      primaryMetric: scoring['primary_metric'] as String? ?? 'accuracy',
    );
  }
}

class NeurobenchPanelState {
  const NeurobenchPanelState({
    this.selectedBenchmarkId,
    this.selectedTarget = 'simulation',
    this.submitting = false,
    this.activeJobId,
    this.activeJobStatus,
    this.activeResultId,
    this.resultMetrics,
    this.errorMessage,
    this.passThreshold,
  });

  final String? selectedBenchmarkId;
  final String selectedTarget;
  final bool submitting;
  final String? activeJobId;
  final String? activeJobStatus;
  final String? activeResultId;
  final Map<String, double>? resultMetrics;
  final String? errorMessage;
  final double? passThreshold;

  bool get hasResult => activeResultId != null && resultMetrics != null;

  bool get isRunning =>
      activeJobStatus == 'RUNNING' || activeJobStatus == 'PENDING';

  NeurobenchPanelState copyWith({
    String? selectedBenchmarkId,
    bool clearSelectedBenchmarkId = false,
    String? selectedTarget,
    bool? submitting,
    String? activeJobId,
    bool clearActiveJobId = false,
    String? activeJobStatus,
    bool clearActiveJobStatus = false,
    String? activeResultId,
    bool clearActiveResultId = false,
    Map<String, double>? resultMetrics,
    bool clearResultMetrics = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    double? passThreshold,
  }) {
    return NeurobenchPanelState(
      selectedBenchmarkId: clearSelectedBenchmarkId
          ? null
          : selectedBenchmarkId ?? this.selectedBenchmarkId,
      selectedTarget: selectedTarget ?? this.selectedTarget,
      submitting: submitting ?? this.submitting,
      activeJobId: clearActiveJobId ? null : activeJobId ?? this.activeJobId,
      activeJobStatus: clearActiveJobStatus
          ? null
          : activeJobStatus ?? this.activeJobStatus,
      activeResultId: clearActiveResultId
          ? null
          : activeResultId ?? this.activeResultId,
      resultMetrics: clearResultMetrics
          ? null
          : resultMetrics ?? this.resultMetrics,
      errorMessage: clearErrorMessage
          ? null
          : errorMessage ?? this.errorMessage,
      passThreshold: passThreshold ?? this.passThreshold,
    );
  }
}

final neurobenchBenchmarksProvider =
    FutureProvider<List<NeurobenchBenchmarkSummary>>((ref) async {
      final uri = Uri.parse(
        '${ref.read(_neurobenchBaseUrlProvider)}/benchmarks',
      );
      final response = await ref.read(_authedHttpProvider).get(uri);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body) as List<dynamic>;
        return data
            .map(
              (e) => NeurobenchBenchmarkSummary.fromJson(
                e as Map<String, dynamic>,
              ),
            )
            .toList();
      }
      throw Exception('Neurobench unavailable (${response.statusCode})');
    });

@riverpod
class NeurobenchPanelController extends _$NeurobenchPanelController {
  Timer? _pollTimer;
  int _pollFailures = 0;
  bool _isPolling = false;

  @override
  NeurobenchPanelState build() {
    ref.onDispose(() {
      _pollTimer?.cancel();
    });
    return const NeurobenchPanelState();
  }

  void selectBenchmark(String? id) {
    state = state.copyWith(
      selectedBenchmarkId: id,
      clearErrorMessage: true,
      clearResultMetrics: true,
      clearActiveResultId: true,
      clearActiveJobId: true,
      clearActiveJobStatus: true,
    );
  }

  void selectTarget(String target) {
    state = state.copyWith(selectedTarget: target, clearErrorMessage: true);
  }

  Future<void> runBenchmark(String networkContent) async {
    final benchmarkId = state.selectedBenchmarkId;
    if (benchmarkId == null || state.submitting || state.isRunning) return;

    if (networkContent.trim().isEmpty) {
      state = state.copyWith(
        errorMessage: 'The editor is empty. Write a CNL spec first.',
      );
      return;
    }

    state = state.copyWith(
      submitting: true,
      clearErrorMessage: true,
      clearResultMetrics: true,
      clearActiveResultId: true,
    );

    try {
      final uri = Uri.parse('${ref.read(_neurobenchBaseUrlProvider)}/run');
      final body = json.encode({
        'benchmark_id': benchmarkId,
        'network_content': networkContent,
        'target': state.selectedTarget,
      });
      final response = await ref
          .read(_authedHttpProvider)
          .post(uri, headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(_requestTimeout);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final jobId = data['job_id'] as String;
        _pollFailures = 0;
        state = state.copyWith(
          submitting: false,
          activeJobId: jobId,
          activeJobStatus: 'PENDING',
        );
        _startPolling(jobId);
      } else {
        state = state.copyWith(
          submitting: false,
          errorMessage: 'Failed to queue run: ${response.body}',
        );
      }
    } catch (e) {
      state = state.copyWith(
        submitting: false,
        errorMessage: 'Cannot reach Neurobench backend: $e',
      );
    }
  }

  void _startPolling(String jobId) {
    _pollTimer?.cancel();
    _isPolling = false;
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (_isPolling) return;
      _isPolling = true;
      unawaited(_pollJob(jobId).whenComplete(() => _isPolling = false));
    });
  }

  Future<void> _pollJob(String jobId) async {
    try {
      final uri = Uri.parse(
        '${ref.read(_neurobenchBaseUrlProvider)}/run/$jobId',
      );
      final response = await ref
          .read(_authedHttpProvider)
          .get(uri)
          .timeout(_requestTimeout);
      if (response.statusCode != 200) {
        _handlePollFailure('Job not found (${response.statusCode})');
        return;
      }
      _pollFailures = 0;
      final job = json.decode(response.body) as Map<String, dynamic>;
      final status = (job['status'] as String?)?.toUpperCase() ?? 'PENDING';
      final resultId = job['result_id'] as String?;
      final error = job['error'] as String?;

      state = state.copyWith(
        activeJobStatus: status,
        activeResultId: resultId,
        clearErrorMessage: true,
      );

      if (status == 'COMPLETED' && resultId != null) {
        _pollTimer?.cancel();
        await _fetchResult(resultId);
      } else if (status == 'FAILED') {
        _pollTimer?.cancel();
        state = state.copyWith(
          errorMessage: error ?? 'Benchmark run failed.',
          clearActiveJobStatus: false,
        );
      } else if (status == 'CANCELLED') {
        _pollTimer?.cancel();
      }
    } catch (e) {
      _handlePollFailure('Poll error: $e');
    }
  }

  void _handlePollFailure(String message) {
    _pollFailures++;
    if (_pollFailures >= 3) {
      _pollTimer?.cancel();
      _pollFailures = 0;
      state = state.copyWith(
        clearActiveJobId: true,
        clearActiveJobStatus: true,
        errorMessage: 'Lost contact with Neurobench backend.',
      );
    } else {
      state = state.copyWith(errorMessage: message);
    }
  }

  Future<void> _fetchResult(String resultId) async {
    try {
      final uri = Uri.parse(
        '${ref.read(_neurobenchBaseUrlProvider)}/results/$resultId',
      );
      final response = await ref
          .read(_authedHttpProvider)
          .get(uri)
          .timeout(_requestTimeout);
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final rawMetrics =
            (data['metrics'] as Map<String, dynamic>?) ??
            const <String, dynamic>{};
        final metrics = <String, double>{};
        for (final entry in rawMetrics.entries) {
          if (entry.value is num) {
            metrics[entry.key] = (entry.value as num).toDouble();
          }
        }
        state = state.copyWith(resultMetrics: metrics);
      }
    } catch (e) {
      debugPrint('Failed to parse benchmark result metrics: $e');
    }
  }
}

/// Backward-compat alias.
final neurobenchPanelProvider = neurobenchPanelControllerProvider;
