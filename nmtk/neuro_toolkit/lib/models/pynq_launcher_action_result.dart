import 'package:nmtk_ui_core/nmtk_ui_core.dart';

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
