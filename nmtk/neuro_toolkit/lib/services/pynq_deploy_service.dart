import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/services/control_api_service.dart';

/// REST client for PYNQ Z2 deployment endpoints.
///
/// Talks to:
/// - NeuroCNL (port 8000): /api/deploy/pynq/network
/// - Neurochip PYNQ board (user-configured): /hardware/pynq/{deploy,status,verify}
class PynqDeployService {
  PynqDeployService({
    http.Client? httpClient,
    String? neurocnlBaseUrl,
    ControlApiService? controlApiService,
  })  : _httpClient = httpClient ?? http.Client(),
        _neurocnlBaseUrl = neurocnlBaseUrl ?? 'http://localhost:8000',
        _controlApiService = controlApiService ?? ControlApiService();

  final http.Client _httpClient;
  final String _neurocnlBaseUrl;
  final ControlApiService _controlApiService;

  /// Check PYNQ exportability for a CNL spec.
  ///
  /// Calls POST /api/deploy/pynq/network on the NeuroCNL backend.
  /// Returns [PynqNetworkResponse] on success.
  /// Throws [PynqDeployException] on parse/lower/HTTP errors.
  Future<PynqNetworkResponse> checkExportability({
    required String spec,
    required int weightBitWidth,
  }) async {
    final uri = Uri.parse('$_neurocnlBaseUrl/api/deploy/pynq/network');
    final response = await _httpClient.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'spec': spec,
        'weight_bit_width': weightBitWidth,
      }),
    );

    if (response.statusCode == 200) {
      return PynqNetworkResponse.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }

    final detail = jsonDecode(response.body);
    if (detail is Map<String, dynamic> && detail.containsKey('detail')) {
      final d = detail['detail'];
      if (d is Map<String, dynamic>) {
        throw PynqDeployException(
          error: d['error'] as String? ?? 'unknown',
          messages:
              (d['messages'] as List?)?.map((e) => e.toString()).toList() ?? [],
        );
      }
      throw PynqDeployException(error: d.toString());
    }
    throw PynqDeployException(
      error: 'HTTP ${response.statusCode}',
      messages: [response.body],
    );
  }

  Future<List<PynqPairedBoard>> fetchPairedBoards() async {
    try {
      return await _controlApiService.fetchPynqBoards();
    } catch (e) {
      throw PynqDeployException(
          error: 'Failed to fetch paired boards', messages: ['$e']);
    }
  }

  Future<PynqPairedBoard> savePairedBoard({
    String? boardId,
    required String displayName,
    required String host,
    required int sshPort,
    required String username,
    required PynqBoardAuthMode authMode,
    String credentialRef = '',
    String password = '',
    String sshKeyPath = '',
    String overlayVersion = '',
  }) async {
    final payload = <String, dynamic>{
      'displayName': displayName,
      'host': host,
      'sshPort': sshPort,
      'username': username,
      'authMode': authMode.apiValue,
      'credentialRef': credentialRef,
      if (password.isNotEmpty) 'password': password,
      if (sshKeyPath.isNotEmpty) 'sshKeyPath': sshKeyPath,
      if (overlayVersion.isNotEmpty) 'overlayVersion': overlayVersion,
    };
    try {
      if (boardId == null || boardId.isEmpty) {
        return await _controlApiService.createPynqBoard(payload);
      }
      return await _controlApiService.updatePynqBoard(boardId, payload);
    } catch (e) {
      throw PynqDeployException(
          error: 'Failed to save paired board', messages: ['$e']);
    }
  }

  Future<void> deletePairedBoard(String boardId) async {
    try {
      await _controlApiService.deletePynqBoard(boardId);
    } catch (e) {
      throw PynqDeployException(
          error: 'Failed to delete paired board', messages: ['$e']);
    }
  }

  Future<PynqPairedBoard> testBoardConnectivity({
    required String boardId,
  }) async {
    try {
      return await _controlApiService.testPynqBoardConnectivity(boardId);
    } catch (e) {
      throw PynqDeployException(
          error: 'Connectivity test failed', messages: ['$e']);
    }
  }

  Future<PynqPairedBoard> provisionBoard({
    required String boardId,
  }) async {
    try {
      return await _controlApiService.provisionPynqBoard(boardId);
    } catch (e) {
      throw PynqDeployException(error: 'Provisioning failed', messages: ['$e']);
    }
  }

  Future<PynqPairedBoard> installOverlay({
    required String boardId,
  }) async {
    try {
      return await _controlApiService.installPynqOverlay(boardId);
    } catch (e) {
      throw PynqDeployException(
          error: 'Overlay install failed', messages: ['$e']);
    }
  }

  Future<PynqPairedBoard> refreshBoardPreflight({
    required String boardId,
  }) async {
    try {
      return await _controlApiService.fetchPynqBoardPreflight(boardId);
    } catch (e) {
      throw PynqDeployException(
          error: 'Preflight check failed', messages: ['$e']);
    }
  }

  Future<PynqPairedBoard> restartRuntime({
    required String boardId,
  }) async {
    try {
      return await _controlApiService.restartPynqRuntime(boardId);
    } catch (e) {
      throw PynqDeployException(
          error: 'Runtime restart failed', messages: ['$e']);
    }
  }

  Future<Map<String, dynamic>> deployToBoard({
    required String boardId,
    required PynqDeployPayload payload,
    String? bitstreamPathOverride,
  }) async {
    final body = payload.toJson();
    if (bitstreamPathOverride != null && bitstreamPathOverride.isNotEmpty) {
      body['bitstream_path'] = bitstreamPathOverride;
    }
    try {
      return await _controlApiService.proxyPynqDeploy(
        boardId,
        payload: body,
      );
    } catch (e) {
      throw PynqDeployException(
        error: 'Deploy failed',
        messages: ['$e'],
      );
    }
  }

  /// Poll the deployment status of a remote PYNQ Z2 board.
  ///
  /// Calls GET {boardBaseUrl}/hardware/pynq/status.
  /// Returns [PynqDeployJob] on success.
  Future<PynqDeployJob> getDeployStatus({
    required String boardId,
  }) async {
    try {
      return await _controlApiService.fetchPynqBoardStatus(boardId);
    } catch (e) {
      throw PynqDeployException(
        error: 'Status check failed',
        messages: ['$e'],
      );
    }
  }

  /// Run SITL verification on the remote PYNQ Z2 board.
  ///
  /// Calls POST {boardBaseUrl}/hardware/pynq/verify.
  /// Returns [PynqSitlVerifyResult] on success.
  Future<PynqSitlVerifyResult> runSitlVerification({
    required String boardId,
    List<double>? weights,
    Map<String, dynamic>? config,
  }) async {
    final body = <String, dynamic>{};
    if (weights != null) body['weights'] = weights;
    if (config != null) body['config'] = config;
    try {
      return await _controlApiService.proxyPynqVerify(
        boardId,
        payload: body,
      );
    } catch (e) {
      throw PynqDeployException(
        error: 'SITL verification failed',
        messages: ['$e'],
      );
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

class PynqDeployException implements Exception {
  final String error;
  final List<String> messages;

  PynqDeployException({
    required this.error,
    this.messages = const [],
  });

  @override
  String toString() {
    final parts = <String>[error, ...messages];
    return 'PynqDeployException: ${parts.join(" — ")}';
  }
}
