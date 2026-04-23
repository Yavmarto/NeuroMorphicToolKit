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

enum AkidaHostOperation {
  savingHost,
  deletingHost,
  testingConnectivity,
  provisioningHost,
  repairingHost,
  checkingReadiness,
  restartingServices,
}

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
  })  : _service = service ?? AkidaDeployService(),
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

  AkidaHostOperation? _activeHostOperation;
  AkidaHostOperation? get activeHostOperation => _activeHostOperation;
  bool get hostOperationInProgress => _activeHostOperation != null;

  String? _hostFeedbackMessage;
  String? get hostFeedbackMessage => _hostFeedbackMessage;

  List<AkidaPairedHost> _remoteHosts = <AkidaPairedHost>[];
  List<AkidaPairedHost> get remoteHosts =>
      List<AkidaPairedHost>.unmodifiable(_remoteHosts);

  String? _selectedRemoteHostId;
  String? get selectedRemoteHostId => _selectedRemoteHostId;

  AkidaPairedHost? get selectedRemoteHost {
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
      return selectedRemoteHost!.runtimeApiUrl;
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
      _applySettings(await _controlApiService.fetchSettings());
      _applyDefaultRuntimeMode();
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

  Future<void> saveRemoteHost({
    String? hostId,
    required String displayName,
    required String hostAddress,
    required int sshPort,
    required String username,
    required String password,
    required String runtimeApiUrl,
    required String controlApiUrl,
    required String remoteInstallRoot,
    required String serviceUser,
  }) async {
    _startHostOperation(
      AkidaHostOperation.savingHost,
      hostId == null || hostId.isEmpty
          ? 'Saving remote Akida host.'
          : 'Updating remote Akida host.',
    );

    try {
      final payload = <String, dynamic>{
        'displayName': displayName,
        'host': hostAddress,
        'sshPort': sshPort,
        'username': username,
        'authMode': 'password',
        'password': password,
        'runtimeApiUrl': runtimeApiUrl,
        'controlApiUrl': controlApiUrl,
        'remoteInstallRoot': remoteInstallRoot,
        'serviceUser': serviceUser,
      };
      final savedHost = hostId == null || hostId.isEmpty
          ? await _controlApiService.createAkidaHost(payload)
          : await _controlApiService.updateAkidaHost(hostId, payload);
      await _controlApiService.updateSettings(
        selectedAkidaHostId: savedHost.id,
      );
      _upsertRemoteHost(savedHost);
      _selectedRemoteHostId = savedHost.id;
      _runtimeMode = AkidaRuntimeMode.remoteSdk;
      _finishHostOperation(
        'Remote Akida host saved. Test connectivity or provision it next.',
      );
    } catch (e) {
      _runtimeSetupError = e.toString();
      _failHostOperation('Failed to save remote Akida host.');
    } finally {
      notifyListeners();
    }
  }

  Future<void> deleteSelectedRemoteHost() async {
    final hostId = _selectedRemoteHostId;
    if (hostId == null) {
      return;
    }

    _startHostOperation(
      AkidaHostOperation.deletingHost,
      'Removing remote Akida host.',
    );

    try {
      await _controlApiService.deleteAkidaHost(hostId);
      _applySettings(await _controlApiService.fetchSettings());
      if (isRemoteSdkMode && _selectedRemoteHostId == null) {
        _runtimeMode = localRuntimeSupported
            ? AkidaRuntimeMode.localSdk
            : AkidaRuntimeMode.localSimulator;
      }
      _finishHostOperation('Remote Akida host removed.');
    } catch (e) {
      _runtimeSetupError = e.toString();
      _failHostOperation('Failed to remove remote Akida host.');
    } finally {
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
      unawaited(_persistSelectedRemoteHost(hostId));
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
      _runtimeStatus = _sdkVerification;
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

  void _applySettings(LauncherControlSettings settings) {
    _remoteHosts = settings.akidaHosts;
    final selectedRemoteHostId = settings.selectedAkidaHostId;
    if (selectedRemoteHostId != null &&
        _remoteHosts.any((host) => host.id == selectedRemoteHostId)) {
      _selectedRemoteHostId = selectedRemoteHostId;
      return;
    }
    _selectedRemoteHostId = _remoteHosts.isEmpty ? null : _remoteHosts.first.id;
  }

  Future<void> _persistSelectedRemoteHost(String hostId) async {
    try {
      await _controlApiService.updateSettings(selectedAkidaHostId: hostId);
    } catch (e) {
      _runtimeSetupError = e.toString();
      notifyListeners();
    }
  }

  void _upsertRemoteHost(AkidaPairedHost host) {
    final index = _remoteHosts.indexWhere((item) => item.id == host.id);
    if (index == -1) {
      _remoteHosts = <AkidaPairedHost>[..._remoteHosts, host];
    } else {
      final updated = List<AkidaPairedHost>.from(_remoteHosts);
      updated[index] = host;
      _remoteHosts = updated;
    }
  }

  void _replaceRemoteHost(AkidaPairedHost host) {
    final index = _remoteHosts.indexWhere((item) => item.id == host.id);
    if (index == -1) {
      _remoteHosts = <AkidaPairedHost>[..._remoteHosts, host];
      return;
    }
    final updated = List<AkidaPairedHost>.from(_remoteHosts);
    updated[index] = host;
    _remoteHosts = updated;
  }

  void _startHostOperation(
    AkidaHostOperation operation,
    String message, {
    AkidaPairedHostState? optimisticState,
  }) {
    _activeHostOperation = operation;
    _hostFeedbackMessage = message;
    _runtimeSetupError = null;
    final host = selectedRemoteHost;
    if (host != null && optimisticState != null) {
      _replaceRemoteHost(
        host.copyWith(
          state: optimisticState,
          lastReadinessMessage: message,
        ),
      );
    }
    notifyListeners();
  }

  void _finishHostOperation(String message) {
    _activeHostOperation = null;
    _hostFeedbackMessage = message;
    notifyListeners();
  }

  void _failHostOperation(
    String message, {
    AkidaPairedHostState? fallbackState,
  }) {
    _activeHostOperation = null;
    _hostFeedbackMessage = message;
    final host = selectedRemoteHost;
    if (host != null && fallbackState != null) {
      _replaceRemoteHost(
        host.copyWith(
          state: fallbackState,
          lastReadinessMessage: message,
        ),
      );
    }
    notifyListeners();
  }

  Future<void> testSelectedRemoteHostConnectivity() async {
    final host = selectedRemoteHost;
    if (host == null) {
      _runtimeSetupError =
          'Save a remote Akida host before running connectivity checks.';
      notifyListeners();
      return;
    }
    _startHostOperation(
      AkidaHostOperation.testingConnectivity,
      'Testing connectivity to the remote Akida host.',
      optimisticState: AkidaPairedHostState.reachable,
    );
    try {
      final updated = await _controlApiService.testAkidaHostConnectivity(
        host.id,
      );
      _upsertRemoteHost(updated);
      _finishHostOperation(
          'Connectivity succeeded. The remote host is reachable.');
    } catch (e) {
      _runtimeSetupError = e.toString();
      _failHostOperation(
        'Connectivity test failed.',
        fallbackState: AkidaPairedHostState.error,
      );
    }
  }

  Future<void> provisionSelectedRemoteHost() async {
    final host = selectedRemoteHost;
    if (host == null) {
      _runtimeSetupError = 'Save a remote Akida host before provisioning.';
      notifyListeners();
      return;
    }
    _startHostOperation(
      AkidaHostOperation.provisioningHost,
      'Provisioning blank host. Watch the launcher terminal for SSH and install steps.',
      optimisticState: AkidaPairedHostState.bootstrapping,
    );
    try {
      final updated = await _controlApiService.provisionAkidaHost(host.id);
      _upsertRemoteHost(updated);
      _finishHostOperation(
        updated.lastReadinessMessage.isNotEmpty
            ? updated.lastReadinessMessage
            : 'Provisioning completed. Review host readiness below.',
      );
    } catch (e) {
      _runtimeSetupError = e.toString();
      _failHostOperation(
        'Provisioning failed.',
        fallbackState: AkidaPairedHostState.provisionFailed,
      );
    }
  }

  Future<void> repairSelectedRemoteHost() async {
    final host = selectedRemoteHost;
    if (host == null) {
      _runtimeSetupError = 'Select a remote Akida host before repairing it.';
      notifyListeners();
      return;
    }
    _startHostOperation(
      AkidaHostOperation.repairingHost,
      'Repairing remote Akida host.',
      optimisticState: AkidaPairedHostState.installingRuntime,
    );
    try {
      final updated = await _controlApiService.repairAkidaHost(host.id);
      _upsertRemoteHost(updated);
      _finishHostOperation(
        updated.lastReadinessMessage.isNotEmpty
            ? updated.lastReadinessMessage
            : 'Repair completed. Review host readiness below.',
      );
    } catch (e) {
      _runtimeSetupError = e.toString();
      _failHostOperation(
        'Repair failed.',
        fallbackState: AkidaPairedHostState.provisionFailed,
      );
    }
  }

  Future<void> checkSelectedRemoteHostReadiness() async {
    final host = selectedRemoteHost;
    if (host == null) {
      _runtimeSetupError =
          'Select a remote Akida host before checking readiness.';
      notifyListeners();
      return;
    }
    _startHostOperation(
      AkidaHostOperation.checkingReadiness,
      'Checking remote Akida host readiness.',
      optimisticState: AkidaPairedHostState.verifyingSdk,
    );
    try {
      final updated = await _controlApiService.fetchAkidaHostPreflight(host.id);
      _upsertRemoteHost(updated);
      _finishHostOperation(
        updated.lastReadinessMessage.isNotEmpty
            ? updated.lastReadinessMessage
            : 'Readiness refresh completed.',
      );
    } catch (e) {
      _runtimeSetupError = e.toString();
      _failHostOperation(
        'Readiness check failed.',
        fallbackState: AkidaPairedHostState.preflightFailed,
      );
    }
  }

  Future<void> restartSelectedRemoteHostServices() async {
    final host = selectedRemoteHost;
    if (host == null) {
      _runtimeSetupError =
          'Select a remote Akida host before restarting services.';
      notifyListeners();
      return;
    }
    _startHostOperation(
      AkidaHostOperation.restartingServices,
      'Restarting remote Neurochip services.',
      optimisticState: AkidaPairedHostState.verifyingSdk,
    );
    try {
      final updated =
          await _controlApiService.restartAkidaHostServices(host.id);
      _upsertRemoteHost(updated);
      _finishHostOperation(
        updated.lastReadinessMessage.isNotEmpty
            ? updated.lastReadinessMessage
            : 'Remote services restarted.',
      );
    } catch (e) {
      _runtimeSetupError = e.toString();
      _failHostOperation(
        'Remote service restart failed.',
        fallbackState: AkidaPairedHostState.error,
      );
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
