import 'dart:convert';

import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/dataset_sample.dart';
import 'package:neuro_toolkit/features/neurocnl/models/trained_nir_artifact.dart';
import 'package:neuro_toolkit/features/neurocnl/services/api_client.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_target_registry_service.dart';

class StudioPynqDeployException implements Exception {
  const StudioPynqDeployException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A trained NIR graph discovered in the workspace.
///
/// The simulator run path needs the same artifact, so the model itself lives in
/// `models/trained_nir_artifact.dart`; this name is kept for the PYNQ call sites.
typedef PynqTrainedNir = TrainedNirArtifact;

/// Everything the Studio Deploy step needs to put a network on a PYNQ-Z2.
///
/// Two services sit behind this, and the split matters. The **backend** decides
/// whether the network fits overlay-v1 and, if it does, builds the deploy
/// payload — quantized weights, thresholds and the MMIO register map. **Launcher
/// control** owns the board: it reaches it over SSH to provision the agent and
/// install the overlay, and proxies deploy/run/verify to the agent's own HTTP
/// API. Neither half can do the other's job, so the flow always crosses both.
class StudioPynqDeployService {
  StudioPynqDeployService({
    required ApiClient apiClient,
    required StudioTargetRegistryService targetRegistryService,
  }) : _apiClient = apiClient,
       _registry = targetRegistryService;

  final ApiClient _apiClient;
  final StudioTargetRegistryService _registry;

  /// Checks the spec against overlay-v1 and, when it fits, builds the payload.
  ///
  /// The verdict and the payload come from the same round trip by design: the
  /// payload only exists for an exportable network, so a caller that got one
  /// knows the capacity gates passed.
  ///
  /// [trainedNirBase64] supplies the learned weights. Omitting it is not a
  /// neutral default — the payload's weights then come from the CNL spec, which
  /// stores tensor shape only, so every weight is zero.
  Future<PynqNetworkResponse> validate({
    required String spec,
    required int bitWidth,
    String? trainedNirBase64,
  }) async {
    final json = await _apiClient.getPynqDeployability(
      spec,
      bitWidth: bitWidth,
      trainedNirBase64: trainedNirBase64,
    );
    return PynqNetworkResponse.fromJson(json);
  }

  /// Fetches the newest trained NIR graph for a workspace, or null if there is
  /// none.
  ///
  /// Absence is the normal state for a network that has not been trained yet, so
  /// it is not an error — the caller falls back to a zero-weight deploy and says
  /// so. A transport failure is also swallowed for the same reason: the deploy
  /// path still works, it just carries no learned values, and blocking hardware
  /// bring-up because an artifact lookup failed would be worse.
  Future<PynqTrainedNir?> fetchLatestTrainedNir(String workspaceFolder) async {
    try {
      final json = await _apiClient.latestTrainedNir(workspaceFolder);
      return TrainedNirArtifact.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  /// Fetches evaluation sample [index] from the workspace as an input frame.
  ///
  /// Unlike [fetchLatestTrainedNir], a failure here is *not* swallowed: the
  /// caller is about to stimulate the board and needs to know it is running
  /// something other than what it asked for. The message is shown next to the
  /// picker, and the manual index field stays available as the fallback.
  Future<DatasetSample> fetchDatasetSample(
    String workspaceFolder, {
    int index = 0,
  }) async {
    try {
      final json = await _apiClient.datasetSample(
        workspaceFolder,
        index: index,
      );
      return DatasetSample.fromJson(json);
    } on ApiException catch (error) {
      // The backend's `detail` is written for the user and names the step that
      // produces the file; `ApiException(404): {"detail": …}` is not.
      throw StudioPynqDeployException(_detailOf(error));
    }
  }

  /// Pulls the human-readable `detail` out of a FastAPI error body.
  static String _detailOf(ApiException error) {
    try {
      final decoded = jsonDecode(error.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is String && detail.trim().isNotEmpty) return detail;
      }
    } catch (_) {
      // Not JSON — fall through to the raw body, which is still better than
      // the exception's own toString().
    }
    return error.body.trim().isEmpty ? '$error' : error.body;
  }

  Future<List<PynqPairedBoard>> fetchBoards() => _registry.fetchPynqBoards();

  Future<PynqPairedBoard?> resolveSelectedBoard() async {
    final boards = await _registry.fetchPynqBoards();
    if (boards.isEmpty) return null;
    final selectedId = await _registry.fetchSelectedPynqBoardId();
    for (final board in boards) {
      if (board.id == selectedId) return board;
    }
    for (final board in boards) {
      if (board.isDefault) return board;
    }
    return boards.first;
  }

  Future<void> selectBoard(String boardId) =>
      _registry.selectPynqBoard(boardId);

  Future<PynqPairedBoard> checkBoardReadiness(String boardId) async {
    return (await _registry.fetchPynqBoardPreflight(boardId)).board;
  }

  Future<PynqPairedBoard> testBoardConnection(String boardId) =>
      _registry.testPynqBoardConnection(boardId);

  Future<PynqBoardOperationResult> provisionBoard(String boardId) =>
      _registry.provisionPynqBoard(boardId);

  Future<PynqBoardOperationResult> installOverlay(String boardId) =>
      _registry.installPynqOverlay(boardId);

  Future<PynqBoardOperationResult> restartRuntime(String boardId) =>
      _registry.restartPynqRuntime(boardId);

  /// Loads the overlay and writes the network into it.
  ///
  /// Refuses a simulator-satisfied deploy: without `require_hardware` the board
  /// agent happily answers 200 from its pure-Python fallback, which is
  /// indistinguishable from silicon in every field except `runtime_mode`. That
  /// would let the UI claim hardware it never touched, so this treats it as an
  /// error even though the HTTP call succeeded.
  Future<PynqDeployAck> deploy({
    required String boardId,
    required PynqDeployPayload payload,
  }) async {
    final ack = await _registry.deployPynqNetwork(
      boardId: boardId,
      deployPayload: payload.toJson(),
    );
    if (!ack.isHardware) {
      throw StudioPynqDeployException(
        'The board runtime served this deploy from its software simulator '
        '(runtime_mode: ${ack.runtimeMode.name}), so nothing reached the FPGA. '
        'Check that the board is powered and that Install Overlay has run.',
      );
    }
    return ack;
  }

  Future<PynqRunResult> run({
    required String boardId,
    required List<int> inputSpikes,
    required int timesteps,
  }) {
    return _registry.runPynqNetwork(
      boardId: boardId,
      inputSpikes: inputSpikes,
      timesteps: timesteps,
    );
  }

  Future<PynqSitlVerifyResult> verify({required String boardId}) =>
      _registry.verifyPynqNetwork(boardId: boardId);
}
