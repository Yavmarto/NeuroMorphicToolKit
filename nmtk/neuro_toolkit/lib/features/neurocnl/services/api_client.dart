import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/features/neurocnl/models/parsed_spec.dart';
import 'package:neuro_toolkit/features/neurocnl/models/validation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/models/network_graph.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulation_result.dart';
import 'package:neuro_toolkit/features/neurocnl/models/template.dart';
import 'package:neuro_toolkit/features/neurocnl/models/prosthetic_sim.dart';
import 'package:neuro_toolkit/features/neurocnl/models/sleep_train.dart';
import 'package:neuro_toolkit/features/neurocnl/models/crossbar_export.dart';
import 'package:neuro_toolkit/features/neurocnl/models/energy_report.dart';
import 'package:neuro_toolkit/features/neurocnl/models/quantization_report.dart';
import 'package:neuro_toolkit/features/neurocnl/models/fault_injection_report.dart';
import 'package:neuro_toolkit/features/neurocnl/models/job_status.dart';
import 'package:neuro_toolkit/features/neurocnl/models/server_workspace_summary.dart';
import 'package:neuro_toolkit/features/neurocnl/models/dataset_catalog.dart';
import 'package:neuro_toolkit/features/neurocnl/models/health_status.dart';
import 'package:neuro_toolkit/features/neurocnl/models/launcher_diagnostics.dart';
import 'package:neuro_toolkit/features/neurocnl/models/crossbar_export_result.dart';
import 'package:neuro_toolkit/features/neurocnl/models/sensor_frame.dart';
import 'package:neuro_toolkit/features/neurocnl/models/simulator_preflight.dart';
import 'package:neuro_toolkit/features/neurocnl/models/target_reachability.dart';
import 'package:neuro_toolkit/features/neurocnl/models/deploy_preview_result.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/pipeline_cnl_result.dart';
import 'package:neuro_toolkit/features/neurocnl/services/base_http_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/export_artifact.dart';
import 'package:neuro_toolkit/features/neurocnl/services/launcher_control_uri.dart';
import 'package:neuro_toolkit/features/neurocnl/services/neurosim_import_contract.dart';

/// HTTP client for the neurocnl Studio backend API.
class ApiClient extends BaseHttpClient {
  static const int _httpOk = 200;
  static const int _httpServiceUnavailable = 503;

  final String apiKey;

  ApiClient({required super.baseUrl, this.apiKey = '', super.httpClient});

  // ── Datasets (Firebase server cache) ───────────────────────────

  Future<DatasetCatalogList> listDatasets() async {
    final response = await _get('/datasets');
    return DatasetCatalogList.fromJson(response);
  }

  Future<DatasetEntry> importLocalDataset({
    required String filename,
    required Uint8List bytes,
    String? serverPath,
  }) async {
    // When the picker returns file bytes, always upload them. The optional
    // server_path fast-path only applies to co-located backends and must not
    // run ahead of multipart (a stale backend returns 405 for POST here).
    if (bytes.isNotEmpty) {
      return _importLocalDatasetMultipart(filename: filename, bytes: bytes);
    }

    final trimmedPath = serverPath?.trim();
    if (trimmedPath != null && trimmedPath.isNotEmpty) {
      final response = await _post('/datasets/import-local', {
        'server_path': trimmedPath,
      });
      return DatasetEntry.fromJson(response);
    }

    throw const ApiException(
      422,
      '{"detail":"No dataset file was provided to import."}',
    );
  }

  Future<DatasetEntry> _importLocalDatasetMultipart({
    required String filename,
    required Uint8List bytes,
  }) async {
    final uri = Uri.parse('$baseUrl/datasets/import-local');
    final request = http.MultipartRequest('POST', uri);
    if (apiKey.isNotEmpty) {
      request.headers['X-API-Key'] = apiKey;
    }
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await rawHttpClient.send(request);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw ApiException(streamed.statusCode, body);
    }
    return DatasetEntry.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  /// Uploads raw bytes to a server path — for pipeline node fields (e.g. the
  /// Data Loader node's `dataset_path`) that reference an arbitrary file
  /// rather than a dataset-catalog entry. Returns the server-resolved path.
  Future<String> uploadRawDatasetFile({
    required String filename,
    required Uint8List bytes,
  }) async {
    final uri = Uri.parse('$baseUrl/datasets/upload-raw');
    final request = http.MultipartRequest('POST', uri);
    if (apiKey.isNotEmpty) {
      request.headers['X-API-Key'] = apiKey;
    }
    request.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: filename),
    );
    final streamed = await rawHttpClient.send(request);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw ApiException(streamed.statusCode, body);
    }
    return (jsonDecode(body) as Map<String, dynamic>)['path'] as String;
  }

  /// Read-only check for whether a previously-stored `dataset_path` (e.g. a
  /// Data Loader node's uploaded `.pt`/`.npy` file) still exists on this
  /// backend instance — does not download or cache anything. Used to warn
  /// the user in the property panel before they hit a generate/train-time
  /// error for a workspace restored after the backend's copy was lost.
  Future<bool> checkDatasetPathExists(String path) async {
    final response = await _get(
      '/datasets/exists?path=${Uri.encodeQueryComponent(path)}',
    );
    return (response['exists'] as bool?) ?? false;
  }

  Future<DatasetDownloadResult> downloadDataset(String datasetId) async {
    final uri = Uri.parse('$baseUrl/datasets/$datasetId/download');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }
    final response = await rawHttpClient.post(uri, headers: headers);
    if (response.statusCode == 200) {
      return DatasetDownloadResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    if (response.statusCode == 202) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final jobId = body['job_id'] as String;
      // Datasets can be very large. The server-side job timeout is 3600 s;
      // use 60 minutes here so slow connections don't prematurely fail, and
      // use a 2-second poll cadence appropriate for long-running transfers.
      return _pollJobResult<DatasetDownloadResult>(
        jobId,
        DatasetDownloadResult.fromJson,
        timeout: const Duration(hours: 1),
        pollInterval: const Duration(seconds: 2),
      );
    }
    throw ApiException(response.statusCode, response.body);
  }

  /// Triggers a server-side Firebase download and polls until the dataset
  /// status reaches [ready]. Returns the server-local file path.
  Future<String> triggerAndWaitForDownload(String datasetId) async {
    final postUri = Uri.parse('$baseUrl/datasets/$datasetId/download');
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }
    final postResponse = await rawHttpClient.post(postUri, headers: headers);

    if (postResponse.statusCode == 200) {
      // Dataset was already downloaded — local_path is in the response.
      final body = jsonDecode(postResponse.body) as Map<String, dynamic>;
      return body['local_path'] as String;
    }
    if (postResponse.statusCode != 202) {
      throw ApiException(postResponse.statusCode, postResponse.body);
    }

    // 202 → download started. Poll GET /datasets/{id} until ready.
    const timeout = Duration(hours: 1);
    const pollInterval = Duration(seconds: 1);
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(pollInterval);
      final data = await _get('/datasets/$datasetId');
      final status = data['status'] as String? ?? '';
      if (status == 'ready') {
        final localPath = data['local_path'] as String?;
        if (localPath == null || localPath.isEmpty) {
          throw ApiException(
            500,
            'Dataset $datasetId is ready but local_path is missing.',
          );
        }
        return localPath;
      }
      if (status == 'error') {
        final msg = data['error_message'] as String?;
        throw ApiException(
          500,
          msg != null && msg.isNotEmpty
              ? msg
              : 'Dataset download failed on the server.',
        );
      }
      // status == 'downloading' or 'not_downloaded' → keep polling
    }

    throw ApiException(
      504,
      'Timed out waiting for dataset $datasetId to download.',
    );
  }

  // ── Parse ──────────────────────────────────────────────────────

  Future<ParseResult> parse(String spec) async {
    final response = await _post('/parse', {'spec': spec});
    return ParseResult.fromJson(response);
  }

  // ── Validate ───────────────────────────────────────────────────

  Future<ValidationResult> validate(
    String spec, {
    Map<String, dynamic>? params,
    String backend = 'nir',
  }) async {
    final response = await _post('/validate', {
      'spec': spec,
      'params': params ?? {},
      'backend': backend,
    });
    return ValidationResult.fromJson(response);
  }

  // ── Preflight ─────────────────────────────────────────────────

  /// Classifies a CNL spec against a simulator backend without dispatching.
  ///
  /// Calls POST /api/simulators/preflight with a JSON body.
  /// Throws [ApiException] on non-200 responses.
  Future<PreflightResult> preflight(String spec, String backendName) async {
    final response = await _post('/simulators/preflight', {
      'spec': spec,
      'backend_name': backendName,
    });
    return PreflightResult.fromJson(response);
  }

  /// Classifies a raw NIR HDF5 graph against a simulator backend.
  ///
  /// Calls POST /api/simulators/preflight-nir as a multipart form upload.
  /// Throws [ApiException] on non-200 responses.
  Future<PreflightResult> preflightNir(
    Uint8List nirBytes,
    String backendName,
  ) async {
    final uri = Uri.parse('$baseUrl/simulators/preflight-nir');
    final request = http.MultipartRequest('POST', uri);
    if (apiKey.isNotEmpty) {
      request.headers['X-API-Key'] = apiKey;
    }
    request.files.add(
      http.MultipartFile.fromBytes('file', nirBytes, filename: 'graph.nir'),
    );
    request.fields['backend_name'] = backendName;
    final streamed = await rawHttpClient.send(request);
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode != 200) {
      throw ApiException(streamed.statusCode, body);
    }
    return PreflightResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }

  // ── Deploy targets (Phase G) ─────────────────────────────────────

  /// Fetches per-backend node-support metadata for the Hardware Deployment
  /// dropdown. Calls GET /api/deploy-targets.
  Future<List<DeployTargetInfo>> getDeployTargets() async {
    final response = await rawHttpClient.get(
      Uri.parse('$baseUrl/deploy-targets'),
      headers: apiKey.isNotEmpty ? {'X-API-Key': apiKey} : null,
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    final decoded = jsonDecode(response.body) as List<dynamic>;
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(DeployTargetInfo.fromJson)
        .toList(growable: false);
  }

  /// Side-effect-free codegen preview for a deploy target — never writes a
  /// notebook to disk. Calls POST /api/notebook/preview.
  Future<DeployPreviewResult> previewDeployTarget(
    String spec,
    String target,
  ) async {
    final response = await _post('/notebook/preview', {
      'spec': spec,
      'target': target,
    });
    return DeployPreviewResult.fromJson(response);
  }

  // ── Generate ───────────────────────────────────────────────────

  Future<GenerateResult> generate(
    String spec, {
    Map<String, dynamic>? params,
  }) async {
    final response = await _post('/generate', {
      'spec': spec,
      'params': params ?? {},
    });
    return GenerateResult.fromJson(response);
  }

  // ── Notebook generation ────────────────────────────────────────

  /// Pipeline-aware notebook generation.
  ///
  /// Sends both the CNL [spec] (from the Architecture tab) and the
  /// [pipelineConfig] JSON (from the Pipeline tab) to the backend endpoint
  /// `POST /api/notebook/generate-v2`. Returns a [NotebookGenerationResult]
  /// whose [NotebookGenerationResult.jupyterUrl] points at the generated
  /// notebook in JupyterLab.
  Future<NotebookGenerationResult> generateNotebookV2({
    required String spec,
    required Map<String, dynamic> pipelineConfig,
    Map<String, dynamic>? pipelinePhases,
    String? pipelineCnl,
    String workspacePath = '',
    String? importId,
  }) async {
    final body = <String, dynamic>{
      'spec': spec,
      'pipeline_config': pipelineConfig,
      'workspace_path': workspacePath,
    };
    if (pipelinePhases != null) {
      body['pipeline_phases'] = pipelinePhases;
    }
    if (pipelineCnl != null && pipelineCnl.isNotEmpty) {
      body['pipeline_cnl'] = pipelineCnl;
    }
    if (importId != null && importId.isNotEmpty) {
      body['import_id'] = importId;
    }
    final response = await _post('/notebook/generate-v2', body);
    return NotebookGenerationResult.fromJson(response);
  }

  /// Creates the reproducible full-MNIST PyTorch→ONNX companion notebook.
  Future<NotebookGenerationResult> generateAkidaMnistNotebook({
    required String workspacePath,
  }) async {
    final response = await _post('/notebook/templates/akida-mnist', {
      'workspace_path': workspacePath,
    });
    return NotebookGenerationResult.fromJson(response);
  }

  /// Returns the newest checksummed Akida bundle in a Jupyter workspace.
  Future<Map<String, dynamic>> latestAkidaBundle(String workspaceFolder) {
    return _get(
      '/notebook/artifacts/latest-akida-bundle?workspace_folder='
      '${Uri.encodeQueryComponent(workspaceFolder)}',
    );
  }

  /// Returns the newest trained NIR graph in a Jupyter workspace.
  ///
  /// Written by the NIR Exporter canvas node after it loads `best_model.pt` and
  /// overlays the learned weights, so this is the only artifact carrying real
  /// values for a target with no bundle format of its own — the CNL spec stores
  /// tensor shape only.
  Future<Map<String, dynamic>> latestTrainedNir(String workspaceFolder) {
    return _get(
      '/notebook/artifacts/latest-trained-nir?workspace_folder='
      '${Uri.encodeQueryComponent(workspaceFolder)}',
    );
  }

  /// One evaluation sample as an input frame a spiking target can run.
  ///
  /// Calls `GET /api/notebook/artifacts/dataset-sample`. The alternative — the
  /// user typing spike indices — is unusable past a handful of input neurons,
  /// so this is what makes a hardware run mean anything.
  Future<Map<String, dynamic>> datasetSample(
    String workspaceFolder, {
    int index = 0,
  }) {
    return _get(
      '/notebook/artifacts/dataset-sample?workspace_folder='
      '${Uri.encodeQueryComponent(workspaceFolder)}&index=$index',
    );
  }

  /// Renders [pipelineConfig] as Train/Evaluate/Export CNL text, for
  /// display in the Pipeline tab's CNL preview panel. Calls
  /// `POST /api/notebook/generate-pipeline-cnl`.
  Future<PipelineCnlResult> generatePipelineCnl(
    Map<String, dynamic> pipelineConfig,
  ) async {
    final response = await _post('/notebook/generate-pipeline-cnl', {
      'pipeline_config': pipelineConfig,
    });
    return PipelineCnlResult.fromJson(response);
  }

  /// Parses Train/Evaluate/Export CNL text and merges it onto
  /// [currentPipelineConfig] — only the fields the CNL text specifies are
  /// overridden. Fail-closed: a malformed sentence throws [ApiException]
  /// with status 422. Calls `POST /api/notebook/parse-pipeline-cnl`.
  Future<PipelineConfigParseResult> parsePipelineCnl(
    String cnlText,
    Map<String, dynamic> currentPipelineConfig,
  ) async {
    final response = await _post('/notebook/parse-pipeline-cnl', {
      'cnl_text': cnlText,
      'pipeline_config': currentPipelineConfig,
    });
    return PipelineConfigParseResult.fromJson(response);
  }

  Future<String> ensureWorkspace({required String workspacePath}) async {
    final response = await _post('/notebook/ensure-workspace', {
      'workspace_path': workspacePath,
    });
    return response['workspace_folder'] as String? ?? '';
  }

  /// Syncs the full workspace config (pipeline/canvas/CNL state) to the
  /// server under [slug], so a different device pointed at the same backend
  /// can list and reopen it later. Upsert — safe to call repeatedly.
  Future<void> syncWorkspace({
    required String slug,
    required String name,
    required Map<String, dynamic> config,
  }) async {
    await _post('/workspaces/$slug', {'name': name, 'config': config});
  }

  /// Every workspace saved on this server, most recently updated first.
  Future<List<ServerWorkspaceSummary>> listServerWorkspaces() async {
    final response = await _get('/workspaces');
    return (response['items'] as List)
        .map((w) => ServerWorkspaceSummary.fromJson(w as Map<String, dynamic>))
        .toList();
  }

  /// The full config previously synced for [slug].
  Future<Map<String, dynamic>> getServerWorkspace(String slug) async {
    final response = await _get('/workspaces/$slug');
    return (response['config'] as Map).cast<String, dynamic>();
  }

  Future<Map<String, bool>> getTargetAvailability() async {
    final response = await _get('/notebook/target-availability');
    return response.map((key, value) => MapEntry(key, value == true));
  }

  /// Current last-modified time (epoch seconds) of a generated notebook, or
  /// null if it can't be found. Used by the Run step to detect edits made in
  /// the embedded JupyterLab view since the notebook was last generated.
  Future<double?> getNotebookLastModified({
    required String workspaceFolder,
    required String filename,
  }) async {
    final query =
        'workspace_folder=${Uri.encodeQueryComponent(workspaceFolder)}'
        '&filename=${Uri.encodeQueryComponent(filename)}';
    final response = await _get('/notebook/last-modified?$query');
    final value = response['last_modified'];
    return value == null ? null : (value as num).toDouble();
  }

  // ── Simulate ───────────────────────────────────────────────────

  Future<SimulationResult> simulate(
    String spec, {
    double duration = 1.0,
    double dt = 0.001,
    Map<String, dynamic>? params,
  }) async {
    final uri = Uri.parse('$baseUrl/simulate');
    final headers = {'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }

    final response = await rawHttpClient.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'spec': spec,
        'duration': duration,
        'dt': dt,
        'params': params ?? {},
      }),
    );

    if (response.statusCode == 200) {
      return SimulationResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    if (response.statusCode == 202) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final jobId = body['job_id'] as String?;
      if (jobId == null || jobId.isEmpty) {
        throw ApiException(response.statusCode, response.body);
      }

      return _pollJobResult<SimulationResult>(jobId, SimulationResult.fromJson);
    }

    throw ApiException(response.statusCode, response.body);
  }

  Future<T> _pollJobResult<T>(
    String jobId,
    T Function(Map<String, dynamic>) factory, {
    Duration pollInterval = const Duration(milliseconds: 250),
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final job = await getJobStatus<T>(jobId, fromJsonT: factory);

      if (job.status == 'complete') {
        final result = job.result;
        if (result != null) {
          return result;
        }
        throw ApiException(
          500,
          'Job $jobId completed without a valid result payload.',
        );
      }

      if (job.status == 'failed') {
        // Prefer the human-readable error stored in the job over the generic
        // fallback so that actionable messages (e.g. Firebase not configured,
        // disk full, hash mismatch) reach the UI intact.
        final errorMsg = job.error;
        throw ApiException(
          500,
          errorMsg != null && errorMsg.isNotEmpty
              ? errorMsg
              : 'Job $jobId failed.',
        );
      }

      await Future<void>.delayed(pollInterval);
    }

    throw ApiException(504, 'Timed out waiting for job $jobId.');
  }

  // ── Templates ──────────────────────────────────────────────────

  Future<List<CnlTemplate>> getTemplates() async {
    final response = await _get('/templates');
    final templates = (response['templates'] as List)
        .map((t) => CnlTemplate.fromJson(t as Map<String, dynamic>))
        .toList();
    return templates;
  }

  // ── Export ─────────────────────────────────────────────────────

  Future<NeurosimImportContract> prepareNeurosimHandoff(String spec) async {
    final response = await _post('/neurosim/handoff', {'spec': spec});
    final importContract = response['import_contract'];
    if (importContract is! Map<String, dynamic>) {
      throw const FormatException(
        'Missing import_contract in NeuroSim handoff response.',
      );
    }
    return NeurosimImportContract.fromJson(importContract);
  }

  Future<String> export(
    String spec, {
    String format = 'cnl',
    String filename = 'spec.cnl',
  }) async {
    final uri = Uri.parse('$baseUrl/export');
    final headers = {'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }
    final response = await rawHttpClient.post(
      uri,
      headers: headers,
      body: jsonEncode({'spec': spec, 'format': format, 'filename': filename}),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return response.body;
  }

  Future<ExportArtifact> exportNirArtifact(
    String spec, {
    String filename = 'network.nir',
  }) async {
    final uri = Uri.parse('$baseUrl/export');
    final headers = {'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }
    final response = await rawHttpClient.post(
      uri,
      headers: headers,
      body: jsonEncode({'spec': spec, 'format': 'nir', 'filename': filename}),
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return ExportArtifact.binary(
      filename: filename,
      mimeType: response.headers['content-type'] ?? 'application/octet-stream',
      payload: Uint8List.fromList(response.bodyBytes),
    );
  }

  // ── Target reachability ────────────────────────────────────────

  /// Reachability of a target *as seen from the backend container*: an SDK
  /// import plus a local device enumeration (see the backend's
  /// `target_reachability.py`).
  ///
  /// [TargetReachability.detail] carries the concrete reason ("akida SDK not
  /// installed", "no Akida devices connected", "2 device(s) found"). It used to
  /// be dropped here, which left every caller guessing at a message from the
  /// bare boolean.
  Future<TargetReachability> getTargetReachability(String targetId) async {
    final response = await _get('/targets/$targetId/reachability');
    return TargetReachability(
      reachable: (response['reachable'] as bool?) ?? false,
      detail: (response['detail'] as String?) ?? '',
    );
  }

  // ── Health ─────────────────────────────────────────────────────

  Future<HealthStatus> health() async {
    final uri = _healthUri();
    final headers = <String, String>{};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }

    final response = await rawHttpClient.get(uri, headers: headers);
    if (response.statusCode == _httpOk ||
        response.statusCode == _httpServiceUnavailable) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return HealthStatus.fromJson(body);
    }
    throw ApiException(response.statusCode, response.body);
  }

  Future<LauncherDiagnostics> fetchLauncherDiagnostics() async {
    final settingsResponse = await rawHttpClient.get(
      _launcherControlUri('/api/launcher/settings'),
    );
    if (settingsResponse.statusCode != _httpOk) {
      throw ApiException(settingsResponse.statusCode, settingsResponse.body);
    }
    final logsResponse = await rawHttpClient.get(
      _launcherControlUri(
        '/api/launcher/logs',
      ).replace(queryParameters: const <String, String>{'filter': 'error'}),
    );
    if (logsResponse.statusCode != _httpOk) {
      throw ApiException(logsResponse.statusCode, logsResponse.body);
    }
    return LauncherDiagnostics.fromJson(
      jsonDecode(settingsResponse.body) as Map<String, dynamic>,
      jsonDecode(logsResponse.body) as Map<String, dynamic>,
    );
  }

  // ── Prosthetic Simulation ─────────────────────────────────────

  Future<ProstheticSimResult> prostheticSimulate(
    ProstheticSimRequest req,
  ) async {
    final response = await _post('/prosthetic/simulate', req.toJson());
    return ProstheticSimResult.fromJson(response);
  }

  // ── Sleep Training ────────────────────────────────────────────

  Future<SleepTrainResult> prostheticSleep(SleepTrainRequest req) async {
    final response = await _post('/prosthetic/sleep', req.toJson());
    return SleepTrainResult.fromJson(response);
  }

  // ── Training ───────────────────────────────────────────────────

  /// POST /activity/compare — returns {frameworks: [...], matrix: [[...], ...]}
  Future<Map<String, dynamic>> compareActivity(
    List<Map<String, String>> jobs, {
    String layer = 'hidden_spikes',
  }) => _post('/activity/compare', {'jobs': jobs, 'layer': layer});

  /// Fetches the captured per-neuron activity export for [jobId].
  ///
  /// [epoch] optionally selects a specific captured epoch (the training
  /// loop only captures activity every few epochs, see
  /// `_ACTIVITY_CAPTURE_CADENCE_EPOCHS` in `notebook.py`); omitted, the
  /// backend returns the latest captured epoch. If [epoch] wasn't captured,
  /// the backend responds 404 with an `X-Available-Epochs` header listing
  /// which epochs were — surfaced via [ActivityFetchException] so callers
  /// can snap to the nearest captured epoch instead of showing nothing.
  Future<ActivityFetchResult> getTrainingActivityNpy(
    String jobId, {
    int? epoch,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/training/jobs/$jobId/activity.npy',
    ).replace(queryParameters: epoch == null ? null : {'epoch': '$epoch'});
    final headers = <String, String>{};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }
    final response = await rawHttpClient.get(uri, headers: headers);
    final availableEpochs = _parseAvailableEpochsHeader(response);
    if (response.statusCode != 200) {
      throw ActivityFetchException(
        response.statusCode,
        response.body,
        availableEpochs,
      );
    }
    final servedEpochHeader = response.headers['x-served-epoch'];
    return ActivityFetchResult(
      bytes: response.bodyBytes,
      servedEpoch: servedEpochHeader == null
          ? null
          : int.tryParse(servedEpochHeader),
      availableEpochs: availableEpochs,
    );
  }

  static List<int> _parseAvailableEpochsHeader(http.Response response) {
    final raw = response.headers['x-available-epochs'];
    if (raw == null || raw.isEmpty) return const <int>[];
    return raw
        .split(',')
        .map(int.tryParse)
        .whereType<int>()
        .toList(growable: false);
  }

  /// Fetch a PNG visualization image captured during a completed training job.
  ///
  /// [imageKey] must be ``"weight_map"`` or ``"attribution_map"``. Returns the
  /// raw PNG bytes, or `null` when the image was not captured (e.g. the canvas
  /// did not include the corresponding visualizer node).
  Future<Uint8List?> getVisualizationImage(
    String jobId,
    String imageKey,
  ) async {
    final uri = Uri.parse(
      '$baseUrl/training/jobs/$jobId/visualization_image/$imageKey',
    );
    final headers = <String, String>{};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }
    final response = await rawHttpClient.get(uri, headers: headers);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw ApiException(
        response.statusCode,
        'Failed to fetch $imageKey image',
      );
    }
    return response.bodyBytes;
  }

  // ── Crossbar Mapping / Handoff ───────────────────────────────────────────

  Future<CrossbarExportResult> prostheticExportCrossbar(
    CrossbarExportRequest req,
  ) async {
    final response = await _post('/prosthetic/export/crossbar', req.toJson());
    return CrossbarExportResult.fromJson(response);
  }

  // ── Energy Profiling ──────────────────────────────────────────

  Future<EnergyReport> prostheticEnergy(String spec) async {
    final response = await _post('/prosthetic/energy', {'spec': spec});
    return EnergyReport.fromJson(response);
  }

  // ── Quantization Analysis ─────────────────────────────────────

  Future<QuantizationReport> prostheticQuantize(
    String spec,
    List<int> bits,
  ) async {
    final response = await _post('/prosthetic/quantize', {
      'spec': spec,
      'bit_widths': bits,
    });
    return QuantizationReport.fromJson(response);
  }

  // ── Fault Injection ───────────────────────────────────────────

  Future<FaultInjectionReport> prostheticFaultInjection(
    String spec,
    double errorRate,
  ) async {
    final response = await _post('/prosthetic/fault-injection', {
      'spec': spec,
      'error_rate': errorRate,
    });
    return FaultInjectionReport.fromJson(response);
  }

  // ── Teensy Deploy ─────────────────────────────────────────────

  /// Validates a CNL spec for Teensy deployability and returns the
  /// Neurochip-compatible NetworkInput payload.
  ///
  /// Throws [ApiException] with status 422 when the network is not
  /// deployable; the body contains `rejection_reasons` and `warnings`.
  Future<Map<String, dynamic>> getTeensyNetworkPayload(
    String spec, {
    int bitWidth = 8,
  }) async {
    return _post('/deploy/teensy/network', {
      'spec': spec,
      'weight_bit_width': bitWidth,
    });
  }

  /// Calls POST /api/deploy/teensy/network and returns the Neurochip
  /// NetworkInput-compatible payload dict.
  ///
  /// Throws [ApiException] with status 422 when the network is not deployable.
  Future<Map<String, dynamic>> deployToNeurochip(
    String spec, {
    int bitWidth = 8,
  }) async {
    final response = await _post('/deploy/teensy/network', {
      'spec': spec,
      'weight_bit_width': bitWidth,
    });
    final payload = response['payload'];
    if (payload == null) {
      throw const FormatException(
        'Backend returned a null payload for Neurochip deploy.',
      );
    }
    return payload as Map<String, dynamic>;
  }

  /// Checks a spec against the PYNQ overlay and, when it fits, builds the payload.
  ///
  /// [trainedNirBase64] carries the learned weights. Without it the payload's
  /// weights come from the CNL spec, which stores tensor shape only — so they are
  /// all zeros and the board fires nothing.
  Future<Map<String, dynamic>> getPynqDeployability(
    String spec, {
    int bitWidth = 8,
    String? trainedNirBase64,
  }) {
    return _post('/deploy/pynq/network', {
      'spec': spec,
      'weight_bit_width': bitWidth,
      'trained_nir_base64': ?trainedNirBase64,
    });
  }

  Future<Map<String, dynamic>> getAkidaDeployability(
    String spec, {
    int bitWidth = 4,
    String akidaVersion = 'akida1',
  }) {
    return _post('/deploy/akida/network', {
      'spec': spec,
      'weight_bit_width': bitWidth,
      'akida_version': akidaVersion,
    });
  }

  Future<Map<String, dynamic>> getLavaDeployability(
    String spec, {
    int bitWidth = 8,
  }) {
    return _post('/deploy/lava/network', {
      'spec': spec,
      'weight_bit_width': bitWidth,
    });
  }

  Future<Map<String, dynamic>> checkScNeuroCoreToolchain(
    String toolchain, {
    String? binPath,
  }) {
    final queryParams = <String, String>{
      'toolchain': toolchain,
      if (binPath != null && binPath.isNotEmpty) 'bin_path': binPath,
    };
    final uri = Uri.parse(
      '$baseUrl/deploy/sc_neurocore/check_toolchain',
    ).replace(queryParameters: queryParams);
    final headers = <String, String>{};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }
    return rawHttpClient.get(uri, headers: headers).then((response) {
      if (response.statusCode != 200) {
        throw ApiException(response.statusCode, response.body);
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    });
  }

  // ── Hardware ──────────────────────────────────────────────────

  Future<List<String>> listSerialPorts() async {
    final response = await _get('/prosthetic/hardware/serial');
    return (response['ports'] as List).cast<String>();
  }

  Future<void> connectHardware(String port, int baudRate) async {
    await _post('/prosthetic/hardware/connect', {
      'port': port,
      'baud_rate': baudRate,
    });
  }

  Future<void> disconnectHardware() async {
    await _post('/prosthetic/hardware/disconnect', {});
  }

  Stream<SensorFrame> streamHardwareSensorData() async* {
    final uri = Uri.parse('$baseUrl/prosthetic/hardware/stream');
    final request = http.Request('GET', uri);
    request.headers['Accept'] = 'text/event-stream';
    if (apiKey.isNotEmpty) {
      request.headers['X-API-Key'] = apiKey;
    }

    final response = await rawHttpClient.send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw ApiException(response.statusCode, body);
    }

    final eventData = <String>[];
    final lines = utf8.decoder
        .bind(response.stream)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (line.isEmpty) {
        if (eventData.isEmpty) {
          continue;
        }

        final payload = eventData.join('\n');
        eventData.clear();

        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          yield SensorFrame.fromJson(decoded);
        } else if (decoded is Map) {
          yield SensorFrame.fromJson(Map<String, dynamic>.from(decoded));
        }
        continue;
      }

      if (line.startsWith('data:')) {
        eventData.add(line.substring(5).trimLeft());
      }
    }
  }

  // ── Job Polling ───────────────────────────────────────────────

  Future<JobStatus<T>> getJobStatus<T>(
    String jobId, {
    T Function(Map<String, dynamic>)? fromJsonT,
  }) async {
    final response = await _get('/jobs/$jobId');
    return JobStatus<T>.fromJson(response, fromJsonT);
  }

  // ── Training events (SSE) ─────────────────────────────────────

  /// Live event stream for a training job.
  ///
  /// Emits one decoded JSON map per `data:` event sent by the backend's
  /// `/api/training/jobs/{jobId}/events` endpoint. Events have a `type`
  /// discriminator — typically `epoch`, `phase`, `done`, or `failed`.
  /// The stream completes naturally when the backend closes the bus
  /// (job reaches a terminal state) or the consumer cancels the
  /// subscription.
  Stream<Map<String, dynamic>> streamTrainingEvents(String jobId) async* {
    final uri = Uri.parse('$baseUrl/training/jobs/$jobId/events');
    final request = http.Request('GET', uri);
    request.headers['Accept'] = 'text/event-stream';
    if (apiKey.isNotEmpty) {
      request.headers['X-API-Key'] = apiKey;
    }

    final response = await rawHttpClient.send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw ApiException(response.statusCode, body);
    }

    final eventData = <String>[];
    final lines = utf8.decoder
        .bind(response.stream)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (line.isEmpty) {
        if (eventData.isEmpty) continue;
        final payload = eventData.join('\n');
        eventData.clear();
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          yield decoded;
        } else if (decoded is Map) {
          yield Map<String, dynamic>.from(decoded);
        }
        continue;
      }
      // ':' lines are SSE comments (heartbeats). Skip them.
      if (line.startsWith(':')) continue;
      if (line.startsWith('data:')) {
        eventData.add(line.substring(5).trimLeft());
      }
    }
  }

  // ── Kernel runner ─────────────────────────────────────────────

  /// Queues a notebook for execution via the kernel runner.
  ///
  /// Returns the job ID that can be passed to [streamTrainingEvents] to receive
  /// progress updates via SSE. The endpoint returns HTTP 202 Accepted.
  Future<String> runNotebook({
    required String notebookPath,
    required String platform,
    String? kernelName,
  }) async {
    final uri = Uri.parse('$baseUrl/notebook/run');
    final headers = {'Content-Type': 'application/json'};
    if (apiKey.isNotEmpty) {
      headers['X-API-Key'] = apiKey;
    }
    final response = await rawHttpClient.post(
      uri,
      headers: headers,
      body: jsonEncode({
        'notebook_path': notebookPath,
        'platform': platform,
        if (kernelName != null && kernelName.trim().isNotEmpty)
          'kernel_name': kernelName.trim(),
      }),
    );
    if (response.statusCode != 200 && response.statusCode != 202) {
      throw ApiException(response.statusCode, response.body);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['job_id'] as String;
  }

  Map<String, String> get _authHeaders =>
      apiKey.isNotEmpty ? {'X-API-Key': apiKey} : const {};

  /// Queued/running notebook execution jobs (step 5 "Run") — polled to show
  /// what's currently active on the server, regardless of which client
  /// started it.
  Future<List<Map<String, dynamic>>> getActiveNotebookJobs() async {
    final response = await rawHttpClient.get(
      Uri.parse('$baseUrl/notebook/jobs/active'),
      headers: _authHeaders,
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  /// Cancels a notebook execution job started via [runNotebook].
  Future<void> cancelNotebookJob(String jobId) async {
    final response = await rawHttpClient.post(
      Uri.parse('$baseUrl/notebook/jobs/$jobId/cancel'),
      headers: _authHeaders,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  /// Live Jupyter kernel sessions — covers notebooks run manually inside the
  /// embedded JupyterLab UI (step 5), which aren't tracked as jobs.
  Future<List<Map<String, dynamic>>> getJupyterSessions() async {
    final response = await rawHttpClient.get(
      Uri.parse('$baseUrl/notebook/sessions'),
      headers: _authHeaders,
    );
    if (response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
    return (jsonDecode(response.body) as List).cast<Map<String, dynamic>>();
  }

  /// Shuts down a manually-run JupyterLab kernel session (hard stop).
  Future<void> stopJupyterSession(String sessionId) async {
    final response = await rawHttpClient.delete(
      Uri.parse('$baseUrl/notebook/sessions/$sessionId'),
      headers: _authHeaders,
    );
    if (response.statusCode != 204 && response.statusCode != 200) {
      throw ApiException(response.statusCode, response.body);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) =>
      basePost(
        path,
        body,
        apiKey: apiKey,
        errorFactory: (s, b) => ApiException(s, b),
      );

  Future<Map<String, dynamic>> _get(String path) =>
      baseGet(path, apiKey: apiKey, errorFactory: (s, b) => ApiException(s, b));

  Uri _resolvedBaseUri() {
    final parsed = Uri.parse(baseUrl);
    if (parsed.hasScheme && parsed.host.isNotEmpty) {
      return parsed;
    }
    return Uri.base.resolveUri(parsed);
  }

  Uri _healthUri() {
    final resolved = _resolvedBaseUri();
    var path = resolved.path;
    if (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final healthPath = path.endsWith('/api') ? '/health' : '$path/health';
    return resolved.replace(path: healthPath, query: null, fragment: null);
  }

  Uri _launcherControlUri(String path) {
    return resolveLauncherControlUri(baseUrl, path);
  }

  /// Returns the URL where Jupyter Lab is running, or null if the backend
  /// doesn't expose one (404 / unavailable).
  Future<String?> getJupyterUrl() async {
    try {
      final result = await _get('/jupyter/url');
      final url = result['url'] as String?;
      return url?.isNotEmpty == true ? url : null;
    } catch (_) {
      return null;
    }
  }
}

class NotebookGenerationResult {
  const NotebookGenerationResult({
    required this.workspaceFolder,
    required this.notebookFilenames,
    this.jupyterUrl = '',
    this.supportLevel,
    this.diagnostics = const [],
    this.generatedAt = 0,
    this.trainable = true,
    this.notTrainableReason = '',
  });

  final String workspaceFolder;
  final List<String> notebookFilenames;

  /// Absolute JupyterLab URL pointing at [workspaceFolder], supplied by the
  /// backend. Empty when the backend can't resolve one (standalone dev), in
  /// which case the caller derives a fallback URL.
  final String jupyterUrl;

  /// Support classification for the generated notebook's target ('exact' /
  /// 'approximate' / 'unsupported'), null if the target isn't a known
  /// backend. Backend has sent this since Phase B; previously discarded here.
  final String? supportLevel;
  final List<String> diagnostics;

  /// Epoch seconds (UTC) when the backend wrote this notebook. Used to detect
  /// edits made in the embedded JupyterLab view since generation.
  final double generatedAt;

  /// Whether this notebook has a training loop at all. The backend derives it
  /// from `_TRAINABLE_NOTEBOOK_TARGETS`, which stays the single authority — the
  /// Run step must not execute a notebook with no optimiser cell, because the
  /// resulting failure reads as the user's mistake. Defaults true so an older
  /// backend that omits the field keeps today's behaviour.
  final bool trainable;

  /// User-facing explanation shown on the Run step's tab when [trainable] is
  /// false. Empty when trainable.
  final String notTrainableReason;

  factory NotebookGenerationResult.fromJson(Map<String, dynamic> json) {
    final notebookEntries = (json['notebooks'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final notebooks = notebookEntries
        .map((n) => n['filename'] as String? ?? '')
        .where((f) => f.isNotEmpty)
        .toList(growable: false);
    final firstEntry = notebookEntries.isNotEmpty
        ? notebookEntries.first
        : const <String, dynamic>{};
    return NotebookGenerationResult(
      workspaceFolder: json['workspace_folder'] as String? ?? 'workspace',
      notebookFilenames: notebooks,
      jupyterUrl: json['jupyter_url'] as String? ?? '',
      supportLevel: firstEntry['support_level'] as String?,
      diagnostics: (firstEntry['diagnostics'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false),
      generatedAt: (json['generated_at'] as num?)?.toDouble() ?? 0,
      trainable: json['trainable'] as bool? ?? true,
      notTrainableReason: json['not_trainable_reason'] as String? ?? '',
    );
  }
}

/// Exception thrown when an API request fails.
class ApiException implements Exception {
  final int statusCode;
  final String body;

  const ApiException(this.statusCode, this.body);

  @override
  String toString() => 'ApiException($statusCode): $body';
}

/// Result of [ApiClient.getTrainingActivityNpy] — the raw export bytes plus
/// which epoch was actually served and which epochs were captured overall,
/// so callers can snap an epoch scrubber to a captured value instead of
/// requesting arbitrary epochs that will always 404.
class ActivityFetchResult {
  final Uint8List bytes;
  final int? servedEpoch;
  final List<int> availableEpochs;

  const ActivityFetchResult({
    required this.bytes,
    required this.servedEpoch,
    required this.availableEpochs,
  });
}

/// Thrown by [ApiClient.getTrainingActivityNpy] when the requested epoch
/// (or any epoch, for a run with no activity at all) isn't available.
/// [availableEpochs] is empty when the run has no activity data at all.
class ActivityFetchException implements Exception {
  final int statusCode;
  final String body;
  final List<int> availableEpochs;

  const ActivityFetchException(
    this.statusCode,
    this.body,
    this.availableEpochs,
  );

  @override
  String toString() => 'ActivityFetchException($statusCode): $body';
}
