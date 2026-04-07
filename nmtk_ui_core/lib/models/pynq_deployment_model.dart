/// Data models for PYNQ Z2 export/deployment workflow.
///
/// Mirrors the Python backend schemas from:
/// - neurocnl PynqExportResult / PynqSupportState
/// - Neurochip PYNQ backend (issue 11)
///
/// Two-tier support model:
/// - **Exportable**: toolkit can produce overlay artifacts offline (no board needed)
/// - **Deployable**: overlay can be loaded onto real PYNQ hardware (runtime)

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

/// Response from PYNQ exportability planning endpoint.
class PynqNetworkResponse {
  final PynqSupportState supportState;
  final List<String> warnings;
  final List<String> rejectionReasons;
  final Map<String, dynamic>? networkSummary;

  const PynqNetworkResponse({
    required this.supportState,
    required this.warnings,
    required this.rejectionReasons,
    this.networkSummary,
  });

  factory PynqNetworkResponse.fromJson(Map<String, dynamic> json) {
    return PynqNetworkResponse(
      supportState:
          PynqSupportState.fromString(json['support_state'] as String),
      warnings:
          (json['warnings'] as List).map((e) => e as String).toList(),
      rejectionReasons:
          (json['rejections'] as List).map((e) => e as String).toList(),
      networkSummary: json['network_summary'] as Map<String, dynamic>?,
    );
  }
}

// ---------------------------------------------------------------------------
// Deploy job status — mirrors /hardware/pynq/status
// ---------------------------------------------------------------------------

/// Lifecycle state of a PYNQ backend deploy job.
enum PynqDeployJobStatus {
  /// No deploy has been attempted yet.
  notInitialised,

  /// Overlay is being loaded and weights written.
  deploying,

  /// Overlay loaded and backend is configured and ready to run.
  configured,

  /// Deploy failed.
  failed;

  static PynqDeployJobStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'not_initialised':
      case 'not_initialized':
        return PynqDeployJobStatus.notInitialised;
      case 'deploying':
        return PynqDeployJobStatus.deploying;
      case 'configured':
        return PynqDeployJobStatus.configured;
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
      case PynqDeployJobStatus.deploying:
        return 0.5;
      case PynqDeployJobStatus.configured:
        return 1.0;
      case PynqDeployJobStatus.failed:
        return 0.0;
    }
  }
}

/// Deploy status snapshot from GET /hardware/pynq/status.
class PynqDeployJob {
  final PynqDeployJobStatus status;
  final String? bitstreamPath;

  const PynqDeployJob({
    required this.status,
    this.bitstreamPath,
  });

  factory PynqDeployJob.fromJson(Map<String, dynamic> json) {
    return PynqDeployJob(
      status: PynqDeployJobStatus.fromString(json['state'] as String),
      bitstreamPath: json['bitstream_path'] as String?,
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
          .map((e) =>
              PynqSitlStepResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
