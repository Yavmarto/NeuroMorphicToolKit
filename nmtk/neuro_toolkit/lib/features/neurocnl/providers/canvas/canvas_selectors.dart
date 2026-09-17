import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';

final canvasSelectedNodeIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(canvasProvider.select((s) => s.selectedNodeIds));
});

final canvasSelectedNodeIdProvider = Provider<String?>((ref) {
  return ref.watch(canvasProvider.select((s) => s.primarySelectedNodeId));
});

/// Id of the node currently "armed" for deletion by a long-press, or null.
///
/// Ephemeral UI interaction state, not graph data — deliberately kept out of
/// [canvasProvider] (and so out of undo/redo history). A long-press on a
/// node's card sets this; tapping the resulting trash badge removes the node
/// and clears it; tapping anywhere else on the canvas also clears it without
/// deleting. Shared by both the Architecture canvas and the pipeline-phase
/// (Train/Eval/Infer) canvases so long-press-to-delete behaves identically.
class ArmedForDeleteNodeIdNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? nodeId) => state = nodeId;
}

final armedForDeleteNodeIdProvider =
    NotifierProvider<ArmedForDeleteNodeIdNotifier, String?>(
      ArmedForDeleteNodeIdNotifier.new,
    );
