import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:nmtk_module_contracts/nmtk_module_contracts.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark.dart';
import 'package:neuro_toolkit/features/neurobench/models/benchmark_job.dart';
import 'package:neuro_toolkit/features/neurobench/models/result.dart';

class ApiClient {
  final String baseUrl;
  final String? apiKey;
  final http.Client _client;

  ApiClient({String? baseUrl, this.apiKey, http.Client? client})
      : baseUrl = baseUrl ??
            NmtkApiBaseUrl.resolve(
                apiPath: '/api/neurobench', defaultPort: 8003),
        _client = client ?? http.Client();

  Map<String, String> get _headers {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey != null) {
      headers['X-API-Key'] = apiKey!;
    }
    return headers;
  }

  Uri _buildUri(String path) {
    final normalizedBaseUrl = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBaseUrl$normalizedPath');
  }

  Future<List<BenchmarkDefinition>> getBenchmarks() async {
    final uri = _buildUri('/benchmarks');
    final response = await _client.get(uri, headers: _headers).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutApiException(uri.path),
        );
    if (response.statusCode == 200) {
      final List<dynamic> data;
      try {
        data = json.decode(response.body) as List<dynamic>;
      } on FormatException {
        throw MalformedResponseException(uri.path, response.body);
      }
      return data
          .map((j) => BenchmarkDefinition.fromJson(j as Map<String, dynamic>))
          .toList();
    } else {
      throw HttpApiException(response.statusCode, response.body);
    }
  }

  Future<BenchmarkDefinition> getBenchmark(String benchmarkId) async {
    final uri = _buildUri('/benchmarks/$benchmarkId');
    final response = await _client.get(uri, headers: _headers).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutApiException(uri.path),
        );
    if (response.statusCode == 200) {
      late final Map<String, dynamic> decoded;
      try {
        decoded = json.decode(response.body) as Map<String, dynamic>;
      } on FormatException {
        throw MalformedResponseException(uri.path, response.body);
      }
      return BenchmarkDefinition.fromJson(decoded);
    } else {
      throw HttpApiException(response.statusCode, response.body);
    }
  }

  Future<List<BenchmarkResult>> getResults() async {
    final uri = _buildUri('/results');
    final response = await _client.get(uri, headers: _headers).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutApiException(uri.path),
        );
    if (response.statusCode == 200) {
      final List<dynamic> data;
      try {
        data = json.decode(response.body) as List<dynamic>;
      } on FormatException {
        throw MalformedResponseException(uri.path, response.body);
      }
      return data
          .map((j) => BenchmarkResult.fromJson(j as Map<String, dynamic>))
          .toList();
    } else {
      throw HttpApiException(response.statusCode, response.body);
    }
  }

  Future<BenchmarkResult> getResult(String resultId) async {
    final uri = _buildUri('/results/$resultId');
    final response = await _client.get(uri, headers: _headers).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutApiException(uri.path),
        );
    if (response.statusCode == 200) {
      late final Map<String, dynamic> decoded;
      try {
        decoded = json.decode(response.body) as Map<String, dynamic>;
      } on FormatException {
        throw MalformedResponseException(uri.path, response.body);
      }
      return BenchmarkResult.fromJson(decoded);
    } else {
      throw HttpApiException(response.statusCode, response.body);
    }
  }

  Future<List<BenchmarkResult>> getBaselines() async {
    final uri = _buildUri('/baselines');
    final response = await _client.get(uri, headers: _headers).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutApiException(uri.path),
        );
    if (response.statusCode == 200) {
      final List<dynamic> data;
      try {
        data = json.decode(response.body) as List<dynamic>;
      } on FormatException {
        throw MalformedResponseException(uri.path, response.body);
      }
      return data
          .map((j) => BenchmarkResult.fromJson(j as Map<String, dynamic>))
          .toList();
    } else {
      throw HttpApiException(response.statusCode, response.body);
    }
  }

  Future<BenchmarkResult> saveBaseline(BenchmarkResult result) async {
    final uri = _buildUri('/baselines');
    final response = await _client
        .post(uri, headers: _headers, body: json.encode(result.toJson()))
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutApiException(uri.path),
        );
    if (response.statusCode == 200) {
      late final Map<String, dynamic> decoded;
      try {
        decoded = json.decode(response.body) as Map<String, dynamic>;
      } on FormatException {
        throw MalformedResponseException(uri.path, response.body);
      }
      return BenchmarkResult.fromJson(decoded);
    } else {
      throw HttpApiException(response.statusCode, response.body);
    }
  }

  Future<String> submitBenchmarkRun(BenchmarkRunRequest request) async {
    final uri = _buildUri('/run');
    final response = await _client
        .post(uri, headers: _headers, body: json.encode(request.toJson()))
        .timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutApiException(uri.path),
        );
    if (response.statusCode == 200) {
      late final Map<String, dynamic> data;
      try {
        data = json.decode(response.body) as Map<String, dynamic>;
      } on FormatException {
        throw MalformedResponseException(uri.path, response.body);
      }
      return data['job_id'] as String;
    } else {
      throw HttpApiException(response.statusCode, response.body);
    }
  }

  Future<BenchmarkJob> getBenchmarkJob(String jobId) async {
    final uri = _buildUri('/run/$jobId');
    final response = await _client.get(uri, headers: _headers).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutApiException(uri.path),
        );
    if (response.statusCode == 200) {
      late final Map<String, dynamic> decoded;
      try {
        decoded = json.decode(response.body) as Map<String, dynamic>;
      } on FormatException {
        throw MalformedResponseException(uri.path, response.body);
      }
      return BenchmarkJob.fromJson(decoded);
    } else {
      throw HttpApiException(response.statusCode, response.body);
    }
  }

  Future<BenchmarkResult> getBenchmarkRunResult(String jobId) async {
    final uri = _buildUri('/run/$jobId/result');
    final response = await _client.get(uri, headers: _headers).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutApiException(uri.path),
        );
    if (response.statusCode == 200) {
      late final Map<String, dynamic> decoded;
      try {
        decoded = json.decode(response.body) as Map<String, dynamic>;
      } on FormatException {
        throw MalformedResponseException(uri.path, response.body);
      }
      return BenchmarkResult.fromJson(decoded);
    } else {
      throw HttpApiException(response.statusCode, response.body);
    }
  }

  Future<bool> cancelBenchmarkRun(String jobId) async {
    final uri = _buildUri('/run/$jobId');
    final response = await _client.delete(uri, headers: _headers).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutApiException(uri.path),
        );
    if (response.statusCode == 200) {
      late final Map<String, dynamic> data;
      try {
        data = json.decode(response.body) as Map<String, dynamic>;
      } on FormatException {
        throw MalformedResponseException(uri.path, response.body);
      }
      return data['success'] as bool? ?? false;
    } else {
      throw HttpApiException(response.statusCode, response.body);
    }
  }

  Future<DiffResult> compareResults(String baselineId, String currentId) async {
    final uri = _buildUri('/compare/$baselineId/$currentId');
    final response = await _client.get(uri, headers: _headers).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutApiException(uri.path),
        );
    if (response.statusCode == 200) {
      late final Map<String, dynamic> decoded;
      try {
        decoded = json.decode(response.body) as Map<String, dynamic>;
      } on FormatException {
        throw MalformedResponseException(uri.path, response.body);
      }
      return DiffResult.fromJson(decoded);
    } else {
      throw HttpApiException(response.statusCode, response.body);
    }
  }

  Future<String> exportDiff(
    String baselineIds,
    String currentIds, {
    String format = 'csv',
  }) async {
    final uri = _buildUri(
      '/compare/export?baseline_ids=$baselineIds&current_ids=$currentIds&format=$format',
    );
    final response = await _client.get(uri, headers: _headers).timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutApiException(uri.path),
        );
    if (response.statusCode == 200) {
      return response.body;
    } else {
      throw HttpApiException(response.statusCode, response.body);
    }
  }
}
