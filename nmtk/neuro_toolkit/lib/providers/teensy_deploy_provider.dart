import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:nmtk_ui_core/nmtk_ui_core.dart';

import '../services/teensy_deploy_service.dart';

/// Step in the Teensy deployment workflow.
enum TeensyDeployStep {
  idle,
  deploying,
  exporting,
  selectingPort,
  flashing,
  verifying,
  done,
  error,
}

/// State management for the Teensy deploy screen.
///
/// Follows the ChangeNotifier + Provider pattern used by [ModuleProvider].
class TeensyDeployProvider with ChangeNotifier {
  TeensyDeployProvider({TeensyDeployService? service})
      : _service = service ?? TeensyDeployService();

  final TeensyDeployService _service;

  // -- State ---------------------------------------------------------------

  TeensyDeployStep _currentStep = TeensyDeployStep.idle;
  TeensyDeployStep get currentStep => _currentStep;

  TeensyNetworkResponse? _deployResult;
  TeensyNetworkResponse? get deployResult => _deployResult;

  Uint8List? _firmwareBytes;
  Uint8List? get firmwareBytes => _firmwareBytes;

  List<SerialPortInfo> _serialPorts = [];
  List<SerialPortInfo> get serialPorts => _serialPorts;

  SerialPortInfo? _selectedPort;
  SerialPortInfo? get selectedPort => _selectedPort;

  FlashJob? _flashJob;
  FlashJob? get flashJob => _flashJob;

  VerificationReport? _verificationReport;
  VerificationReport? get verificationReport => _verificationReport;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  Timer? _pollTimer;

  // -- Actions -------------------------------------------------------------

  /// Run the full deploy pipeline: parse → plan → handoff → firmware export.
  Future<void> deployAndExport({
    required String spec,
    required int weightBitWidth,
  }) async {
    _currentStep = TeensyDeployStep.deploying;
    _errorMessage = null;
    _deployResult = null;
    _firmwareBytes = null;
    _flashJob = null;
    _verificationReport = null;
    notifyListeners();

    try {
      // Step 1: Deploy (parse → lower → plan → handoff)
      _deployResult = await _service.deployNetwork(
        spec: spec,
        weightBitWidth: weightBitWidth,
      );
      notifyListeners();

      if (_deployResult!.payload == null) {
        _currentStep = TeensyDeployStep.error;
        _errorMessage = 'Network not deployable';
        notifyListeners();
        return;
      }

      // Step 2: Export firmware
      _currentStep = TeensyDeployStep.exporting;
      notifyListeners();

      _firmwareBytes = await _service.exportFirmware(
        payload: _deployResult!.payload!,
        bitWidth: weightBitWidth,
      );

      _currentStep = TeensyDeployStep.selectingPort;
      notifyListeners();
    } on TeensyDeployException catch (e) {
      _currentStep = TeensyDeployStep.error;
      _errorMessage = e.toString();
      // If it was a deployment rejection, still capture partial result
      if (e.rejectionReasons.isNotEmpty) {
        _deployResult = TeensyNetworkResponse(
          verdict: TeensyDeploymentVerdict.notDeployable,
          warnings: [],
          rejectionReasons: e.rejectionReasons,
          payload: null,
        );
      }
      notifyListeners();
    } catch (e) {
      _currentStep = TeensyDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Refresh the list of available serial ports.
  Future<void> refreshPorts() async {
    try {
      _serialPorts = await _service.listSerialPorts();
      // Auto-select first Teensy device if available
      final teensy = _serialPorts.where((p) => p.isTeensy).toList();
      if (teensy.isNotEmpty && _selectedPort == null) {
        _selectedPort = teensy.first;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to list serial ports: $e');
    }
  }

  /// Select a serial port for flashing.
  void selectPort(SerialPortInfo port) {
    _selectedPort = port;
    notifyListeners();
  }

  /// Start flashing firmware to the selected serial port.
  Future<void> startFlash() async {
    if (_firmwareBytes == null || _selectedPort == null) return;

    _currentStep = TeensyDeployStep.flashing;
    _errorMessage = null;
    notifyListeners();

    try {
      _flashJob = await _service.startFlash(
        firmwareZipBytes: _firmwareBytes!,
        serialPort: _selectedPort!.device,
      );
      notifyListeners();

      // Start polling for flash job status
      _startPolling();
    } catch (e) {
      _currentStep = TeensyDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (_flashJob == null) return;

      try {
        _flashJob = await _service.pollFlashJob(_flashJob!.jobId);
        notifyListeners();

        if (_flashJob!.status == FlashJobStatus.done) {
          _pollTimer?.cancel();
          _pollTimer = null;
          // Automatically begin verification
          await runVerification();
        } else if (_flashJob!.status == FlashJobStatus.failed) {
          _pollTimer?.cancel();
          _pollTimer = null;
          _currentStep = TeensyDeployStep.error;
          _errorMessage = _flashJob!.error ?? 'Flash failed';
          notifyListeners();
        }
      } catch (e) {
        debugPrint('Flash poll error: $e');
      }
    });
  }

  /// Run post-flash Dream-Hand verification.
  Future<void> runVerification() async {
    if (_flashJob == null || _selectedPort == null) return;

    _currentStep = TeensyDeployStep.verifying;
    _errorMessage = null;
    notifyListeners();

    try {
      _verificationReport = await _service.verifyFlash(
        jobId: _flashJob!.jobId,
        serialPort: _selectedPort!.device,
        runDemo: true,
        runHitl: false,
      );
      _currentStep = TeensyDeployStep.done;
      notifyListeners();
    } on TeensyDeployException catch (e) {
      if (e.error.contains('not installed')) {
        // Dream-Hand not installed — still mark as done (verification optional)
        _currentStep = TeensyDeployStep.done;
        _errorMessage = 'Verification skipped: ${e.error}';
      } else {
        _currentStep = TeensyDeployStep.error;
        _errorMessage = e.toString();
      }
      notifyListeners();
    } catch (e) {
      _currentStep = TeensyDeployStep.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Reset the provider state to start a new deployment.
  void reset() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _currentStep = TeensyDeployStep.idle;
    _deployResult = null;
    _firmwareBytes = null;
    _selectedPort = null;
    _flashJob = null;
    _verificationReport = null;
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
