import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/workspace_provider.dart';

part 'nir_ui_state_provider.g.dart';

@riverpod
class NirUiStateController extends _$NirUiStateController {
  @override
  Map<String, Set<String>> build() => const <String, Set<String>>{};

  String? get _activeFileId => ref.read(workspaceProvider).activeFileId;

  void setNodeExpanded(String nodeId, bool expanded, {String? fileId}) {
    final resolvedFileId = fileId ?? _activeFileId;
    if (resolvedFileId == null) {
      return;
    }

    final nextExpanded = Set<String>.from(state[resolvedFileId] ?? const {});
    final changed = expanded
        ? nextExpanded.add(nodeId)
        : nextExpanded.remove(nodeId);
    if (!changed) {
      return;
    }

    state = <String, Set<String>>{
      ...state,
      resolvedFileId: Set<String>.unmodifiable(nextExpanded),
    };
  }
}

/// Backward-compat alias.
final nirUiStateProvider = nirUiStateControllerProvider;

final activeExpandedNirNodeIdsProvider = Provider<Set<String>>((ref) {
  final activeFileId = ref.watch(
    workspaceProvider.select((workspace) => workspace.activeFileId),
  );
  final state = ref.watch(nirUiStateControllerProvider);
  return state[activeFileId] ?? const <String>{};
});

final nirNodeExpandedProvider = Provider.family<bool, String>((ref, nodeId) {
  final expandedNodeIds = ref.watch(activeExpandedNirNodeIdsProvider);
  return expandedNodeIds.contains(nodeId);
});
