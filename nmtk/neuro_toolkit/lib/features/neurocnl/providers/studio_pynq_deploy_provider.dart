import 'dart:convert';

import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/models/dataset_sample.dart';
import 'package:neuro_toolkit/features/neurocnl/services/studio_pynq_deploy_service.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/api_provider.dart';

part 'studio_pynq_deploy_provider.g.dart';

/// Where the board is in the pair → provision → overlay → deploy → run chain.
///
/// Deliberately one flat phase list rather than a board-state field plus a busy
/// flag: every one of these blocks the next step, and the setup pane needs to
/// say which one is happening. `PynqBoardState` still carries the board's own
/// persisted state — this is what *this session* is doing to it.
enum StudioPynqDeployPhase {
  idle,
  validating,
  provisioning,
  installingOverlay,
  restartingRuntime,
  deploying,
  running,
  verifying,
  completed,
  failed,
}

/// What the board is stimulated with.
///
/// [datasetSample] is the default because it is the only source that produces a
/// meaningful result: a real evaluation sample, the same data the model was
/// scored against. [manualIndices] is the old behaviour, kept for probing
/// individual neurons and for networks with no dataset in the workspace.
enum StudioPynqInputSource { datasetSample, manualIndices }

class StudioPynqDeployState {
  const StudioPynqDeployState({
    this.phase = StudioPynqDeployPhase.idle,
    this.boards = const <PynqPairedBoard>[],
    this.selectedBoard,
    this.exportResult,
    this.deployAck,
    this.runResult,
    this.verifyResult,
    this.bitWidth = 8,
    this.timesteps = 1,
    this.timestepsChosenByUser = false,
    this.inputSpikesText = '0',
    this.inputSource = StudioPynqInputSource.datasetSample,
    this.sampleIndex = 0,
    this.datasetSample,
    this.datasetSampleIssue,
    this.activityMessage,
    this.errorMessage,
    this.overlayPackage,
    this.warningMessage,
    this.trainedNir,
    this.preparationKey,
  });

  /// The presentation window the trained model was evaluated over.
  ///
  /// The generated snnTorch pipeline runs `num_steps = 25` and reads out spike
  /// counts, so a board run of a real sample has to present it for the same
  /// number of steps to be comparable. At one timestep a correct network can
  /// legitimately fire nothing, which reads as a broken board.
  static const int datasetSampleTimesteps = 25;

  final StudioPynqDeployPhase phase;
  final List<PynqPairedBoard> boards;
  final PynqPairedBoard? selectedBoard;

  /// Verdict plus, when exportable, the payload the board needs.
  final PynqNetworkResponse? exportResult;

  /// Proof the overlay was loaded on real silicon — see [PynqDeployAck].
  final PynqDeployAck? deployAck;
  final PynqRunResult? runResult;
  final PynqSitlVerifyResult? verifyResult;
  final int bitWidth;
  final int timesteps;

  /// Whether [timesteps] was typed rather than defaulted. Loading a sample sets
  /// the presentation window for the user, but must never overwrite a number
  /// they chose themselves.
  final bool timestepsChosenByUser;
  final String inputSpikesText;
  final StudioPynqInputSource inputSource;
  final int sampleIndex;

  /// The evaluation sample currently loaded, or null when none has been
  /// fetched (or the workspace has no evaluation set).
  final DatasetSample? datasetSample;

  /// Why no sample is available, shown beside the picker. Not an error for the
  /// deploy as a whole: the manual field still works.
  final String? datasetSampleIssue;
  final String? activityMessage;
  final String? errorMessage;

  /// Set when Install Overlay found nothing to install, so the pane can explain
  /// which files the backend is missing instead of just failing.
  final PynqStagedOverlayPackage? overlayPackage;

  /// Non-fatal trouble, e.g. a user-space agent that would not restart. The step
  /// still succeeded, so this must not be surfaced as an error.
  final String? warningMessage;

  /// The trained NIR graph found in the workspace, or null when the network has
  /// not been trained (or the NIR Exporter node has not run).
  final PynqTrainedNir? trainedNir;

  /// Which (board, workspace, spec) the automatic preparation pass has already
  /// run for. It lives here rather than in the pane's widget state because that
  /// state is disposed when the user switches pipeline steps: walking to Review
  /// and back re-ran a validate and a board preflight that together take the
  /// better part of a minute, for an answer that had not changed.
  final String? preparationKey;

  /// Whether the payload the board would receive carries learned weights.
  ///
  /// False means the CNL spec's zeros: the deploy succeeds, the overlay loads,
  /// and nothing fires. This has to reach the user before they read a green
  /// result as a working model.
  bool get hasTrainedWeights => exportResult?.hasTrainedWeights ?? false;

  bool get isBusy => switch (phase) {
    StudioPynqDeployPhase.validating ||
    StudioPynqDeployPhase.provisioning ||
    StudioPynqDeployPhase.installingOverlay ||
    StudioPynqDeployPhase.restartingRuntime ||
    StudioPynqDeployPhase.deploying ||
    StudioPynqDeployPhase.running ||
    StudioPynqDeployPhase.verifying => true,
    _ => false,
  };

  bool get isExportable {
    final state = exportResult?.supportState;
    return state == PynqSupportState.exportable ||
        state == PynqSupportState.exportableWithWarnings;
  }

  /// A deploy needs a payload *and* a board that answered its preflight.
  bool get canDeploy =>
      exportResult?.deployPayload != null &&
      (selectedBoard?.isReady ?? false) &&
      !isBusy;

  /// Run and verify only mean anything once an overlay is configured with this
  /// network — before that the board agent answers "Overlay not deployed".
  bool get canRun => deployAck != null && !isBusy;

  /// The spike indices typed into the execution pane.
  ///
  /// Tolerant of commas, spaces and newlines because users paste these from
  /// notebooks; anything unparseable is dropped rather than failing the run.
  /// These are *indices*, not what the board receives — see [buildInputFrames].
  List<int> get inputSpikes => inputSpikesText
      .split(RegExp(r'[^0-9-]+'))
      .map((token) => int.tryParse(token))
      .whereType<int>()
      .toList(growable: false);

  /// How many input neurons the deployed network has, or 0 when unknown.
  ///
  /// The overlay has no neuron-count register — the layer chain in the deploy
  /// payload is the only place this number exists on either side.
  int get inputNeuronCount {
    final layers = exportResult?.deployPayload?.layers ?? const [];
    return layers.isEmpty ? 0 : layers.first.inputSize;
  }

  /// Expands the typed indices into what overlay-v2 actually consumes: one word
  /// per input neuron per timestep, 1 where that neuron spikes.
  ///
  /// The typed indices used to be sent verbatim, which is the v1 protocol. The
  /// v2 engine reads a whole frame per timestep and both the board worker and
  /// the simulator reject a short transfer outright, so every run failed with
  /// `Expected N input words`. The field stays index-based because typing three
  /// numbers beats typing 784 zeros; the expansion happens here.
  ///
  /// Each named neuron spikes on *every* timestep — the same static-input scheme
  /// the trained snnTorch network was evaluated under, where one image is
  /// presented repeatedly.
  ///
  /// Throws [ArgumentError] naming the offending index when one is out of range,
  /// rather than dropping it: an index past the input width is a typo worth
  /// reporting, and silently ignoring it produced a run that looked fine and
  /// stimulated the wrong neurons.
  /// Whether a run can proceed: a dataset run needs a loaded sample, a manual
  /// run needs at least one index (an all-silent frame is a DMA underrun).
  bool get hasStimulus =>
      usingDatasetSample ? datasetSample != null : inputSpikes.isNotEmpty;

  bool get usingDatasetSample =>
      inputSource == StudioPynqInputSource.datasetSample;

  List<int> buildInputFrames() {
    final width = inputNeuronCount;
    if (width <= 0) {
      throw ArgumentError(
        'This deploy carries no layer descriptors, so the board cannot be told '
        'how wide an input frame is. Redeploy the network.',
      );
    }

    final sample = datasetSample;
    if (usingDatasetSample && sample != null) {
      if (sample.inputWidth != width) {
        throw ArgumentError(
          'This sample has ${sample.inputWidth} values but the network takes '
          '$width inputs, so it cannot be run as-is. Pick a workspace whose '
          'evaluation set matches this network.',
        );
      }
      // Presented unchanged on every timestep — rate coding over a static
      // frame, which is how the model was trained and evaluated.
      final frames = List<int>.filled(width * timesteps, 0);
      for (var timestep = 0; timestep < timesteps; timestep++) {
        final base = timestep * width;
        for (var index = 0; index < width; index++) {
          frames[base + index] = sample.inputSpikes[index] > 0 ? 1 : 0;
        }
      }
      return frames;
    }

    final indices = inputSpikes;
    final tooLarge = indices.where((index) => index < 0 || index >= width);
    if (tooLarge.isNotEmpty) {
      throw ArgumentError(
        'Input neuron ${tooLarge.first} does not exist — this network has '
        '$width input neurons, numbered 0 to ${width - 1}.',
      );
    }
    final frames = List<int>.filled(width * timesteps, 0);
    for (var timestep = 0; timestep < timesteps; timestep++) {
      final base = timestep * width;
      for (final index in indices) {
        frames[base + index] = 1;
      }
    }
    return frames;
  }

  StudioPynqDeployState copyWith({
    StudioPynqDeployPhase? phase,
    List<PynqPairedBoard>? boards,
    PynqPairedBoard? selectedBoard,
    PynqNetworkResponse? exportResult,
    PynqDeployAck? deployAck,
    PynqRunResult? runResult,
    PynqSitlVerifyResult? verifyResult,
    int? bitWidth,
    int? timesteps,
    bool? timestepsChosenByUser,
    String? inputSpikesText,
    StudioPynqInputSource? inputSource,
    int? sampleIndex,
    DatasetSample? datasetSample,
    String? datasetSampleIssue,
    String? activityMessage,
    String? errorMessage,
    PynqStagedOverlayPackage? overlayPackage,
    String? warningMessage,
    PynqTrainedNir? trainedNir,
    String? preparationKey,
    bool clearSelectedBoard = false,
    bool clearErrorMessage = false,
    bool clearWarningMessage = false,
    bool clearOverlayPackage = false,
    bool clearDeployAck = false,
    bool clearResults = false,
    bool clearDatasetSample = false,
    bool clearDatasetSampleIssue = false,
  }) {
    return StudioPynqDeployState(
      phase: phase ?? this.phase,
      boards: boards ?? this.boards,
      selectedBoard: clearSelectedBoard
          ? null
          : (selectedBoard ?? this.selectedBoard),
      exportResult: exportResult ?? this.exportResult,
      deployAck: clearDeployAck ? null : (deployAck ?? this.deployAck),
      runResult: clearResults ? null : (runResult ?? this.runResult),
      verifyResult: clearResults ? null : (verifyResult ?? this.verifyResult),
      bitWidth: bitWidth ?? this.bitWidth,
      timesteps: timesteps ?? this.timesteps,
      timestepsChosenByUser:
          timestepsChosenByUser ?? this.timestepsChosenByUser,
      inputSpikesText: inputSpikesText ?? this.inputSpikesText,
      inputSource: inputSource ?? this.inputSource,
      sampleIndex: sampleIndex ?? this.sampleIndex,
      datasetSample: clearDatasetSample
          ? null
          : (datasetSample ?? this.datasetSample),
      datasetSampleIssue: clearDatasetSampleIssue
          ? null
          : (datasetSampleIssue ?? this.datasetSampleIssue),
      activityMessage: activityMessage ?? this.activityMessage,
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
      overlayPackage: clearOverlayPackage
          ? null
          : (overlayPackage ?? this.overlayPackage),
      warningMessage: clearWarningMessage
          ? null
          : (warningMessage ?? this.warningMessage),
      trainedNir: trainedNir ?? this.trainedNir,
      preparationKey: preparationKey ?? this.preparationKey,
    );
  }
}

@riverpod
class StudioPynqDeployController extends _$StudioPynqDeployController {
  @override
  StudioPynqDeployState build() => const StudioPynqDeployState();

  StudioPynqDeployService get _service =>
      ref.read(studioPynqDeployServiceProvider);

  void _fail(Object error) {
    if (!ref.mounted) return;
    state = state.copyWith(
      phase: StudioPynqDeployPhase.failed,
      errorMessage: error is StudioPynqDeployException
          ? error.message
          : error.toString(),
    );
  }

  void selectBoard(PynqPairedBoard? board) {
    if (board == null) {
      state = state.copyWith(
        clearSelectedBoard: true,
        clearDeployAck: true,
        clearResults: true,
      );
      return;
    }
    // A different board has its own overlay and its own configured network, so
    // carrying the previous board's deploy ack or results forward would let the
    // UI attribute one board's numbers to another.
    final switchedBoard = state.selectedBoard?.id != board.id;
    state = state.copyWith(
      selectedBoard: board,
      clearDeployAck: switchedBoard,
      clearResults: switchedBoard,
      clearErrorMessage: true,
    );
  }

  void setBitWidth(int bitWidth) {
    // Changing quantization invalidates the payload the board was given.
    state = state.copyWith(
      bitWidth: bitWidth,
      clearDeployAck: true,
      clearResults: true,
    );
  }

  void setTimesteps(int timesteps) {
    state = state.copyWith(
      timesteps: timesteps < 1 ? 1 : timesteps,
      timestepsChosenByUser: true,
    );
  }

  void setInputSpikesText(String value) {
    state = state.copyWith(inputSpikesText: value);
  }

  /// Claims the automatic preparation pass for [key], or refuses if it has
  /// already run for that key. Survives the pane being rebuilt or remounted.
  bool claimPreparation(String key) {
    if (state.preparationKey == key) return false;
    state = state.copyWith(preparationKey: key);
    return true;
  }

  void setInputSource(StudioPynqInputSource source) {
    state = state.copyWith(inputSource: source, clearResults: true);
  }

  /// Loads evaluation sample [index] from the workspace.
  ///
  /// Also sets the presentation window the first time a sample arrives: the
  /// board reads out spike counts, so a single timestep can legitimately fire
  /// nothing. A window the user typed themselves is left alone.
  Future<void> loadDatasetSample(String workspaceFolder, {int? index}) async {
    final requested = index ?? state.sampleIndex;
    try {
      final sample = await _service.fetchDatasetSample(
        workspaceFolder,
        index: requested,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        datasetSample: sample,
        sampleIndex: sample.sampleIndex,
        inputSource: StudioPynqInputSource.datasetSample,
        timesteps: state.timestepsChosenByUser
            ? state.timesteps
            : StudioPynqDeployState.datasetSampleTimesteps,
        clearDatasetSampleIssue: true,
        // The stimulus changed, so a previous run's numbers describe something
        // else.
        clearResults: true,
      );
    } catch (error) {
      if (!ref.mounted) return;
      state = state.copyWith(
        datasetSampleIssue: error is StudioPynqDeployException
            ? error.message
            : '$error',
        clearDatasetSample: true,
      );
    }
  }

  /// Loads the paired boards and resolves the one launcher control will act on.
  Future<void> loadBoards() async {
    try {
      final boards = await _service.fetchBoards();
      final resolved = await _service.resolveSelectedBoard();
      if (!ref.mounted) return;
      state = state.copyWith(
        boards: boards,
        selectedBoard: resolved,
        clearSelectedBoard: resolved == null,
      );
    } catch (error) {
      _fail(error);
    }
  }

  /// Checks the spec and builds the payload, carrying trained weights if any.
  ///
  /// [workspaceFolder] is what makes a deploy meaningful: without a trained NIR
  /// graph from it the payload's weights come from the CNL spec, which stores
  /// tensor shape only, so the board would load the overlay and fire nothing.
  /// Passing null deliberately skips the lookup (used by callers with no
  /// workspace context); the resulting state reports zero weights rather than
  /// implying trained ones.
  Future<void> validate(String spec, {String? workspaceFolder}) async {
    state = state.copyWith(
      phase: StudioPynqDeployPhase.validating,
      activityMessage: 'Checking the network against the PYNQ-Z2 overlay.',
      clearErrorMessage: true,
    );
    try {
      final trainedNir = workspaceFolder == null
          ? state.trainedNir
          : await _service.fetchLatestTrainedNir(workspaceFolder);
      if (!ref.mounted) return;
      final result = await _service.validate(
        spec: spec,
        bitWidth: state.bitWidth,
        trainedNirBase64: trainedNir?.isUsable == true
            ? trainedNir!.nirBase64
            : null,
      );
      if (!ref.mounted) return;
      // Re-validating is not evidence the board's copy went stale. This runs
      // whenever the Deploy step is opened, so discarding the ack unconditionally
      // threw away a deploy the board was still holding — every trip to Review
      // and back forced a redeploy and wiped the results.
      final samePayload = _samePayload(
        state.exportResult?.deployPayload,
        result.deployPayload,
      );
      state = state.copyWith(
        exportResult: result,
        trainedNir: trainedNir,
        phase: StudioPynqDeployPhase.idle,
        activityMessage: result.trainedWeights?.detail.isNotEmpty == true
            ? '${result.supportState.label} — ${result.trainedWeights!.detail}'
            : result.supportState.label,
        clearDeployAck: !samePayload,
        clearResults: !samePayload,
      );
    } catch (error) {
      _fail(error);
    }
  }

  /// Whether two builds of the deploy payload would put the same thing on the
  /// board. Compared as JSON because that is exactly what is posted.
  static bool _samePayload(
    PynqDeployPayload? before,
    PynqDeployPayload? after,
  ) {
    if (before == null || after == null) return false;
    return jsonEncode(before.toJson()) == jsonEncode(after.toJson());
  }

  /// Re-runs the board's own preflight and reports what it said.
  Future<void> checkReadiness() async {
    final board = state.selectedBoard;
    if (board == null) {
      state = state.copyWith(
        errorMessage: 'Pair a PYNQ-Z2 board first, under Manage Targets.',
      );
      return;
    }
    state = state.copyWith(
      phase: StudioPynqDeployPhase.validating,
      activityMessage: 'Checking ${board.displayName}.',
      clearErrorMessage: true,
    );
    try {
      final refreshed = await _service.checkBoardReadiness(board.id);
      if (!ref.mounted) return;
      state = state.copyWith(
        selectedBoard: refreshed,
        phase: StudioPynqDeployPhase.idle,
        activityMessage: refreshed.lastPreflightMessage.trim().isEmpty
            ? 'Board state: ${refreshed.state.label}.'
            : refreshed.lastPreflightMessage.trim(),
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> provisionBoard() => _runBoardOperation(
    phase: StudioPynqDeployPhase.provisioning,
    activity: (board) =>
        'Installing the board runtime on ${board.displayName}. '
        'A first install takes around two minutes.',
    operation: (id) => _service.provisionBoard(id),
  );

  Future<void> installOverlay() => _runBoardOperation(
    phase: StudioPynqDeployPhase.installingOverlay,
    activity: (board) => 'Copying the FPGA overlay to ${board.displayName}.',
    operation: (id) => _service.installOverlay(id),
  );

  Future<void> restartRuntime() => _runBoardOperation(
    phase: StudioPynqDeployPhase.restartingRuntime,
    activity: (board) => 'Restarting the runtime on ${board.displayName}.',
    operation: (id) => _service.restartRuntime(id),
  );

  /// Shared shape for provision / install-overlay / restart.
  ///
  /// All three answer with the updated board plus optional `error` / `warning`
  /// *inside a 200*, so success cannot be inferred from the call returning —
  /// only from the absence of `error`.
  Future<void> _runBoardOperation({
    required StudioPynqDeployPhase phase,
    required String Function(PynqPairedBoard board) activity,
    required Future<PynqBoardOperationResult> Function(String boardId)
    operation,
  }) async {
    final board = state.selectedBoard;
    if (board == null) {
      state = state.copyWith(
        errorMessage: 'Pair a PYNQ-Z2 board first, under Manage Targets.',
      );
      return;
    }
    state = state.copyWith(
      phase: phase,
      activityMessage: activity(board),
      clearErrorMessage: true,
      clearWarningMessage: true,
      clearOverlayPackage: true,
    );
    try {
      final result = await operation(board.id);
      if (!ref.mounted) return;
      state = state.copyWith(
        selectedBoard: result.board,
        phase: result.succeeded
            ? StudioPynqDeployPhase.idle
            : StudioPynqDeployPhase.failed,
        activityMessage: result.board.lastPreflightMessage.trim().isEmpty
            ? 'Board state: ${result.board.state.label}.'
            : result.board.lastPreflightMessage.trim(),
        errorMessage: result.error,
        warningMessage: result.warning,
        overlayPackage: result.localOverlayPackage,
      );
    } catch (error) {
      _fail(error);
    }
  }

  /// Sends the validated payload to the board and loads the overlay.
  Future<void> deploy() async {
    final board = state.selectedBoard;
    final payload = state.exportResult?.deployPayload;
    if (board == null) {
      state = state.copyWith(
        errorMessage: 'Pair a PYNQ-Z2 board first, under Manage Targets.',
      );
      return;
    }
    if (payload == null) {
      state = state.copyWith(
        errorMessage:
            'Run the PYNQ check first — the board payload is only built for a '
            'network that fits the overlay.',
      );
      return;
    }
    state = state.copyWith(
      phase: StudioPynqDeployPhase.deploying,
      activityMessage:
          'Loading the overlay on ${board.displayName} and writing '
          '${payload.weightCount} weights.',
      clearErrorMessage: true,
      clearResults: true,
    );
    try {
      final ack = await _service.deploy(boardId: board.id, payload: payload);
      if (!ref.mounted) return;
      state = state.copyWith(
        deployAck: ack,
        phase: StudioPynqDeployPhase.idle,
        activityMessage: ack.overlayVersion == null
            ? ack.message
            : '${ack.message} Overlay ${ack.overlayVersion}.',
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> run() async {
    final board = state.selectedBoard;
    if (board == null || state.deployAck == null) {
      state = state.copyWith(
        errorMessage: 'Deploy to the board before running.',
      );
      return;
    }
    if (!state.hasStimulus) {
      // The board's DMA path treats an empty transfer as an underrun, so this
      // would fail on the board with a much less helpful message.
      state = state.copyWith(
        errorMessage: state.usingDatasetSample
            ? 'Load an evaluation sample first, or switch to typing input '
                  'neurons — the board cannot run an empty frame.'
            : 'Name at least one input neuron — an all-silent frame is a DMA '
                  'underrun on the board.',
      );
      return;
    }
    final List<int> frames;
    try {
      frames = state.buildInputFrames();
    } on ArgumentError catch (error) {
      state = state.copyWith(errorMessage: '${error.message}');
      return;
    }
    final sample = state.datasetSample;
    state = state.copyWith(
      phase: StudioPynqDeployPhase.running,
      activityMessage: state.usingDatasetSample && sample != null
          ? 'Running sample ${sample.sampleIndex} (${sample.spikeCount} of '
                '${sample.inputWidth} inputs spiking) for ${state.timesteps} '
                'timestep(s) on ${board.displayName}.'
          : 'Running ${state.inputSpikes.length} of ${state.inputNeuronCount} '
                'input neurons for ${state.timesteps} timestep(s) on '
                '${board.displayName}.',
      clearErrorMessage: true,
    );
    try {
      final result = await _service.run(
        boardId: board.id,
        inputSpikes: frames,
        timesteps: state.timesteps,
      );
      if (!ref.mounted) return;
      state = state.copyWith(
        runResult: result,
        phase: StudioPynqDeployPhase.completed,
        // The count, never the stream's length: overlay-v2 sends one word per
        // output neuron per timestep, so a silent run is a full-length list of
        // zeros and reporting its length said "10 output spikes" for a network
        // that fired nothing.
        activityMessage:
            '${result.totalSpikes} output spike(s) in '
            '${result.executionTimeUs.toStringAsFixed(1)} µs.',
      );
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> verify() async {
    final board = state.selectedBoard;
    if (board == null) {
      state = state.copyWith(
        errorMessage: 'Pair a PYNQ-Z2 board first, under Manage Targets.',
      );
      return;
    }
    state = state.copyWith(
      phase: StudioPynqDeployPhase.verifying,
      activityMessage: 'Verifying ${board.displayName} against known cases.',
      clearErrorMessage: true,
    );
    try {
      final result = await _service.verify(boardId: board.id);
      if (!ref.mounted) return;
      state = state.copyWith(
        verifyResult: result,
        phase: StudioPynqDeployPhase.completed,
        activityMessage: result.summary,
      );
    } catch (error) {
      _fail(error);
    }
  }
}

final studioPynqDeployProvider = studioPynqDeployControllerProvider;
