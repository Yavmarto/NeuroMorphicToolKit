// Data models for PYNQ Z2 export/deployment workflow.
//
// Mirrors the Python backend schemas from:
// - neurocnl PynqExportResult / PynqSupportState
// - Neurochip PYNQ backend (issue 11)
//
// Two-tier support model:
// - Exportable: toolkit can produce overlay artifacts offline (no board needed)
// - Deployable: overlay can be loaded onto real PYNQ hardware (runtime)

import 'package:flutter/material.dart';

/// Support state for PYNQ Z2 target.
///
/// Export-time states are deterministic at planning time.
/// Deploy-time states are resolved at runtime (issue #11).
enum PynqSupportState {
  /// All constraints met; overlay artifacts can be generated.
  exportable,

  /// Constraints met but near capacity thresholds (>80%).
  exportableWithWarnings,

  /// One or more export-blocking rejections present.
  notExportable,

  /// Export succeeded AND overlay loaded on real PYNQ board.
  deployable,

  /// Export OK but board unreachable or overlay load failed.
  notDeployable;

  static PynqSupportState fromString(String value) {
    switch (value) {
      case 'exportable':
        return PynqSupportState.exportable;
      case 'exportable_with_warnings':
        return PynqSupportState.exportableWithWarnings;
      case 'not_exportable':
        return PynqSupportState.notExportable;
      case 'deployable':
        return PynqSupportState.deployable;
      case 'not_deployable':
        return PynqSupportState.notDeployable;
      default:
        return PynqSupportState.notExportable;
    }
  }

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case PynqSupportState.exportable:
        return 'Exportable — overlay package ready';
      case PynqSupportState.exportableWithWarnings:
        return 'Exportable — near capacity limits';
      case PynqSupportState.notExportable:
        return 'Not Exportable — see rejections';
      case PynqSupportState.deployable:
        return 'Deployed — running on PYNQ board';
      case PynqSupportState.notDeployable:
        return 'Not Deployable — board unreachable';
    }
  }

  /// Theme color for UI indicators.
  ///
  /// Blue/teal for exportable states (distinct from Teensy green)
  /// to visually reinforce the export-only semantic boundary.
  Color get color {
    switch (this) {
      case PynqSupportState.exportable:
        return const Color(0xFF0097A7); // Teal 700
      case PynqSupportState.exportableWithWarnings:
        return const Color(0xFFFFA000); // Amber 700
      case PynqSupportState.notExportable:
        return const Color(0xFFD32F2F); // Red 700
      case PynqSupportState.deployable:
        return const Color(0xFF388E3C); // Green 700
      case PynqSupportState.notDeployable:
        return const Color(0xFFD32F2F); // Red 700
    }
  }

  /// Icon for UI indicators.
  IconData get icon {
    switch (this) {
      case PynqSupportState.exportable:
        return Icons.upload_file;
      case PynqSupportState.exportableWithWarnings:
        return Icons.warning_amber_rounded;
      case PynqSupportState.notExportable:
        return Icons.block;
      case PynqSupportState.deployable:
        return Icons.check_circle;
      case PynqSupportState.notDeployable:
        return Icons.cloud_off;
    }
  }
}

/// Runtime mode reported by the Neurochip PYNQ backend.
enum PynqBackendRuntimeMode {
  unknown,
  hardware,
  simulator;

  static PynqBackendRuntimeMode fromJson(Object? value) {
    switch ((value as String?)?.toLowerCase()) {
      case 'hardware':
        return PynqBackendRuntimeMode.hardware;
      case 'simulator':
        return PynqBackendRuntimeMode.simulator;
      default:
        return PynqBackendRuntimeMode.unknown;
    }
  }

  bool get isSimulator => this == PynqBackendRuntimeMode.simulator;
}

/// Typed deploy-time config for POST /hardware/pynq/deploy.
class PynqDeployConfig {
  final double threshold;
  final int bitWidth;
  final double scaleFactor;

  const PynqDeployConfig({
    required this.threshold,
    required this.bitWidth,
    required this.scaleFactor,
  });

  factory PynqDeployConfig.fromJson(Map<String, dynamic> json) {
    return PynqDeployConfig(
      threshold: (json['threshold'] as num?)?.toDouble() ?? 1.0,
      bitWidth: json['bit_width'] as int? ?? 4,
      scaleFactor: (json['scale_factor'] as num?)?.toDouble() ?? 1.0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'threshold': threshold,
      'bit_width': bitWidth,
      'scale_factor': scaleFactor,
    };
  }
}

/// Typed MMIO register map for the PYNQ SNN overlay.
class PynqRegisterMap {
  final int baseAddress;
  final int controlRegOffset;
  final int statusRegOffset;
  final int neuronBaseOffset;
  final int weightBaseOffset;
  final String dmaChannel;
  final int inputBufferAddr;
  final int outputBufferAddr;
  final int timestepUs;

  const PynqRegisterMap({
    required this.baseAddress,
    required this.controlRegOffset,
    required this.statusRegOffset,
    required this.neuronBaseOffset,
    required this.weightBaseOffset,
    required this.dmaChannel,
    required this.inputBufferAddr,
    required this.outputBufferAddr,
    required this.timestepUs,
  });

  factory PynqRegisterMap.fromJson(Map<String, dynamic> json) {
    return PynqRegisterMap(
      baseAddress: json['base_address'] as int? ?? 0x40000000,
      controlRegOffset: json['control_reg_offset'] as int? ?? 0x00,
      statusRegOffset: json['status_reg_offset'] as int? ?? 0x04,
      neuronBaseOffset: json['neuron_base_offset'] as int? ?? 0x100,
      weightBaseOffset: json['weight_base_offset'] as int? ?? 0x1000,
      dmaChannel: json['dma_channel'] as String? ?? 'axi_dma_0',
      inputBufferAddr: json['input_buffer_addr'] as int? ?? 0,
      outputBufferAddr: json['output_buffer_addr'] as int? ?? 0,
      timestepUs: json['timestep_us'] as int? ?? 1000,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'base_address': baseAddress,
      'control_reg_offset': controlRegOffset,
      'status_reg_offset': statusRegOffset,
      'neuron_base_offset': neuronBaseOffset,
      'weight_base_offset': weightBaseOffset,
      'dma_channel': dmaChannel,
      'input_buffer_addr': inputBufferAddr,
      'output_buffer_addr': outputBufferAddr,
      'timestep_us': timestepUs,
    };
  }
}

/// Validated deploy payload returned by NeuroCNL for Neurochip's PYNQ router.
class PynqDeployPayload {
  final List<double> weights;
  final PynqDeployConfig config;
  final String bitstreamPath;
  final PynqRegisterMap registerMap;

  const PynqDeployPayload({
    required this.weights,
    required this.config,
    required this.bitstreamPath,
    required this.registerMap,
  });

  int get weightCount => weights.length;

  factory PynqDeployPayload.fromJson(Map<String, dynamic> json) {
    return PynqDeployPayload(
      weights: (json['weights'] as List? ?? const <Object>[])
          .map((e) => (e as num).toDouble())
          .toList(),
      config: PynqDeployConfig.fromJson(
        json['config'] as Map<String, dynamic>? ?? const <String, dynamic>{},
      ),
      bitstreamPath: json['bitstream_path'] as String? ?? 'snn_overlay.bit',
      registerMap: PynqRegisterMap.fromJson(
        json['register_map'] as Map<String, dynamic>? ??
            const <String, dynamic>{},
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'weights': weights,
      'config': config.toJson(),
      'bitstream_path': bitstreamPath,
      'register_map': registerMap.toJson(),
    };
  }
}

/// Response from PYNQ exportability planning endpoint.
class PynqNetworkResponse {
  final PynqSupportState supportState;
  final List<String> warnings;
  final List<String> rejectionReasons;
  final Map<String, dynamic>? networkSummary;
  final PynqDeployPayload? deployPayload;

  const PynqNetworkResponse({
    required this.supportState,
    required this.warnings,
    required this.rejectionReasons,
    this.networkSummary,
    this.deployPayload,
  });

  factory PynqNetworkResponse.fromJson(Map<String, dynamic> json) {
    return PynqNetworkResponse(
      supportState: PynqSupportState.fromString(
        json['support_state'] as String,
      ),
      warnings: (json['warnings'] as List).map((e) => e as String).toList(),
      rejectionReasons: (json['rejections'] as List)
          .map((e) => e as String)
          .toList(),
      networkSummary: json['network_summary'] as Map<String, dynamic>?,
      deployPayload: json['deploy_payload'] is Map<String, dynamic>
          ? PynqDeployPayload.fromJson(
              json['deploy_payload'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

enum PynqBoardAuthMode {
  password,
  sshKey;

  static PynqBoardAuthMode fromString(String? value) {
    switch (value) {
      case 'ssh_key':
        return PynqBoardAuthMode.sshKey;
      case 'password':
      default:
        return PynqBoardAuthMode.password;
    }
  }

  String get apiValue {
    switch (this) {
      case PynqBoardAuthMode.password:
        return 'password';
      case PynqBoardAuthMode.sshKey:
        return 'ssh_key';
    }
  }
}

enum PynqBoardState {
  unpaired,
  reachable,
  provisioning,
  provisionFailed,
  runtimeInstalled,
  overlayMissing,
  ready,
  degradedOptionalCapability,
  preflightFailed,
  error;

  static PynqBoardState fromString(String? value) {
    switch (value) {
      case 'reachable':
        return PynqBoardState.reachable;
      case 'provisioning':
        return PynqBoardState.provisioning;
      case 'provision_failed':
        return PynqBoardState.provisionFailed;
      case 'runtime_installed':
        return PynqBoardState.runtimeInstalled;
      case 'overlay_missing':
        return PynqBoardState.overlayMissing;
      case 'ready':
        return PynqBoardState.ready;
      case 'degraded_optional_capability':
        return PynqBoardState.degradedOptionalCapability;
      case 'preflight_failed':
        return PynqBoardState.preflightFailed;
      case 'error':
        return PynqBoardState.error;
      case 'unpaired':
      default:
        return PynqBoardState.unpaired;
    }
  }

  String get apiValue {
    switch (this) {
      case PynqBoardState.unpaired:
        return 'unpaired';
      case PynqBoardState.reachable:
        return 'reachable';
      case PynqBoardState.provisioning:
        return 'provisioning';
      case PynqBoardState.provisionFailed:
        return 'provision_failed';
      case PynqBoardState.runtimeInstalled:
        return 'runtime_installed';
      case PynqBoardState.overlayMissing:
        return 'overlay_missing';
      case PynqBoardState.ready:
        return 'ready';
      case PynqBoardState.degradedOptionalCapability:
        return 'degraded_optional_capability';
      case PynqBoardState.preflightFailed:
        return 'preflight_failed';
      case PynqBoardState.error:
        return 'error';
    }
  }

  String get label {
    switch (this) {
      case PynqBoardState.unpaired:
        return 'Unpaired';
      case PynqBoardState.reachable:
        return 'Reachable';
      case PynqBoardState.provisioning:
        return 'Provisioning';
      case PynqBoardState.provisionFailed:
        return 'Provision Failed';
      case PynqBoardState.runtimeInstalled:
        return 'Runtime Installed';
      case PynqBoardState.overlayMissing:
        return 'Overlay Missing';
      case PynqBoardState.ready:
        return 'Ready';
      case PynqBoardState.degradedOptionalCapability:
        return 'Degraded Optional Capability';
      case PynqBoardState.preflightFailed:
        return 'Preflight Failed';
      case PynqBoardState.error:
        return 'Error';
    }
  }
}

class PynqPairedBoard {
  final String id;
  final String displayName;
  final String host;
  final int sshPort;
  final String username;
  final PynqBoardAuthMode authMode;
  final String credentialRef;
  final String runtimeApiUrl;
  final String runtimeApiUrlOverride;
  final String overlayVersion;
  final PynqBoardState state;
  final String lastPreflightStatus;
  final String lastPreflightMessage;
  final String lastRuntimeMode;
  final bool hasPassword;
  final String sshKeyPath;
  final Map<String, dynamic>? lastStatus;

  const PynqPairedBoard({
    required this.id,
    required this.displayName,
    required this.host,
    required this.sshPort,
    required this.username,
    required this.authMode,
    required this.credentialRef,
    required this.runtimeApiUrl,
    this.runtimeApiUrlOverride = '',
    required this.overlayVersion,
    required this.state,
    required this.lastPreflightStatus,
    required this.lastPreflightMessage,
    required this.lastRuntimeMode,
    required this.hasPassword,
    required this.sshKeyPath,
    this.lastStatus,
  });

  bool get isReady => state == PynqBoardState.ready;

  factory PynqPairedBoard.fromJson(Map<String, dynamic> json) {
    return PynqPairedBoard(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'PYNQ Board',
      host: json['host'] as String? ?? '',
      sshPort: json['sshPort'] as int? ?? 22,
      username: json['username'] as String? ?? 'xilinx',
      authMode: PynqBoardAuthMode.fromString(json['authMode'] as String?),
      credentialRef: json['credentialRef'] as String? ?? '',
      runtimeApiUrl: json['runtimeApiUrl'] as String? ?? '',
      runtimeApiUrlOverride: json['runtimeApiUrlOverride'] as String? ?? '',
      overlayVersion: json['overlayVersion'] as String? ?? '',
      state: PynqBoardState.fromString(json['state'] as String?),
      lastPreflightStatus: json['lastPreflightStatus'] as String? ?? '',
      lastPreflightMessage: json['lastPreflightMessage'] as String? ?? '',
      lastRuntimeMode: json['lastRuntimeMode'] as String? ?? '',
      hasPassword: json['hasPassword'] as bool? ?? false,
      sshKeyPath: json['sshKeyPath'] as String? ?? '',
      lastStatus: json['lastStatus'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toJson({String? password}) {
    return <String, dynamic>{
      'id': id,
      'displayName': displayName,
      'host': host,
      'sshPort': sshPort,
      'username': username,
      'authMode': authMode.apiValue,
      'credentialRef': credentialRef,
      if (password != null && password.isNotEmpty) 'password': password,
      if (sshKeyPath.isNotEmpty) 'sshKeyPath': sshKeyPath,
      if (runtimeApiUrlOverride.isNotEmpty)
        'runtimeApiUrlOverride': runtimeApiUrlOverride,
      if (overlayVersion.isNotEmpty) 'overlayVersion': overlayVersion,
      'state': state.apiValue,
    };
  }

  PynqPairedBoard copyWith({
    String? id,
    String? displayName,
    String? host,
    int? sshPort,
    String? username,
    PynqBoardAuthMode? authMode,
    String? credentialRef,
    String? runtimeApiUrl,
    String? runtimeApiUrlOverride,
    String? overlayVersion,
    PynqBoardState? state,
    String? lastPreflightStatus,
    String? lastPreflightMessage,
    String? lastRuntimeMode,
    bool? hasPassword,
    String? sshKeyPath,
    Map<String, dynamic>? lastStatus,
  }) {
    return PynqPairedBoard(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      host: host ?? this.host,
      sshPort: sshPort ?? this.sshPort,
      username: username ?? this.username,
      authMode: authMode ?? this.authMode,
      credentialRef: credentialRef ?? this.credentialRef,
      runtimeApiUrl: runtimeApiUrl ?? this.runtimeApiUrl,
      runtimeApiUrlOverride:
          runtimeApiUrlOverride ?? this.runtimeApiUrlOverride,
      overlayVersion: overlayVersion ?? this.overlayVersion,
      state: state ?? this.state,
      lastPreflightStatus: lastPreflightStatus ?? this.lastPreflightStatus,
      lastPreflightMessage: lastPreflightMessage ?? this.lastPreflightMessage,
      lastRuntimeMode: lastRuntimeMode ?? this.lastRuntimeMode,
      hasPassword: hasPassword ?? this.hasPassword,
      sshKeyPath: sshKeyPath ?? this.sshKeyPath,
      lastStatus: lastStatus ?? this.lastStatus,
    );
  }
}

// ---------------------------------------------------------------------------
// Deploy job status — mirrors /hardware/pynq/status
// ---------------------------------------------------------------------------

/// Lifecycle state of a PYNQ backend deploy job.
///
/// Maps to the backend's `PynqState` enum plus router-level states:
///   unloaded / not_initialised → [notInitialised]
///   loaded                     → [loaded]
///   deploying (UI-only)        → [deploying]
///   configured                 → [configured]
///   running                    → [running]
///   failed                     → [failed]
enum PynqDeployJobStatus {
  /// No deploy has been attempted yet (or backend is unloaded).
  notInitialised,

  /// Overlay loaded but weights not yet configured.
  loaded,

  /// Overlay is being loaded and weights written (UI-side state).
  deploying,

  /// Overlay loaded and backend is configured and ready to run.
  configured,

  /// Backend is actively running inference.
  running,

  /// Deploy failed.
  failed;

  static PynqDeployJobStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'not_initialised':
      case 'not_initialized':
      case 'unloaded':
        return PynqDeployJobStatus.notInitialised;
      case 'loaded':
        return PynqDeployJobStatus.loaded;
      case 'deploying':
        return PynqDeployJobStatus.deploying;
      case 'configured':
        return PynqDeployJobStatus.configured;
      case 'running':
        return PynqDeployJobStatus.running;
      case 'failed':
        return PynqDeployJobStatus.failed;
      default:
        return PynqDeployJobStatus.notInitialised;
    }
  }

  double get progressFraction {
    switch (this) {
      case PynqDeployJobStatus.notInitialised:
        return 0.0;
      case PynqDeployJobStatus.loaded:
        return 0.25;
      case PynqDeployJobStatus.deploying:
        return 0.5;
      case PynqDeployJobStatus.configured:
        return 1.0;
      case PynqDeployJobStatus.running:
        return 0.9;
      case PynqDeployJobStatus.failed:
        return 0.0;
    }
  }
}

/// Deploy status snapshot from GET /hardware/pynq/status.
class PynqDeployJob {
  final PynqDeployJobStatus status;
  final String? bitstreamPath;
  final PynqBackendRuntimeMode runtimeMode;

  const PynqDeployJob({
    required this.status,
    this.bitstreamPath,
    this.runtimeMode = PynqBackendRuntimeMode.unknown,
  });

  factory PynqDeployJob.fromJson(Map<String, dynamic> json) {
    return PynqDeployJob(
      status: PynqDeployJobStatus.fromString(json['state'] as String),
      bitstreamPath: json['bitstream_path'] as String?,
      runtimeMode: PynqBackendRuntimeMode.fromJson(json['runtime_mode']),
    );
  }
}

// ---------------------------------------------------------------------------
// SITL verification result — mirrors /hardware/pynq/verify
// ---------------------------------------------------------------------------

/// Per-step result from SITL verification.
class PynqSitlStepResult {
  final String label;
  final bool passed;
  final double executionTimeUs;

  const PynqSitlStepResult({
    required this.label,
    required this.passed,
    required this.executionTimeUs,
  });

  factory PynqSitlStepResult.fromJson(Map<String, dynamic> json) {
    return PynqSitlStepResult(
      label: json['label'] as String,
      passed: json['passed'] as bool,
      executionTimeUs: (json['execution_time_us'] as num).toDouble(),
    );
  }
}

/// Full SITL verification result from POST /hardware/pynq/verify.
class PynqSitlVerifyResult {
  final bool passed;
  final int totalCases;
  final int passedCases;
  final double meanExecUs;
  final double maxExecUs;
  final String summary;
  final List<PynqSitlStepResult> steps;

  const PynqSitlVerifyResult({
    required this.passed,
    required this.totalCases,
    required this.passedCases,
    required this.meanExecUs,
    required this.maxExecUs,
    required this.summary,
    required this.steps,
  });

  factory PynqSitlVerifyResult.fromJson(Map<String, dynamic> json) {
    return PynqSitlVerifyResult(
      passed: json['passed'] as bool,
      totalCases: json['total_cases'] as int,
      passedCases: json['passed_cases'] as int,
      meanExecUs: (json['mean_exec_us'] as num).toDouble(),
      maxExecUs: (json['max_exec_us'] as num).toDouble(),
      summary: json['summary'] as String,
      steps: (json['steps'] as List)
          .map((e) => PynqSitlStepResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
