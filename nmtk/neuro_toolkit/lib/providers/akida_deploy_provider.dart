import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:neuro_toolkit/models/module.dart';
import 'package:neuro_toolkit/services/control_api_service.dart';
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

  /// Package saved locally; verifying SDK deployability via Neurochip.
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
  AkidaDeployProvider({
    AkidaDeployService? service,
    ControlApiService? controlApiService,
  }) : _service = service ?? AkidaDeployService(),
       _controlApiService = controlApiService ?? ControlApiService();

  final AkidaDeployService _service;
  final ControlApiService _controlApiService;

  // -- State ---------------------------------------------------------------

  AkidaDeployStep _currentStep = AkidaDeployStep.idle;
  AkidaDeployStep get currentStep => _currentStep;

  AkidaNetworkResponse? _exportResult;
  AkidaNetworkResponse? get exportResult => _exportResult;

  AkidaDeployJob? _deployJob;
  AkidaDeployJob? get deployJob => _deployJob;

  AkidaSdkVerification? _runtimeStatus;
  AkidaSdkVerification? get runtimeStatus => _runtimeStatus;

  AkidaSdkVerification? _sdkVerification;
  AkidaSdkVerification? get sdkVerification => _sdkVerification;

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

  Module? _neurochipModule;
  Module? get neurochipModule => _neurochipModule;

  bool _isLoadingRuntimeSetup = false;
  bool get isLoadingRuntimeSetup => _isLoadingRuntimeSetup;

  bool _isPreparingRuntime = false;
  bool get isPreparingRuntime => _isPreparingRuntime;

  String? _runtimeSetupError;
  String? get runtimeSetupError => _runtimeSetupError;

  /// Whether to run Neurobench verification after the package is downloaded.
  bool _runNeurobench = false;
  bool get runNeurobench => _runNeurobench;

  Timer? _pollTimer;

  // -- Actions -------------------------------------------------------------

  Future<void> refreshRuntimeSetup() async {
    _isLoadingRuntimeSetup = true;
    _runtimeSetupError = null;
    notifyListeners();

    try {
      _neurochipModule = await _controlApiService.fetchModule('Neurochip');
    } catch (e) {
      _runtimeSetupError = e.toString();
    }

    try {
      _runtimeStatus = await _service.getRuntimeStatus();
    } catch (_) {
      // Runtime diagnostics are best-effort here; launcher module metadata
      // still needs to load even when the Neurochip backend is offline.
    } finally {
      _isLoadingRuntimeSetup = false;
      notifyListeners();
    }
  }

  Future<void> prepareLocalRuntime() async {
    _isPreparingRuntime = true;
    _runtimeSetupError = null;
    notifyListeners();

    try {
      _neurochipModule = await _controlApiService.prepareAkidaRuntime(
        'Neurochip',
      );
    } catch (e) {
      _runtimeSetupError = e.toString();
    } finally {
      try {
        _runtimeStatus = await _service.getRuntimeStatus();
      } catch (_) {
        // Ignore refresh failures; prepare action state is still useful on its own.
      }
      _isPreparingRuntime = false;
      notifyListeners();
    }
  }

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
    _sdkVerification = null;
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
    _sdkVerification = null;
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
      _sdkVerification = await _service.verifySdk(
        mappedNetwork: mappedNetwork,
        bitWidth: bitWidth,
      );
      _runtimeStatus = _sdkVerification;
      _deployJob = AkidaDeployJob.fromVerification(_sdkVerification!);
      notifyListeners();

      if (_runNeurobench &&
          _savedPackagePath != null &&
          _sdkVerification!.isDeployable) {
        await runVerification();
      } else {
        _currentStep = AkidaDeployStep.done;
        notifyListeners();
      }
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

  /// Submit a Neurobench verification job for the deployed package.
  Future<void> runVerification({String benchmarkId = 'akida_default'}) async {
    if (_sdkVerification?.isDeployable != true) {
      _errorMessage =
          'Neurobench verification is blocked until Akida SDK verification succeeds.';
      notifyListeners();
      return;
    }

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
          final result = await _service.getNeurobenchJobStatus(
            _neurobenchJobId!,
          );
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
    _sdkVerification = null;
    _savedPackagePath = null;
    _neurobenchJobId = null;
    _neurobenchResult = null;
    _errorMessage = null;
    _runtimeSetupError = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _service.dispose();
    super.dispose();
  }
}
