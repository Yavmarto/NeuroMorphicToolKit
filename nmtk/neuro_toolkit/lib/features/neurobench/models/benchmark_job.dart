import 'dart:convert';

enum BenchmarkJobStatus {
  pending,
  running,
  completed,
  failed,
  cancelled;

  factory BenchmarkJobStatus.fromJson(String value) {
    return BenchmarkJobStatus.values.firstWhere(
      (status) => status.name.toUpperCase() == value.toUpperCase(),
      orElse: () => BenchmarkJobStatus.pending,
    );
  }

  bool get isTerminal => switch (this) {
        BenchmarkJobStatus.completed ||
        BenchmarkJobStatus.failed ||
        BenchmarkJobStatus.cancelled =>
          true,
        BenchmarkJobStatus.pending || BenchmarkJobStatus.running => false,
      };

  String get label => switch (this) {
        BenchmarkJobStatus.pending => 'Pending',
        BenchmarkJobStatus.running => 'Running',
        BenchmarkJobStatus.completed => 'Completed',
        BenchmarkJobStatus.failed => 'Failed',
        BenchmarkJobStatus.cancelled => 'Cancelled',
      };
}

class BenchmarkRunRequest {
  const BenchmarkRunRequest({
    required this.benchmarkId,
    this.networkPath,
    this.params = const <String, dynamic>{},
    this.seed,
    this.target = 'simulation',
  });

  final String benchmarkId;
  final String? networkPath;
  final Map<String, dynamic> params;
  final int? seed;
  final String target;

  Map<String, dynamic> toJson() {
    return {
      'benchmark_id': benchmarkId,
      if (networkPath != null && networkPath!.trim().isNotEmpty)
        'network_path': networkPath,
      if (params.isNotEmpty) 'params': params,
      if (seed != null) 'seed': seed,
      'target': target,
    };
  }
}

class BenchmarkRunDraft {
  const BenchmarkRunDraft({
    this.networkPath = '',
    this.paramsText = '{}',
    this.seedText = '',
    this.target = 'simulation',
  });

  final String networkPath;
  final String paramsText;
  final String seedText;
  final String target;

  BenchmarkRunDraft copyWith({
    String? networkPath,
    String? paramsText,
    String? seedText,
    String? target,
  }) {
    return BenchmarkRunDraft(
      networkPath: networkPath ?? this.networkPath,
      paramsText: paramsText ?? this.paramsText,
      seedText: seedText ?? this.seedText,
      target: target ?? this.target,
    );
  }

  factory BenchmarkRunDraft.fromDefaults({
    required String benchmarkId,
    required Map<String, dynamic> defaultParams,
  }) {
    final networkPath = defaultParams['network_path']?.toString() ??
        'examples/$benchmarkId.json';
    final seed = defaultParams['seed']?.toString() ?? '';
    final target = defaultParams['target']?.toString() ?? 'simulation';
    final params = Map<String, dynamic>.from(defaultParams)
      ..remove('network_path')
      ..remove('seed')
      ..remove('target');

    return BenchmarkRunDraft(
      networkPath: networkPath,
      seedText: seed,
      target: target,
      paramsText: const JsonEncoder.withIndent('  ').convert(params),
    );
  }
}

class BenchmarkJob {
  const BenchmarkJob({
    required this.id,
    required this.benchmarkId,
    required this.networkPath,
    required this.createdAt,
    required this.updatedAt,
    this.params,
    this.seed,
    this.status = BenchmarkJobStatus.pending,
    this.resultId,
    this.error,
  });

  final String id;
  final String benchmarkId;
  final String networkPath;
  final Map<String, dynamic>? params;
  final int? seed;
  final BenchmarkJobStatus status;
  final String? resultId;
  final String? error;
  final String createdAt;
  final String updatedAt;

  factory BenchmarkJob.fromJson(Map<String, dynamic> json) {
    return BenchmarkJob(
      id: json['id'] as String,
      benchmarkId: json['benchmark_id'] as String,
      networkPath: json['network_path'] as String,
      params: json['params'] == null
          ? null
          : Map<String, dynamic>.from(json['params'] as Map),
      seed: json['seed'] as int?,
      status: BenchmarkJobStatus.fromJson(json['status'] as String),
      resultId: json['result_id'] as String?,
      error: json['error'] as String?,
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }
}
