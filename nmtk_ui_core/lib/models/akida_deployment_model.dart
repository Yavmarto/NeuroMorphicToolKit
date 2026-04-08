/// Data models for BrainChip Akida scaffold-export/deployment workflow.
///
/// Mirrors the Python backend schemas from:
/// - neurocnl AkidaExportResult / AkidaSupportState
/// - Neurochip Akida backend (akida_backend.py)
///
/// Three-tier support model:
/// - **Unsupported**: network cannot target Akida
/// - **Exportable Scaffold**: toolkit can produce MetaTF project scaffolding
///   and quantized weights offline (no Akida SDK needed)
/// - **SDK Deployable**: model can be compiled and mapped via Akida SDK
///   onto hardware or AKD1000 simulator (runtime)

import 'package:flutter/material.dart';

/// Support state for BrainChip Akida target.
///
/// Export-time states are deterministic at planning time.
/// SDK deploy states are resolved at runtime.
enum AkidaSupportState {
  /// All constraints met; scaffold package can be generated.
  exportableScaffold,

  /// Constraints met but near capacity thresholds or topology approximate.
  exportableScaffoldWithWarnings,

  /// One or more export-blocking rejections present.
  unsupported,

  /// Scaffold succeeded AND model mapped via Akida SDK.
  sdkDeployable,

  /// Scaffold OK but SDK unavailable or mapping failed.
  sdkNotDeployable;

  static AkidaSupportState fromString(String value) {
    switch (value) {
      case 'exportable_scaffold':
        return AkidaSupportState.exportableScaffold;
      case 'exportable_scaffold_with_warnings':
        return AkidaSupportState.exportableScaffoldWithWarnings;
      case 'unsupported':
        return AkidaSupportState.unsupported;
      case 'sdk_deployable':
        return AkidaSupportState.sdkDeployable;
      case 'sdk_not_deployable':
        return AkidaSupportState.sdkNotDeployable;
      default:
        return AkidaSupportState.unsupported;
    }
  }

  /// Human-readable label for UI display.
  String get label {
    switch (this) {
      case AkidaSupportState.exportableScaffold:
        return 'Exportable — scaffold package ready';
      case AkidaSupportState.exportableScaffoldWithWarnings:
        return 'Exportable — near capacity or approximate topology';
      case AkidaSupportState.unsupported:
        return 'Unsupported — see rejections';
      case AkidaSupportState.sdkDeployable:
        return 'Deployed — running via Akida SDK';
      case AkidaSupportState.sdkNotDeployable:
        return 'Not Deployable — SDK unavailable';
    }
  }

  /// Theme color for UI indicators.
  ///
  /// Purple/indigo for scaffold states (distinct from PYNQ teal and
  /// Teensy green) to visually reinforce the scaffold-only semantic
  /// boundary.
  Color get color {
    switch (this) {
      case AkidaSupportState.exportableScaffold:
        return const Color(0xFF5C6BC0); // Indigo 400
      case AkidaSupportState.exportableScaffoldWithWarnings:
        return const Color(0xFFFFA000); // Amber 700
      case AkidaSupportState.unsupported:
        return const Color(0xFFD32F2F); // Red 700
      case AkidaSupportState.sdkDeployable:
        return const Color(0xFF388E3C); // Green 700
      case AkidaSupportState.sdkNotDeployable:
        return const Color(0xFFD32F2F); // Red 700
    }
  }

  /// Icon for UI indicators.
  IconData get icon {
    switch (this) {
      case AkidaSupportState.exportableScaffold:
        return Icons.architecture;
      case AkidaSupportState.exportableScaffoldWithWarnings:
        return Icons.warning_amber_rounded;
      case AkidaSupportState.unsupported:
        return Icons.block;
      case AkidaSupportState.sdkDeployable:
        return Icons.check_circle;
      case AkidaSupportState.sdkNotDeployable:
        return Icons.cloud_off;
    }
  }
}

/// Response from Akida exportability planning endpoint.
class AkidaNetworkResponse {
  final AkidaSupportState supportState;
  final String akidaVersion;
  final String topologyVerdict;
  final List<String> warnings;
  final List<String> rejectionReasons;
  final Map<String, dynamic>? networkSummary;

  const AkidaNetworkResponse({
    required this.supportState,
    required this.akidaVersion,
    required this.topologyVerdict,
    required this.warnings,
    required this.rejectionReasons,
    this.networkSummary,
  });

  factory AkidaNetworkResponse.fromJson(Map<String, dynamic> json) {
    return AkidaNetworkResponse(
      supportState:
          AkidaSupportState.fromString(json['support_state'] as String),
      akidaVersion: json['akida_version'] as String? ?? 'akida',
      topologyVerdict: json['topology_verdict'] as String? ?? 'unknown',
      warnings:
          (json['warnings'] as List).map((e) => e as String).toList(),
      rejectionReasons:
          (json['rejections'] as List).map((e) => e as String).toList(),
      networkSummary: json['network_summary'] as Map<String, dynamic>?,
    );
  }
}

// ---------------------------------------------------------------------------
// Deploy job status — mirrors Akida SDK deployment lifecycle
// ---------------------------------------------------------------------------

/// Lifecycle state of an Akida SDK deploy job.
///
/// Maps to the backend's deployment pipeline states:
///   not_initialised → [notInitialised]
///   sdk_loading     → [sdkLoading]
///   model_mapping   → [modelMapping]
///   mapped          → [mapped]
///   running         → [running]
///   failed          → [failed]
enum AkidaDeployJobStatus {
  /// No deploy has been attempted yet.
  notInitialised,

  /// Akida SDK is being loaded and initialised.
  sdkLoading,

  /// Model is being mapped to Akida device/simulator.
  modelMapping,

  /// Model successfully mapped and ready to run.
  mapped,

  /// Model is actively running inference.
  running,

  /// Deploy or inference failed.
  failed;

  static AkidaDeployJobStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'not_initialised':
      case 'not_initialized':
        return AkidaDeployJobStatus.notInitialised;
      case 'sdk_loading':
        return AkidaDeployJobStatus.sdkLoading;
      case 'model_mapping':
        return AkidaDeployJobStatus.modelMapping;
      case 'mapped':
        return AkidaDeployJobStatus.mapped;
      case 'running':
        return AkidaDeployJobStatus.running;
      case 'failed':
        return AkidaDeployJobStatus.failed;
      default:
        return AkidaDeployJobStatus.notInitialised;
    }
  }

  double get progressFraction {
    switch (this) {
      case AkidaDeployJobStatus.notInitialised:
        return 0.0;
      case AkidaDeployJobStatus.sdkLoading:
        return 0.25;
      case AkidaDeployJobStatus.modelMapping:
        return 0.5;
      case AkidaDeployJobStatus.mapped:
        return 1.0;
      case AkidaDeployJobStatus.running:
        return 0.9;
      case AkidaDeployJobStatus.failed:
        return 0.0;
    }
  }
}

/// Deploy status snapshot from Akida backend.
class AkidaDeployJob {
  final AkidaDeployJobStatus status;
  final String? deviceInfo;

  const AkidaDeployJob({
    required this.status,
    this.deviceInfo,
  });

  factory AkidaDeployJob.fromJson(Map<String, dynamic> json) {
    return AkidaDeployJob(
      status: AkidaDeployJobStatus.fromString(json['state'] as String),
      deviceInfo: json['device_info'] as String?,
    );
  }
}
