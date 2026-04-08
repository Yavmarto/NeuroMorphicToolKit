import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';
import 'package:neuro_toolkit/services/akida_deploy_service.dart';

/// Step in the Akida deployment workflow.
enum AkidaDeployStep {
  idle,

  /// Calling NeuroCNL to check exportability.
  checking,

  /// Exportability verdict received (may be unsupported).
  checked,

  /// Generating and downloading the scaffold package from Neurochip.
  deploying,

  /// Package saved locally; polling Neurochip for backend state.
  polling,

  /// Running Neurobench verification.
  verifying,

  /// Workflow complete.
  done,

  /// An unrecoverable error occurred.
  error,
}

/// State management for the Akida deploy screen.
///
/// Follows the ChangeNotifier + Provider pattern used by [PynqDeployProvider].
class AkidaDeployProvider with ChangeNotifier {
  AkidaDeployProvider({AkidaDeployService? service})
      : _service = service ?? AkidaDeployService();

  final AkidaDeployService _service;

  // -- State ---------------------------------------------------------------

  AkidaDeployStep _currentStep = AkidaDeployStep.idle;
  AkidaDeployStep get currentStep => _currentStep;

  AkidaNetworkResponse? _exportResult;
  AkidaNetworkResponse? get exportResult => _exportResult;

  AkidaDeployJob? _deployJob;
  AkidaDeployJob? get deployJob => _deployJob;

  /// Absolute path to the saved akida_deploy.zip, if downloaded.
  String? _savedPackagePath;
  String? get savedPackagePath => _savedPackagePath;

  /// Neurobench job ID, set after verification is submitted.
  String? _neurobenchJobId;
  String? get neurobenchJobId => _neurobenchJobId;

  /// Latest Neurobench job status dict.
  Map<String, dynamic>? _neurobenchResult;
  Map<String, dynamic>? get neurobenchResult => _neurobenchResult;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Whether to run Neurobench verification after the package is downloaded.
  bool _runNeurobench = false;
  bool get runNeurobench => _runNeurobench;

  Timer? _pollTimer;

  // -- Actions -------------------------------------------------------------

  /// Check Akida exportability for a CNL spec.
  Future<void> checkExportability({
    required String spec,
    required int weightBitWidth,
    String akidaVersion = 'akida1',
  }) async {
    _currentStep = AkidaDeployStep.checking;
    _errorMessage = null;
    _exportResult = null;
    _deployJob = null;
    _savedPackagePath = null;
    _neurobenchJobId = null;
    _neurobenchResult = null;
    notifyListeners();

    try {
      _exportResult = await _service.checkExportability(
        spec: spec,
        weightBitWidth: weightBitWidth,
        akidaVersion: akidaVersion,
      );
      _currentStep = AkidaDeployStep.checked;
      notifyListeners();
    } on AkidaDeployException catch (e) {
      _currentStep = AkidaDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    } catch (e) {
      _currentStep = AkidaDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Toggle optional Neurobench verification.
  void setRunNeurobench(bool value) {
    _runNeurobench = value;
    notifyListeners();
  }

  /// Download the Akida scaffold package from Neurochip.
  ///
  /// [mappedNetwork] is the pre-mapped network from the exportability check.
  /// [bitWidth] is the weight quantisation bit-width (1, 2, or 4).
  /// [outputDir] is the directory where the ZIP will be saved.
  Future<void> startDeploy({
    required Map<String, dynamic> mappedNetwork,
    required int bitWidth,
    required String outputDir,
  }) async {
    _currentStep = AkidaDeployStep.deploying;
    _errorMessage = null;
    _deployJob = null;
    _savedPackagePath = null;
    _neurobenchJobId = null;
    _neurobenchResult = null;
    notifyListeners();

    try {
      _savedPackagePath = await _service.downloadPackage(
        mappedNetwork: mappedNetwork,
        bitWidth: bitWidth,
        outputDir: outputDir,
      );
      _currentStep = AkidaDeployStep.polling;
      notifyListeners();
      _startPolling();
    } on AkidaDeployException catch (e) {
      _currentStep = AkidaDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    } catch (e) {
      _currentStep = AkidaDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      try {
        _deployJob = await _service.getStatus();
        notifyListeners();

        final status = _deployJob!.status;
        if (status == AkidaDeployJobStatus.mapped ||
            status == AkidaDeployJobStatus.running) {
          _pollTimer?.cancel();
          _pollTimer = null;
          if (_runNeurobench && _savedPackagePath != null) {
            await runVerification();
          } else {
            _currentStep = AkidaDeployStep.done;
            notifyListeners();
          }
        } else if (status == AkidaDeployJobStatus.failed) {
          _pollTimer?.cancel();
          _pollTimer = null;
          _currentStep = AkidaDeployStep.error;
          _errorMessage = 'Akida backend deploy failed';
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Akida status poll error: $e');
      }
    });
  }

  /// Submit a Neurobench verification job for the deployed package.
  Future<void> runVerification({
    String benchmarkId = 'akida_default',
  }) async {
    _currentStep = AkidaDeployStep.verifying;
    _errorMessage = null;
    notifyListeners();

    try {
      _neurobenchJobId = await _service.runNeurobenchJob(
        benchmarkId: benchmarkId,
        networkPath: _savedPackagePath ?? '',
        target: 'simulation',
      );
      notifyListeners();

      // Poll until the job completes or fails.
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
        if (_neurobenchJobId == null) return;
        try {
          final result = await _service.getNeurobenchJobStatus(_neurobenchJobId!);
          _neurobenchResult = result;
          notifyListeners();

          final jobStatus = result['status'] as String? ?? '';
          if (jobStatus == 'completed' || jobStatus == 'failed') {
            _pollTimer?.cancel();
            _pollTimer = null;
            _currentStep = AkidaDeployStep.done;
            notifyListeners();
          }
        } catch (e) {
          debugPrint('Neurobench poll error: $e');
        }
      });
    } on AkidaDeployException catch (e) {
      _currentStep = AkidaDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    } catch (e) {
      _currentStep = AkidaDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Reset all state to start a new session.
  void reset() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _currentStep = AkidaDeployStep.idle;
    _exportResult = null;
    _deployJob = null;
    _savedPackagePath = null;
    _neurobenchJobId = null;
    _neurobenchResult = null;
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
