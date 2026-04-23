import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:neuro_toolkit/models/akida_remote_host.dart';
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

  /// Generating the package completed; runtime target verification is running.
  polling,

  /// Running Neurobench verification.
  verifying,

  /// Workflow complete.
  done,

  /// An unrecoverable error occurred.
  error,
}

enum AkidaRuntimeMode { localSimulator, localSdk, remoteSdk }

extension AkidaRuntimeModeLabel on AkidaRuntimeMode {
  String get label {
    switch (this) {
      case AkidaRuntimeMode.localSimulator:
        return 'Local simulator';
      case AkidaRuntimeMode.localSdk:
        return 'Local SDK';
      case AkidaRuntimeMode.remoteSdk:
        return 'Remote SDK host';
    }
  }
}

/// State management for the Akida deploy screen.
///
/// Follows the ChangeNotifier + Provider pattern used by [PynqDeployProvider].
class AkidaDeployProvider with ChangeNotifier {
  AkidaDeployProvider({
    AkidaDeployService? service,
    ControlApiService? controlApiService,
    TargetPlatform? platformOverride,
  }) : _service = service ?? AkidaDeployService(),
       _controlApiService = controlApiService ?? ControlApiService(),
       _platformOverride = platformOverride;

  final AkidaDeployService _service;
  final ControlApiService _controlApiService;
  final TargetPlatform? _platformOverride;

  // -- State ---------------------------------------------------------------

  AkidaDeployStep _currentStep = AkidaDeployStep.idle;
  AkidaDeployStep get currentStep => _currentStep;

  AkidaRuntimeMode _runtimeMode = AkidaRuntimeMode.localSimulator;
  AkidaRuntimeMode get runtimeMode => _runtimeMode;
  bool get isLocalSimulatorMode =>
      _runtimeMode == AkidaRuntimeMode.localSimulator;
  bool get isLocalSdkMode => _runtimeMode == AkidaRuntimeMode.localSdk;
  bool get isRemoteSdkMode => _runtimeMode == AkidaRuntimeMode.remoteSdk;

  AkidaNetworkResponse? _exportResult;
  AkidaNetworkResponse? get exportResult => _exportResult;

  AkidaDeployJob? _deployJob;
  AkidaDeployJob? get deployJob => _deployJob;

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

  List<AkidaRemoteHost> _remoteHosts = <AkidaRemoteHost>[];
  List<AkidaRemoteHost> get remoteHosts =>
      List<AkidaRemoteHost>.unmodifiable(_remoteHosts);

  String? _selectedRemoteHostId;
  String? get selectedRemoteHostId => _selectedRemoteHostId;

  AkidaRemoteHost? get selectedRemoteHost {
    final selectedRemoteHostId = _selectedRemoteHostId;
    if (selectedRemoteHostId == null) {
      return null;
    }
    for (final host in _remoteHosts) {
      if (host.id == selectedRemoteHostId) {
        return host;
      }
    }
    return null;
  }

  String get selectedRuntimeBaseUrl {
    if (isRemoteSdkMode && selectedRemoteHost != null) {
      return selectedRemoteHost!.baseUrl;
    }
    return _service.localNeurochipBaseUrl;
  }

  bool get canDeployToSelectedRuntime =>
      !isRemoteSdkMode || selectedRemoteHost != null;

  bool get localRuntimeSupported {
    final runtime = _neurochipModule?.akidaRuntime;
    if (runtime == null) {
      return false;
    }
    return runtime.supportedPlatforms.contains(_currentPlatformKey());
  }

  bool get isExpectedLocalSimulatorOutcome {
    final verification = _sdkVerification;
    return verification != null &&
        isLocalSimulatorMode &&
        verification.sdkStatus == 'not_available';
  }

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
      _remoteHosts = await _controlApiService.fetchAkidaHosts();
      if (_selectedRemoteHostId == null ||
          !_remoteHosts.any((host) => host.id == _selectedRemoteHostId)) {
        _selectedRemoteHostId = _remoteHosts.isEmpty
            ? null
            : _remoteHosts.first.id;
      }
      _applyDefaultRuntimeMode();
    } catch (e) {
      _runtimeSetupError = e.toString();
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
      _isPreparingRuntime = false;
      notifyListeners();
    }
  }

  Future<void> saveRemoteHost({
    String? hostId,
    required String displayName,
    required String baseUrl,
  }) async {
    _isLoadingRuntimeSetup = true;
    _runtimeSetupError = null;
    notifyListeners();

    try {
      final payload = <String, dynamic>{
        'displayName': displayName,
        'baseUrl': baseUrl,
      };
      final host = hostId == null || hostId.isEmpty
          ? await _controlApiService.createAkidaHost(payload)
          : await _controlApiService.updateAkidaHost(hostId, payload);
      _upsertRemoteHost(host);
      _selectedRemoteHostId = host.id;
      _runtimeMode = AkidaRuntimeMode.remoteSdk;
    } catch (e) {
      _runtimeSetupError = e.toString();
    } finally {
      _isLoadingRuntimeSetup = false;
      notifyListeners();
    }
  }

  Future<void> deleteSelectedRemoteHost() async {
    final hostId = _selectedRemoteHostId;
    if (hostId == null) {
      return;
    }

    _isLoadingRuntimeSetup = true;
    _runtimeSetupError = null;
    notifyListeners();

    try {
      await _controlApiService.deleteAkidaHost(hostId);
      _remoteHosts = _remoteHosts
          .where((host) => host.id != hostId)
          .toList(growable: false);
      _selectedRemoteHostId = _remoteHosts.isEmpty
          ? null
          : _remoteHosts.first.id;
      if (isRemoteSdkMode && _selectedRemoteHostId == null) {
        _runtimeMode = localRuntimeSupported
            ? AkidaRuntimeMode.localSdk
            : AkidaRuntimeMode.localSimulator;
      }
    } catch (e) {
      _runtimeSetupError = e.toString();
    } finally {
      _isLoadingRuntimeSetup = false;
      notifyListeners();
    }
  }

  void setRuntimeMode(AkidaRuntimeMode runtimeMode) {
    _runtimeMode = runtimeMode;
    if (_runtimeMode == AkidaRuntimeMode.remoteSdk &&
        _selectedRemoteHostId == null &&
        _remoteHosts.isNotEmpty) {
      _selectedRemoteHostId = _remoteHosts.first.id;
    }
    notifyListeners();
  }

  void selectRemoteHost(String? hostId) {
    _selectedRemoteHostId = hostId;
    if (hostId != null) {
      _runtimeMode = AkidaRuntimeMode.remoteSdk;
    }
    notifyListeners();
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
    if (!canDeployToSelectedRuntime) {
      _currentStep = AkidaDeployStep.error;
      _errorMessage =
          'Select or create a remote Akida host before routing deploy and verification to a remote SDK runtime.';
      notifyListeners();
      return;
    }

    _currentStep = AkidaDeployStep.deploying;
    _errorMessage = null;
    _deployJob = null;
    _sdkVerification = null;
    _savedPackagePath = null;
    _neurobenchJobId = null;
    _neurobenchResult = null;
    notifyListeners();

    try {
      final runtimeBaseUrl = selectedRuntimeBaseUrl;
      _savedPackagePath = await _service.downloadPackage(
        mappedNetwork: mappedNetwork,
        bitWidth: bitWidth,
        outputDir: outputDir,
        neurochipBaseUrl: runtimeBaseUrl,
      );
      _currentStep = AkidaDeployStep.polling;
      notifyListeners();
      _sdkVerification = await _service.verifySdk(
        mappedNetwork: mappedNetwork,
        bitWidth: bitWidth,
        neurochipBaseUrl: runtimeBaseUrl,
      );
      if (!isExpectedLocalSimulatorOutcome) {
        _deployJob = AkidaDeployJob.fromVerification(_sdkVerification!);
      }
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

  void _applyDefaultRuntimeMode() {
    if (isRemoteSdkMode && selectedRemoteHost == null) {
      _runtimeMode = localRuntimeSupported
          ? AkidaRuntimeMode.localSdk
          : AkidaRuntimeMode.localSimulator;
      return;
    }
    if (isLocalSdkMode && !localRuntimeSupported) {
      _runtimeMode = AkidaRuntimeMode.localSimulator;
      return;
    }
    if (_runtimeMode == AkidaRuntimeMode.localSimulator &&
        localRuntimeSupported) {
      _runtimeMode = AkidaRuntimeMode.localSdk;
    }
  }

  void _upsertRemoteHost(AkidaRemoteHost host) {
    final index = _remoteHosts.indexWhere((item) => item.id == host.id);
    if (index == -1) {
      _remoteHosts = <AkidaRemoteHost>[..._remoteHosts, host];
    } else {
      final updated = List<AkidaRemoteHost>.from(_remoteHosts);
      updated[index] = host;
      _remoteHosts = updated;
    }
  }

  String _currentPlatformKey() {
    switch (_platformOverride ?? defaultTargetPlatform) {
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      default:
        return (_platformOverride ?? defaultTargetPlatform).name;
    }
  }
}
