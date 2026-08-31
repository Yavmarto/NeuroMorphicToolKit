import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/services/launcher_control_uri.dart';

class StudioTargetRegistryService {
  StudioTargetRegistryService({Uri? backendUri, http.Client? client})
    : backendUri = backendUri ?? Uri.parse('http://127.0.0.1:9000'),
      _client = client ?? http.Client();

  final Uri backendUri;
  final http.Client _client;

  /// Unwraps an Akida host from a response that may or may not nest it.
  ///
  /// The routes disagree by design: `/preflight` and `/provision` answer
  /// `{"host": {...}, "preflight": ..., ...}`, while `/connectivity-test`
  /// answers the serialized host directly — and a serialized host has its own
  /// `host` key holding the *address string*. A blind
  /// `payload['host'] as Map?` therefore threw "type 'String' is not a subtype
  /// of type 'Map' in type cast" on exactly the routes that do not nest. Treat it
  /// as the wrapper only when it is one.
  Map<String, dynamic> _akidaHostPayload(Map<String, dynamic> payload) {
    final nested = payload['host'];
    return nested is Map<String, dynamic> ? nested : payload;
  }

  Map<String, dynamic> _decodeBodyAsMap(http.Response response) {
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Unexpected JSON object payload.');
    }
    return decoded;
  }

  Uri _controlUri(String path, {Map<String, String>? queryParameters}) {
    return resolveLauncherControlUri(
      backendUri.toString(),
      path,
      queryParameters: queryParameters,
    );
  }

  Uri _runtimeUri(
    String baseUrl,
    String path, {
    Map<String, String>? queryParameters,
  }) {
    final parsedBase = Uri.parse(baseUrl);
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return parsedBase.replace(
      path: normalizedPath,
      queryParameters: queryParameters,
    );
  }

  Future<List<PynqPairedBoard>> fetchPynqBoards() async {
    final response = await _client.get(
      _controlUri('/api/launcher/pynq/boards'),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected PYNQ board payload.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(PynqPairedBoard.fromJson)
        .toList(growable: false);
  }

  Future<PynqPairedBoard> savePynqBoard({
    String? boardId,
    required String displayName,
    required String hostAddress,
    required int sshPort,
    required String username,
    required String authMode,
    required String password,
    required String sshKeyPath,
    required String runtimeApiUrlOverride,
    required String overlayVersion,
    bool isDefault = false,
  }) async {
    final payload = <String, dynamic>{
      'displayName': displayName,
      'host': hostAddress,
      'sshPort': sshPort,
      'username': username,
      'authMode': authMode,
      if (authMode == 'password' && password.isNotEmpty) 'password': password,
      if (authMode == 'ssh_key' && sshKeyPath.isNotEmpty)
        'sshKeyPath': sshKeyPath,
      if (runtimeApiUrlOverride.isNotEmpty)
        'runtimeApiUrlOverride': runtimeApiUrlOverride,
      if (overlayVersion.isNotEmpty) 'overlayVersion': overlayVersion,
      'isDefault': isDefault,
    };

    final response = boardId == null || boardId.isEmpty
        ? await _client.post(
            _controlUri('/api/launcher/pynq/boards'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
        : await _client.put(
            _controlUri('/api/launcher/pynq/boards/$boardId'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          );
    _ensureSuccess(response);
    return PynqPairedBoard.fromJson(_decodeBodyAsMap(response));
  }

  Future<PynqPairedBoard> fetchPynqBoard(String boardId) async {
    final response = await _client.get(
      _controlUri('/api/launcher/pynq/boards/$boardId'),
    );
    _ensureSuccess(response);
    return PynqPairedBoard.fromJson(_decodeBodyAsMap(response));
  }

  Future<void> deletePynqBoard(String boardId) async {
    final response = await _client.delete(
      _controlUri('/api/launcher/pynq/boards/$boardId'),
    );
    _ensureSuccess(response);
  }

  Future<void> selectPynqBoard(String boardId) async {
    final response = await _client.put(
      _controlUri('/api/launcher/settings'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'selectedPynqBoardId': boardId}),
    );
    _ensureSuccess(response);
  }

  /// The board id launcher control will act on, or `null` when none is paired.
  ///
  /// Read side of [selectPynqBoard]; launcher control auto-selects the first
  /// board created, so this is populated as soon as one exists.
  Future<String?> fetchSelectedPynqBoardId() async {
    final response = await _client.get(_controlUri('/api/launcher/settings'));
    _ensureSuccess(response);
    final payload = _decodeBodyAsMap(response);
    final boardId = (payload['selectedPynqBoardId'] as String?)?.trim();
    return (boardId == null || boardId.isEmpty) ? null : boardId;
  }

  /// Verifies the board answers SSH with the saved credentials.
  ///
  /// Launcher control runs `python3 --version` over SSH, so this needs no board
  /// runtime and is the right check to offer immediately after pairing — before
  /// the agent is installed and long before an overlay exists.
  Future<PynqPairedBoard> testPynqBoardConnection(String boardId) async {
    final response = await _client.post(
      _controlUri('/api/launcher/pynq/boards/$boardId/connectivity-test'),
    );
    _ensureSuccess(response);
    return PynqBoardOperationResult.fromJson(_decodeBodyAsMap(response)).board;
  }

  /// Installs the board-side agent over SSH (wheel, venv, systemd or user-space).
  ///
  /// A cold provision on a Z2 regularly needs 90–100 s, so callers must show
  /// progress rather than a spinner that looks hung.
  Future<PynqBoardOperationResult> provisionPynqBoard(String boardId) async {
    final response = await _client.post(
      _controlUri('/api/launcher/pynq/boards/$boardId/provision'),
    );
    _ensureSuccess(response);
    return PynqBoardOperationResult.fromJson(_decodeBodyAsMap(response));
  }

  /// Copies `snn_overlay.bit` / `.hwh` / `overlay_manifest.json` to the board.
  ///
  /// Source is the overlay staged on the backend host, which ships with the
  /// backend image — the user never supplies these files.
  Future<PynqBoardOperationResult> installPynqOverlay(String boardId) async {
    final response = await _client.post(
      _controlUri('/api/launcher/pynq/boards/$boardId/install-overlay'),
    );
    _ensureSuccess(response);
    return PynqBoardOperationResult.fromJson(_decodeBodyAsMap(response));
  }

  Future<PynqBoardOperationResult> restartPynqRuntime(String boardId) async {
    final response = await _client.post(
      _controlUri('/api/launcher/pynq/boards/$boardId/restart-runtime'),
    );
    _ensureSuccess(response);
    return PynqBoardOperationResult.fromJson(_decodeBodyAsMap(response));
  }

  /// Asks the board runtime whether the overlay assets and DMA are usable.
  ///
  /// This is the canonical readiness probe for a PYNQ board — the backend
  /// container's `/targets/pynq/reachability` cannot see a remote board at all.
  Future<PynqBoardOperationResult> fetchPynqBoardPreflight(
    String boardId,
  ) async {
    final response = await _client.get(
      _controlUri('/api/launcher/pynq/boards/$boardId/preflight'),
    );
    _ensureSuccess(response);
    return PynqBoardOperationResult.fromJson(_decodeBodyAsMap(response));
  }

  /// Loads the overlay onto the PL and writes the network via MMIO/DMA.
  ///
  /// [requireHardware] is sent `true` so the board runtime refuses with
  /// `hardware_required` instead of quietly satisfying the deploy from its
  /// pure-Python simulator — a simulator success here would look exactly like
  /// silicon in the UI.
  Future<PynqDeployAck> deployPynqNetwork({
    required String boardId,
    required Map<String, dynamic> deployPayload,
    bool requireHardware = true,
  }) async {
    final response = await _client.post(
      _controlUri('/api/launcher/pynq/boards/$boardId/deploy'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        ...deployPayload,
        'require_hardware': requireHardware,
      }),
    );
    _ensureSuccess(response);
    return PynqDeployAck.fromJson(_decodeBodyAsMap(response));
  }

  Future<PynqRunResult> runPynqNetwork({
    required String boardId,
    required List<int> inputSpikes,
    int timesteps = 1,
  }) async {
    final response = await _client.post(
      _controlUri('/api/launcher/pynq/boards/$boardId/run'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'input_spikes': inputSpikes,
        'timesteps': timesteps,
      }),
    );
    _ensureSuccess(response);
    return PynqRunResult.fromJson(_decodeBodyAsMap(response));
  }

  Future<PynqSitlVerifyResult> verifyPynqNetwork({
    required String boardId,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) async {
    final response = await _client.post(
      _controlUri('/api/launcher/pynq/boards/$boardId/verify'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    _ensureSuccess(response);
    return PynqSitlVerifyResult.fromJson(_decodeBodyAsMap(response));
  }

  Future<PynqDeployJob> fetchPynqRuntimeStatus(String boardId) async {
    final response = await _client.get(
      _controlUri('/api/launcher/pynq/boards/$boardId/runtime-status'),
    );
    _ensureSuccess(response);
    return PynqDeployJob.fromJson(_decodeBodyAsMap(response));
  }

  Future<List<AkidaPairedHost>> fetchAkidaHosts() async {
    final response = await _client.get(
      _controlUri('/api/launcher/akida/hosts'),
    );
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body);
    if (decoded is! List) {
      throw Exception('Unexpected Akida host payload.');
    }
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(AkidaPairedHost.fromJson)
        .toList(growable: false);
  }

  Future<void> selectAkidaHost(String hostId) async {
    final response = await _client.put(
      _controlUri('/api/launcher/settings'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'selectedAkidaHostId': hostId}),
    );
    _ensureSuccess(response);
  }

  /// The host id launcher control will act on, or `null` when none is paired.
  ///
  /// Read side of [selectAkidaHost] — launcher control auto-selects the first
  /// host created, so this is normally populated as soon as one exists.
  Future<String?> fetchSelectedAkidaHostId() async {
    final response = await _client.get(_controlUri('/api/launcher/settings'));
    _ensureSuccess(response);
    final payload = _decodeBodyAsMap(response);
    final hostId = (payload['selectedAkidaHostId'] as String?)?.trim();
    return (hostId == null || hostId.isEmpty) ? null : hostId;
  }

  Future<AkidaPairedHost> saveAkidaHost({
    String? hostId,
    required String displayName,
    required String hostAddress,
    required int sshPort,
    required String username,
    required String authMode,
    required String? password,
    required String sshKeyPath,
    required String runtimeApiUrl,
    required String controlApiUrl,
    required String remoteInstallRoot,
    required String serviceUser,
    bool isDefault = false,
    bool sameHostAsBackend = false,
  }) async {
    final payload = <String, dynamic>{
      'displayName': displayName,
      'host': hostAddress,
      'sshPort': sshPort,
      'username': username,
      'authMode': authMode,
      // Sent whenever the user supplied one, regardless of [authMode]: gating on
      // the toggle silently discarded a typed password when the two disagreed,
      // which is how saved passwords went missing. An explicit `''` clears the
      // stored password; omitting the key entirely keeps it. The backend
      // reconciles authMode against the credentials it actually receives.
      'password': ?password,
      if (sshKeyPath.isNotEmpty) 'sshKeyPath': sshKeyPath,
      'runtimeApiUrl': runtimeApiUrl,
      'controlApiUrl': controlApiUrl,
      'remoteInstallRoot': remoteInstallRoot,
      'serviceUser': serviceUser,
      'isDefault': isDefault,
      'sameHostAsBackend': sameHostAsBackend,
    };

    final response = hostId == null || hostId.isEmpty
        ? await _client.post(
            _controlUri('/api/launcher/akida/hosts'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
        : await _client.put(
            _controlUri('/api/launcher/akida/hosts/$hostId'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          );
    _ensureSuccess(response);
    return AkidaPairedHost.fromJson(_decodeBodyAsMap(response));
  }

  Future<AkidaPairedHost> fetchAkidaHost(String hostId) async {
    final response = await _client.get(
      _controlUri('/api/launcher/akida/hosts/$hostId'),
    );
    _ensureSuccess(response);
    return AkidaPairedHost.fromJson(_decodeBodyAsMap(response));
  }

  /// Verifies the host is actually reachable with the saved credentials.
  ///
  /// Launcher control runs `python3 --version` over SSH when a username is saved
  /// and falls back to an HTTP `/health` probe otherwise, so on the SSH path this
  /// needs no API token — which makes it the right check to offer right after
  /// entering credentials. The returned host carries the resulting `state` and
  /// `lastReadinessMessage`.
  Future<AkidaPairedHost> testAkidaHostConnection(String hostId) async {
    final response = await _client.post(
      _controlUri('/api/launcher/akida/hosts/$hostId/connectivity-test'),
    );
    _ensureSuccess(response);
    final payload = _decodeBodyAsMap(response);
    return AkidaPairedHost.fromJson(_akidaHostPayload(payload));
  }

  Future<AkidaPairedHost> provisionAkidaHost(String hostId) async {
    final response = await _client.post(
      _controlUri('/api/launcher/akida/hosts/$hostId/provision'),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return AkidaPairedHost.fromJson(_akidaHostPayload(payload));
  }

  Future<AkidaRuntimeUpdateJob> startAkidaRuntimeUpdate(String hostId) async {
    final response = await _client.post(
      _controlUri('/api/launcher/akida/hosts/$hostId/runtime-update-jobs'),
    );
    _ensureSuccess(response);
    return AkidaRuntimeUpdateJob.fromJson(_decodeBodyAsMap(response));
  }

  Future<AkidaRuntimeUpdateJob> fetchAkidaRuntimeUpdate({
    required String hostId,
    required String jobId,
  }) async {
    final response = await _client.get(
      _controlUri(
        '/api/launcher/akida/hosts/$hostId/runtime-update-jobs/$jobId',
      ),
    );
    _ensureSuccess(response);
    return AkidaRuntimeUpdateJob.fromJson(_decodeBodyAsMap(response));
  }

  Future<AkidaPairedHost> fetchAkidaHostPreflight(String hostId) async {
    final response = await _client.get(
      _controlUri('/api/launcher/akida/hosts/$hostId/preflight'),
    );
    _ensureSuccess(response);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return AkidaPairedHost.fromJson(_akidaHostPayload(payload));
  }

  Future<Uint8List> downloadAkidaPackage({
    required String runtimeApiUrl,
    required String credentialRef,
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (credentialRef.trim().isNotEmpty) {
      headers['X-API-Key'] = credentialRef.trim();
    }
    final response = await _client.post(
      _runtimeUri(
        runtimeApiUrl,
        '/api/neurochip/akida/deploy/mapped',
        queryParameters: <String, String>{'bit_width': '$bitWidth'},
      ),
      headers: headers,
      body: jsonEncode(mappedNetwork),
    );
    _ensureSuccess(response);
    return response.bodyBytes;
  }

  Future<AkidaSdkVerification> mapAkidaRuntime({
    required String runtimeApiUrl,
    required String credentialRef,
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (credentialRef.trim().isNotEmpty) {
      headers['X-API-Key'] = credentialRef.trim();
    }
    final response = await _client.post(
      _runtimeUri(
        runtimeApiUrl,
        '/api/neurochip/akida/map',
        queryParameters: <String, String>{'bit_width': '$bitWidth'},
      ),
      headers: headers,
      body: jsonEncode(mappedNetwork),
    );
    _ensureSuccess(response);
    return AkidaSdkVerification.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<AkidaSdkVerification> mapAkidaRuntimeViaLauncher({
    required String hostId,
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
  }) async {
    final response = await _client.post(
      _controlUri(
        '/api/launcher/akida/hosts/$hostId/map',
        queryParameters: <String, String>{'bit_width': '$bitWidth'},
      ),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(mappedNetwork),
    );
    _ensureSuccess(response);
    return AkidaSdkVerification.fromJson(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<Map<String, dynamic>> runAkidaInference({
    required String runtimeApiUrl,
    required String credentialRef,
    required List<double> inputs,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (credentialRef.trim().isNotEmpty) {
      headers['X-API-Key'] = credentialRef.trim();
    }
    final response = await _client.post(
      _runtimeUri(runtimeApiUrl, '/api/neurochip/akida/inference'),
      headers: headers,
      body: jsonEncode(<String, dynamic>{'inputs': inputs}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> runAkidaInferenceViaLauncher({
    required String hostId,
    required List<double> inputs,
  }) async {
    final response = await _client.post(
      _controlUri('/api/launcher/akida/hosts/$hostId/run'),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'inputs': inputs}),
    );
    _ensureSuccess(response);
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> submitAkidaModelJobViaLauncher({
    required String hostId,
    required String filename,
    required String bundleBase64,
    required String sha256,
  }) async {
    final response = await _client.post(
      _controlUri('/api/launcher/akida/hosts/$hostId/model-jobs'),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'filename': filename,
        'bundleBase64': bundleBase64,
        'sha256': sha256,
        'requirePhysicalHardware': true,
      }),
    );
    _ensureSuccess(response);
    return _decodeBodyAsMap(response);
  }

  Future<Map<String, dynamic>> fetchAkidaModelJobViaLauncher({
    required String hostId,
    required String jobId,
  }) async {
    final response = await _client.get(
      _controlUri('/api/launcher/akida/hosts/$hostId/model-jobs/$jobId'),
    );
    _ensureSuccess(response);
    return _decodeBodyAsMap(response);
  }

  Future<Map<String, dynamic>> startAkidaModelBenchmarkViaLauncher({
    required String hostId,
    required String modelId,
  }) async {
    final response = await _client.post(
      _controlUri(
        '/api/launcher/akida/hosts/$hostId/models/$modelId/benchmark',
      ),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(const <String, dynamic>{}),
    );
    _ensureSuccess(response);
    return _decodeBodyAsMap(response);
  }

  Future<Map<String, dynamic>> runAkidaModelInferenceViaLauncher({
    required String hostId,
    required String modelId,
    required int sampleIndex,
  }) async {
    final response = await _client.post(
      _controlUri(
        '/api/launcher/akida/hosts/$hostId/models/$modelId/inference',
      ),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{'sampleIndex': sampleIndex}),
    );
    _ensureSuccess(response);
    return _decodeBodyAsMap(response);
  }

  Future<Map<String, dynamic>> fetchAkidaModelVisualizationViaLauncher({
    required String hostId,
    required String modelId,
    required String mode,
    required int layerIndex,
    int? sampleIndex,
  }) async {
    final response = await _client.post(
      _controlUri(
        '/api/launcher/akida/hosts/$hostId/models/$modelId/visualization',
      ),
      headers: const <String, String>{'Content-Type': 'application/json'},
      body: jsonEncode(<String, dynamic>{
        'mode': mode,
        'layerIndex': layerIndex,
        'sampleIndex': ?sampleIndex,
      }),
    );
    _ensureSuccess(response);
    return _decodeBodyAsMap(response);
  }

  void dispose() {
    _client.close();
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    throw LauncherControlApiException(response.statusCode, response.body);
  }
}

class LauncherControlApiException implements Exception {
  const LauncherControlApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'LauncherControlApiException($statusCode): $body';
}
