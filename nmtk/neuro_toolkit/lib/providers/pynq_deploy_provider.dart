import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/services/pynq_deploy_service.dart';

/// Step in the PYNQ deployment workflow.
enum PynqDeployStep {
  idle,
  checking,
  checked,
  deploying,
  polling,
  verifying,
  done,
  error,
}

enum PynqBoardOperation {
  savingPairing,
  deletingPairing,
  testingSsh,
  provisioningRuntime,
  installingOverlay,
  checkingReadiness,
  restartingRuntime,
}

class PynqDeployProvider with ChangeNotifier {
  PynqDeployProvider({PynqDeployService? service})
      : _service = service ?? PynqDeployService() {
    unawaited(loadPairedBoards(notifyListeners: false));
  }

  final PynqDeployService _service;

  PynqDeployStep _currentStep = PynqDeployStep.idle;
  PynqDeployStep get currentStep => _currentStep;

  PynqNetworkResponse? _exportResult;
  PynqNetworkResponse? get exportResult => _exportResult;

  PynqDeployJob? _deployJob;
  PynqDeployJob? get deployJob => _deployJob;

  PynqSitlVerifyResult? _sitlResult;
  PynqSitlVerifyResult? get sitlResult => _sitlResult;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  List<PynqPairedBoard> _pairedBoards = <PynqPairedBoard>[];
  List<PynqPairedBoard> get pairedBoards =>
      List<PynqPairedBoard>.unmodifiable(_pairedBoards);

  String? _selectedBoardId;
  String? get selectedBoardId => _selectedBoardId;
  PynqPairedBoard? get selectedBoard {
    if (_selectedBoardId == null) {
      return null;
    }
    for (final board in _pairedBoards) {
      if (board.id == _selectedBoardId) {
        return board;
      }
    }
    return null;
  }

  bool _loadingBoards = false;
  bool get loadingBoards => _loadingBoards;

  PynqBoardOperation? _activeBoardOperation;
  PynqBoardOperation? get activeBoardOperation => _activeBoardOperation;
  bool get boardOperationInProgress => _activeBoardOperation != null;

  String? _boardFeedbackMessage;
  String? get boardFeedbackMessage => _boardFeedbackMessage;

  String _bitstreamPathOverride = '';
  String get bitstreamPathOverride => _bitstreamPathOverride;

  bool _runSitl = false;
  bool get runSitl => _runSitl;

  Timer? _pollTimer;

  PynqDeployPayload? get deployPayload => _exportResult?.deployPayload;

  Future<void> loadPairedBoards({bool notifyListeners = true}) async {
    _loadingBoards = true;
    if (notifyListeners) {
      this.notifyListeners();
    }
    try {
      _pairedBoards = await _service.fetchPairedBoards();
      if (_pairedBoards.isEmpty) {
        _selectedBoardId = null;
      } else if (_selectedBoardId == null ||
          !_pairedBoards.any((board) => board.id == _selectedBoardId)) {
        _selectedBoardId = _pairedBoards.first.id;
      }
      _errorMessage = null;
    } on PynqDeployException catch (e) {
      _errorMessage = e.toString();
    } finally {
      _loadingBoards = false;
      if (notifyListeners) {
        this.notifyListeners();
      }
    }
  }

  void selectBoard(String? boardId) {
    _selectedBoardId = boardId;
    notifyListeners();
  }

  void _upsertBoard(PynqPairedBoard board) {
    final index = _pairedBoards.indexWhere((item) => item.id == board.id);
    if (index == -1) {
      _pairedBoards = <PynqPairedBoard>[..._pairedBoards, board];
    } else {
      final updated = List<PynqPairedBoard>.from(_pairedBoards);
      updated[index] = board;
      _pairedBoards = updated;
    }
    _selectedBoardId ??= board.id;
  }

  void _replaceBoard(PynqPairedBoard board) {
    final index = _pairedBoards.indexWhere((item) => item.id == board.id);
    if (index == -1) {
      _pairedBoards = <PynqPairedBoard>[..._pairedBoards, board];
      return;
    }
    final updated = List<PynqPairedBoard>.from(_pairedBoards);
    updated[index] = board;
    _pairedBoards = updated;
  }

  void _startBoardOperation(
    PynqBoardOperation operation,
    String message, {
    PynqBoardState? optimisticState,
  }) {
    _activeBoardOperation = operation;
    _boardFeedbackMessage = message;
    _errorMessage = null;
    final board = selectedBoard;
    if (board != null && optimisticState != null) {
      _replaceBoard(
        board.copyWith(
          state: optimisticState,
          lastPreflightMessage: message,
        ),
      );
    }
    notifyListeners();
  }

  void _finishBoardOperation(String message) {
    _activeBoardOperation = null;
    _boardFeedbackMessage = message;
    notifyListeners();
  }

  void _failBoardOperation(
    String message, {
    PynqBoardState? fallbackState,
  }) {
    _activeBoardOperation = null;
    _boardFeedbackMessage = message;
    final board = selectedBoard;
    if (board != null && fallbackState != null) {
      _replaceBoard(
        board.copyWith(
          state: fallbackState,
          lastPreflightMessage: message,
        ),
      );
    }
    notifyListeners();
  }

  Future<void> savePairedBoard({
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
    _startBoardOperation(
      PynqBoardOperation.savingPairing,
      boardId == null || boardId.isEmpty
          ? 'Saving paired board details.'
          : 'Updating paired board details.',
    );
    try {
      final board = await _service.savePairedBoard(
        boardId: boardId,
        displayName: displayName,
        host: host,
        sshPort: sshPort,
        username: username,
        authMode: authMode,
        credentialRef: credentialRef,
        password: password,
        sshKeyPath: sshKeyPath,
        overlayVersion: overlayVersion,
      );
      _upsertBoard(board);
      _selectedBoardId = board.id;
      _errorMessage = null;
      _finishBoardOperation(
        'Paired board saved. You can now test SSH or provision the runtime.',
      );
    } on PynqDeployException catch (e) {
      _errorMessage = e.toString();
      _failBoardOperation('Failed to save paired board details.');
    }
  }

  Future<void> deleteSelectedBoard() async {
    final boardId = _selectedBoardId;
    if (boardId == null) {
      return;
    }
    _startBoardOperation(
      PynqBoardOperation.deletingPairing,
      'Removing paired board from launcher settings.',
    );
    try {
      await _service.deletePairedBoard(boardId);
      _pairedBoards = _pairedBoards
          .where((board) => board.id != boardId)
          .toList(growable: false);
      _selectedBoardId = _pairedBoards.isEmpty ? null : _pairedBoards.first.id;
      _errorMessage = null;
      _finishBoardOperation('Paired board removed.');
    } on PynqDeployException catch (e) {
      _errorMessage = e.toString();
      _failBoardOperation('Failed to remove paired board.');
    }
  }

  Future<void> testSelectedBoardConnectivity() async {
    final board = selectedBoard;
    if (board == null) {
      _errorMessage = 'Pair a board before running connectivity checks.';
      notifyListeners();
      return;
    }
    _startBoardOperation(
      PynqBoardOperation.testingSsh,
      'Testing SSH connectivity. Watch the launcher terminal for SSH step logs.',
    );
    try {
      final updated = await _service.testBoardConnectivity(boardId: board.id);
      _upsertBoard(updated);
      _errorMessage = null;
      _finishBoardOperation(
        'SSH connectivity succeeded. The board is reachable.',
      );
    } on PynqDeployException catch (e) {
      _errorMessage = e.toString();
      _failBoardOperation(
        'SSH connectivity test failed.',
        fallbackState: PynqBoardState.error,
      );
    }
  }

  Future<void> provisionSelectedBoard() async {
    final board = selectedBoard;
    if (board == null) {
      _errorMessage = 'Pair a board before provisioning the runtime.';
      notifyListeners();
      return;
    }
    _startBoardOperation(
      PynqBoardOperation.provisioningRuntime,
      'Provisioning runtime. Watch the launcher terminal for bundle upload and installer steps.',
      optimisticState: PynqBoardState.provisioning,
    );
    try {
      final updated = await _service.provisionBoard(boardId: board.id);
      _upsertBoard(updated);
      _errorMessage = null;
      final completionMessage = switch (updated.state) {
        PynqBoardState.overlayMissing =>
          'Runtime provisioning finished. Runtime is installed; install overlay assets next.',
        PynqBoardState.degradedOptionalCapability =>
          'Runtime provisioning finished in degraded mode. Review the readiness message below for the next step.',
        _ =>
          'Runtime provisioning finished. Check the board state and readiness message below.',
      };
      _finishBoardOperation(completionMessage);
    } on PynqDeployException catch (e) {
      _errorMessage = e.toString();
      _failBoardOperation(
        'Runtime provisioning failed. Review the launcher terminal and board message below.',
        fallbackState: PynqBoardState.provisionFailed,
      );
    }
  }

  Future<void> installOverlayForSelectedBoard() async {
    final board = selectedBoard;
    if (board == null) {
      _errorMessage = 'Pair a board before installing overlay assets.';
      notifyListeners();
      return;
    }
    _startBoardOperation(
      PynqBoardOperation.installingOverlay,
      'Installing overlay assets. Watch the launcher terminal for copy steps.',
    );
    try {
      final updated = await _service.installOverlay(boardId: board.id);
      _upsertBoard(updated);
      _errorMessage = null;
      final completionMessage = switch (updated.state) {
        PynqBoardState.overlayMissing =>
          'Overlay installation did not start because the local staged overlay package is missing or incomplete.',
        _ => 'Overlay installation finished. Run readiness again if needed.',
      };
      _finishBoardOperation(completionMessage);
    } on PynqDeployException catch (e) {
      _errorMessage = e.toString();
      _failBoardOperation(
        'Overlay installation failed.',
        fallbackState: PynqBoardState.overlayMissing,
      );
    }
  }

  Future<void> refreshSelectedBoardPreflight() async {
    final board = selectedBoard;
    if (board == null) {
      _errorMessage = 'Select a paired board to check readiness.';
      notifyListeners();
      return;
    }
    _startBoardOperation(
      PynqBoardOperation.checkingReadiness,
      'Checking board readiness. Watch the launcher terminal for runtime checks.',
    );
    try {
      final updated = await _service.refreshBoardPreflight(boardId: board.id);
      _upsertBoard(updated);
      _errorMessage = null;
      _finishBoardOperation(
        'Readiness check completed. Review the board state and preflight message below.',
      );
    } on PynqDeployException catch (e) {
      _errorMessage = e.toString();
      _failBoardOperation(
        'Readiness check failed.',
        fallbackState: PynqBoardState.error,
      );
    }
  }

  Future<void> restartSelectedBoardRuntime() async {
    final board = selectedBoard;
    if (board == null) {
      _errorMessage = 'Select a paired board to restart the runtime.';
      notifyListeners();
      return;
    }
    _startBoardOperation(
      PynqBoardOperation.restartingRuntime,
      'Restarting board runtime. Watch the launcher terminal for system service steps.',
    );
    try {
      final updated = await _service.restartRuntime(boardId: board.id);
      _upsertBoard(updated);
      _errorMessage = null;
      _finishBoardOperation(
        'Runtime restart completed. Readiness was refreshed afterward.',
      );
    } on PynqDeployException catch (e) {
      _errorMessage = e.toString();
      _failBoardOperation(
        'Runtime restart failed.',
        fallbackState: PynqBoardState.error,
      );
    }
  }

  Future<void> checkExportability({
    required String spec,
    required int weightBitWidth,
  }) async {
    _currentStep = PynqDeployStep.checking;
    _errorMessage = null;
    _exportResult = null;
    _deployJob = null;
    _sitlResult = null;
    notifyListeners();

    try {
      _exportResult = await _service.checkExportability(
        spec: spec,
        weightBitWidth: weightBitWidth,
      );
      _bitstreamPathOverride =
          _exportResult?.deployPayload?.bitstreamPath ?? '';
      _currentStep = PynqDeployStep.checked;
      notifyListeners();
    } on PynqDeployException catch (e) {
      _currentStep = PynqDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    } catch (e) {
      _currentStep = PynqDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  void setBitstreamPathOverride(String value) {
    _bitstreamPathOverride = value;
    notifyListeners();
  }

  void setRunSitl(bool value) {
    _runSitl = value;
    notifyListeners();
  }

  Future<void> startDeploy() async {
    final board = selectedBoard;
    if (board == null) {
      _currentStep = PynqDeployStep.error;
      _errorMessage = 'Select a paired board before deploy.';
      notifyListeners();
      return;
    }
    if (deployPayload == null) {
      _currentStep = PynqDeployStep.error;
      _errorMessage =
          'No validated deploy payload available. Run exportability first.';
      notifyListeners();
      return;
    }

    _currentStep = PynqDeployStep.deploying;
    _errorMessage = null;
    _deployJob = null;
    _sitlResult = null;
    notifyListeners();

    try {
      await _service.deployToBoard(
        boardId: board.id,
        payload: deployPayload!,
        bitstreamPathOverride:
            _bitstreamPathOverride.isNotEmpty ? _bitstreamPathOverride : null,
      );
      _currentStep = PynqDeployStep.polling;
      notifyListeners();
      _startPolling(board.id);
    } on PynqDeployException catch (e) {
      _currentStep = PynqDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    } catch (e) {
      _currentStep = PynqDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  void _startPolling(String boardId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        _deployJob = await _service.getDeployStatus(boardId: boardId);
        notifyListeners();

        if (_deployJob!.status == PynqDeployJobStatus.configured) {
          _pollTimer?.cancel();
          _pollTimer = null;
          if (_runSitl) {
            await runVerification();
          } else {
            _currentStep = PynqDeployStep.done;
            notifyListeners();
          }
        } else if (_deployJob!.status == PynqDeployJobStatus.failed) {
          _pollTimer?.cancel();
          _pollTimer = null;
          _currentStep = PynqDeployStep.error;
          _errorMessage = 'Board deploy failed';
          notifyListeners();
        }
      } catch (e) {
        debugPrint('PYNQ status poll error: $e');
      }
    });
  }

  Future<void> runVerification() async {
    final board = selectedBoard;
    if (board == null) {
      _currentStep = PynqDeployStep.error;
      _errorMessage = 'Select a paired board before verification.';
      notifyListeners();
      return;
    }

    _currentStep = PynqDeployStep.verifying;
    _errorMessage = null;
    notifyListeners();

    try {
      _sitlResult = await _service.runSitlVerification(boardId: board.id);
      _currentStep = PynqDeployStep.done;
      notifyListeners();
    } on PynqDeployException catch (e) {
      _currentStep = PynqDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    } catch (e) {
      _currentStep = PynqDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  void reset() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _currentStep = PynqDeployStep.idle;
    _exportResult = null;
    _deployJob = null;
    _sitlResult = null;
    _errorMessage = null;
    _bitstreamPathOverride = '';
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _service.dispose();
    super.dispose();
  }
}
