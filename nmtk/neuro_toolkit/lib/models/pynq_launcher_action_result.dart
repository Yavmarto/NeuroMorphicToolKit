import 'package:nmtk_ui_core/nmtk_ui_core.dart';

// NOTE: This file is also duplicated in `Neurochip/frontend/lib/models/`. The
// launcher retains it so `control_api_service.dart` — which is still consumed
// by the launcher's `ModuleProvider` for module lifecycle calls — continues
// to compile. The PYNQ-board endpoints of `ControlApiService` are now only
// exercised by the Neurochip frontend (see ADR-claude/0007); the launcher
// copy is kept because excising those methods is a separate slim-down change.

String? _normalizedWarning(Object? value) {
  final text = (value as String?)?.trim() ?? '';
  return text.isEmpty ? null : text;
}

class PynqOverlayInstallResult {
  const PynqOverlayInstallResult({
    required this.board,
    this.warning,
  });

  factory PynqOverlayInstallResult.fromJson(Map<String, dynamic> json) {
    final boardJson = json['board'] as Map<String, dynamic>? ?? json;
    return PynqOverlayInstallResult(
      board: PynqPairedBoard.fromJson(boardJson),
      warning: _normalizedWarning(json['overlayRestartWarning']),
    );
  }

  final PynqPairedBoard board;
  final String? warning;

  bool get hasWarning => warning != null;
}

class PynqRestartRuntimeResult {
  const PynqRestartRuntimeResult({
    required this.board,
    this.warning,
  });

  factory PynqRestartRuntimeResult.fromJson(Map<String, dynamic> json) {
    final boardJson = json['board'] as Map<String, dynamic>? ?? json;
    return PynqRestartRuntimeResult(
      board: PynqPairedBoard.fromJson(boardJson),
      warning: _normalizedWarning(json['warning']),
    );
  }

  final PynqPairedBoard board;
  final String? warning;

  bool get hasWarning => warning != null;
}
