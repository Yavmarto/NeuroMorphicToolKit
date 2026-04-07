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
