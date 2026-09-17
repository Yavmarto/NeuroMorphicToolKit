import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'cnl_focus_provider.g.dart';

/// Immutable UI-focus state for the CNL editor ↔ canvas live-sync glow.
///
/// Exactly one of [focusedLine] or [focusedNodeId] is non-null at a time —
/// whichever was set most recently is the canonical focus direction.
/// Setting one clears the other automatically.
@immutable
class CnlFocusState {
  /// 1-based line number currently active in the CNL editor. Null when the
  /// last focus event came from the canvas side.
  final int? focusedLine;

  /// Canvas node ID that the user last tapped. Null when the last focus event
  /// came from the editor side.
  final String? focusedNodeId;

  const CnlFocusState({this.focusedLine, this.focusedNodeId});

  CnlFocusState copyWith({
    int? focusedLine,
    bool clearFocusedLine = false,
    String? focusedNodeId,
    bool clearFocusedNodeId = false,
  }) {
    return CnlFocusState(
      focusedLine: clearFocusedLine ? null : (focusedLine ?? this.focusedLine),
      focusedNodeId: clearFocusedNodeId
          ? null
          : (focusedNodeId ?? this.focusedNodeId),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CnlFocusState &&
          runtimeType == other.runtimeType &&
          focusedLine == other.focusedLine &&
          focusedNodeId == other.focusedNodeId;

  @override
  int get hashCode => Object.hash(focusedLine, focusedNodeId);
}

/// Provider that holds the current CNL editor ↔ canvas focus signal.
///
/// Setting one direction clears the other to prevent stale highlights.
/// Both setters are idempotent — calling with the same value is a no-op.
@riverpod
class CnlFocusNotifier extends _$CnlFocusNotifier {
  @override
  CnlFocusState build() => const CnlFocusState();

  /// Publish a 1-based line number from the editor cursor position.
  /// Clears [CnlFocusState.focusedNodeId].
  void setFocusedLine(int? line) {
    if (state.focusedLine == line && state.focusedNodeId == null) return;
    if (line == null && state.focusedLine == null) return;
    state = state.copyWith(
      focusedLine: line,
      clearFocusedLine: line == null,
      clearFocusedNodeId: true,
    );
  }

  /// Publish a canvas node ID from a node tap.
  /// Clears [CnlFocusState.focusedLine].
  void setFocusedNode(String? nodeId) {
    if (state.focusedNodeId == nodeId && state.focusedLine == null) return;
    if (nodeId == null && state.focusedNodeId == null) return;
    state = state.copyWith(
      focusedNodeId: nodeId,
      clearFocusedNodeId: nodeId == null,
      clearFocusedLine: true,
    );
  }
}
