// Data models for BrainChip Akida scaffold-export and runtime verification.
//
// Mirrors the Python backend schemas from:
// - neurocnl AkidaExportResult / AkidaSupportState
// - Neurochip Akida backend (akida_backend.py)
//
// Exportability and runtime verification are modeled separately:
// - NeuroCNL reports whether the network is unsupported or exportable as a
//   scaffold package plus mapped handoff payload.
// - Neurochip later verifies whether that mapped payload is actually
//   deployable via the Akida SDK in the current environment.

import 'package:flutter/material.dart';

/// Support state for BrainChip Akida target.
///
/// Export-time scaffold states come from NeuroCNL.
/// SDK states are retained for UI compatibility and may be used by runtime
/// surfaces that collapse export and verification into a single badge.
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
        return 'Verified — Akida SDK runtime ready';
      case AkidaSupportState.sdkNotDeployable:
        return 'Scaffold Only — SDK verification blocked';
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

/// Response from the NeuroCNL Akida exportability endpoint.
class AkidaNetworkResponse {
  final AkidaSupportState supportState;
  final String akidaVersion;
  final String topologyVerdict;
  final List<String> warnings;
  final List<String> rejectionReasons;
  final Map<String, dynamic>? networkSummary;

  /// Pre-built mapped network for Neurochip /deploy/mapped.
  ///
  /// Null when [supportState] is [AkidaSupportState.unsupported] or when
  /// the topology is not faithful (e.g. recurrent / branching networks).
  final Map<String, dynamic>? mappedNetwork;

  const AkidaNetworkResponse({
    required this.supportState,
    required this.akidaVersion,
    required this.topologyVerdict,
    required this.warnings,
    required this.rejectionReasons,
    this.networkSummary,
    this.mappedNetwork,
  });

  factory AkidaNetworkResponse.fromJson(Map<String, dynamic> json) {
    return AkidaNetworkResponse(
      supportState: AkidaSupportState.fromString(
        json['support_state'] as String,
      ),
      akidaVersion: json['akida_version'] as String? ?? 'akida',
      topologyVerdict: json['topology_verdict'] as String? ?? 'unknown',
      warnings: (json['warnings'] as List).map((e) => e as String).toList(),
      rejectionReasons: (json['rejections'] as List)
          .map((e) => e as String)
          .toList(),
      networkSummary: json['network_summary'] as Map<String, dynamic>?,
      mappedNetwork: json['mapped_network'] as Map<String, dynamic>?,
    );
  }
}

// ---------------------------------------------------------------------------
// Runtime verification — reported by Neurochip verify/status endpoints
// ---------------------------------------------------------------------------

class AkidaSdkVerification {
  final bool sdkAvailable;
  final String sdkStatus;
  final List<String> sdkIssues;
  final String state;
  final Map<String, dynamic>? modelSummary;
  final String runtimeTarget;
  final String? deviceInfo;
  final String? sdkIssueDetail;

  const AkidaSdkVerification({
    required this.sdkAvailable,
    required this.sdkStatus,
    required this.sdkIssues,
    required this.state,
    this.modelSummary,
    this.runtimeTarget = 'unknown',
    this.deviceInfo,
    this.sdkIssueDetail,
  });

  factory AkidaSdkVerification.fromJson(Map<String, dynamic> json) {
    return AkidaSdkVerification(
      sdkAvailable: json['sdk_available'] as bool? ?? false,
      sdkStatus: json['sdk_status'] as String? ?? 'unknown',
      sdkIssues:
          (json['sdk_issues'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      state: json['state'] as String? ?? 'unknown',
      modelSummary: json['model_summary'] as Map<String, dynamic>?,
      runtimeTarget: json['runtime_target'] as String? ?? 'unknown',
      deviceInfo: json['device_info'] as String?,
      sdkIssueDetail: json['sdk_issue_detail'] as String?,
    );
  }

  bool get isDeployable => sdkStatus == 'deployable';
}

// ---------------------------------------------------------------------------
// Deploy job status — mirrors Akida backend lifecycle
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
      // 'constructed' means the model is built but SDK mapping failed or was
      // skipped (scaffold-only path). Treat as terminal mapped state so the
      // poll timer stops and the UI shows the package as ready.
      case 'constructed':
        return AkidaDeployJobStatus.mapped;
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

  const AkidaDeployJob({required this.status, this.deviceInfo});

  factory AkidaDeployJob.fromJson(Map<String, dynamic> json) {
    return AkidaDeployJob(
      status: AkidaDeployJobStatus.fromString(json['state'] as String),
      deviceInfo: json['device_info'] as String?,
    );
  }

  factory AkidaDeployJob.fromVerification(AkidaSdkVerification verification) {
    return AkidaDeployJob(
      status: AkidaDeployJobStatus.fromString(verification.state),
      deviceInfo: verification.deviceInfo,
    );
  }
}
