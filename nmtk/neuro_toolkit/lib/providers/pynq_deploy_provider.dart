import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/services/pynq_deploy_service.dart';

/// Step in the PYNQ deployment workflow.
enum PynqDeployStep {
  idle,

  /// Calling NeuroCNL to check exportability.
  checking,

  /// Exportability verdict received (may be not exportable).
  checked,

  /// Submitting overlay to the PYNQ board.
  deploying,

  /// Polling board status after deploy.
  polling,

  /// Running SITL verification.
  verifying,

  /// Workflow complete.
  done,

  /// An unrecoverable error occurred.
  error,
}

/// State management for the PYNQ deploy screen.
///
/// Follows the ChangeNotifier + Provider pattern used by [TeensyDeployProvider].
class PynqDeployProvider with ChangeNotifier {
  PynqDeployProvider({PynqDeployService? service})
      : _service = service ?? PynqDeployService();

  final PynqDeployService _service;

  // -- State ---------------------------------------------------------------

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

  /// Remote board endpoint URL (set by the user in the UI).
  String _boardBaseUrl = '';
  String get boardBaseUrl => _boardBaseUrl;

  /// Optional API key for the remote board.
  String _boardApiKey = '';
  String get boardApiKey => _boardApiKey;

  /// Whether to run optional SITL verification after deploy.
  bool _runSitl = false;
  bool get runSitl => _runSitl;

  Timer? _pollTimer;

  // -- Actions -------------------------------------------------------------

  /// Check PYNQ exportability for a CNL spec.
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

  /// Update the remote board base URL.
  void setBoardBaseUrl(String url) {
    _boardBaseUrl = url;
    notifyListeners();
  }

  /// Update the optional API key.
  void setBoardApiKey(String key) {
    _boardApiKey = key;
    notifyListeners();
  }

  /// Toggle optional SITL verification.
  void setRunSitl(bool value) {
    _runSitl = value;
    notifyListeners();
  }

  /// Deploy the overlay to the remote PYNQ board.
  ///
  /// The [weights] and [config] come from the network payload produced by
  /// the NeuroCNL pipeline.  The UI passes them down from [exportResult].
  Future<void> startDeploy({
    required List<double> weights,
    required Map<String, dynamic> config,
    String? bitstreamPath,
  }) async {
    _currentStep = PynqDeployStep.deploying;
    _errorMessage = null;
    _deployJob = null;
    _sitlResult = null;
    notifyListeners();

    try {
      await _service.deployToBoard(
        boardBaseUrl: _boardBaseUrl,
        weights: weights,
        config: config,
        bitstreamPath: bitstreamPath,
        apiKey: _boardApiKey.isNotEmpty ? _boardApiKey : null,
      );

      _currentStep = PynqDeployStep.polling;
      notifyListeners();
      _startPolling();
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

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        _deployJob = await _service.getDeployStatus(
          boardBaseUrl: _boardBaseUrl,
          apiKey: _boardApiKey.isNotEmpty ? _boardApiKey : null,
        );
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

  /// Run optional SITL verification.
  Future<void> runVerification() async {
    _currentStep = PynqDeployStep.verifying;
    _errorMessage = null;
    notifyListeners();

    try {
      _sitlResult = await _service.runSitlVerification(
        boardBaseUrl: _boardBaseUrl,
        apiKey: _boardApiKey.isNotEmpty ? _boardApiKey : null,
      );
      _currentStep = PynqDeployStep.done;
      notifyListeners();
    } on PynqDeployException catch (e) {
      if (e.error.contains('No backend deployed')) {
        // Verification attempted before deploy; treat as a warning
        _currentStep = PynqDeployStep.done;
        _errorMessage = 'Verification skipped: ${e.error}';
      } else {
        _currentStep = PynqDeployStep.error;
        _errorMessage = e.toString();
      }
      notifyListeners();
    } catch (e) {
      _currentStep = PynqDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Reset all state to start a new session.
  void reset() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _currentStep = PynqDeployStep.idle;
    _exportResult = null;
    _deployJob = null;
    _sitlResult = null;
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _service.dispose();
    super.dispose();
  }
}
