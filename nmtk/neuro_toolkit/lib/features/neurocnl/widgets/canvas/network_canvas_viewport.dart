import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/canvas.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/grid.dart';
import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_provider.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_viewport.dart';

/// [NetworkCanvas]-specific viewport plumbing: keeping [canvasProvider]'s
/// persisted viewport and the live [TransformationController] in sync, and
/// the animated pan-to-node used when a node is added.
///
/// Builds on the cross-canvas arithmetic in [CanvasViewportMixin] (world
/// matrix, scene/viewport conversion, zoom limits) with the parts that are
/// specific to this canvas: talking to [canvasProvider] and driving
/// [networkViewportFollowController].
mixin NetworkCanvasViewportMixin<T extends ConsumerStatefulWidget>
    on ConsumerState<T>
    implements CanvasViewportMixin<T> {
  /// Drives the animated pan-to-node triggered by
  /// [networkFollowPendingViewportFocus]. Owned by the host (needs a
  /// `vsync` from its `TickerProviderStateMixin`, created in `initState` and
  /// disposed in `dispose`).
  AnimationController get networkViewportFollowController;

  bool _syncingViewportFromState = false;

  /// Mirrors the live [InteractiveViewer] transform into [canvasProvider]
  /// whenever it changes, unless the change originated from
  /// [networkSyncViewportFromState] itself (guarded by
  /// [_syncingViewportFromState] to avoid an update/listen feedback loop).
  void networkHandleViewportChanged() {
    if (_syncingViewportFromState) {
      return;
    }

    final Matrix4 matrix = canvasTransform.value;
    ref
        .read(canvasProvider.notifier)
        .updateViewport(
          zoom: matrix.getMaxScaleOnAxis(),
          pan: <double>[
            matrix.storage[12] +
                canvasWorld.origin.dx * matrix.getMaxScaleOnAxis(),
            matrix.storage[13] +
                canvasWorld.origin.dy * matrix.getMaxScaleOnAxis(),
          ],
        );
  }

  /// Applies [viewport] (from [canvasProvider]) to the live transform when it
  /// didn't originate from the gesture itself -- e.g. `resetViewport()`.
  void networkSyncViewportFromState(CanvasViewport viewport) {
    final Matrix4 matrix = canvasTransform.value;
    final CanvasViewport controllerViewport = CanvasViewport(
      zoom: matrix.getMaxScaleOnAxis(),
      pan: <double>[
        matrix.storage[12] + canvasWorld.origin.dx * matrix.getMaxScaleOnAxis(),
        matrix.storage[13] + canvasWorld.origin.dy * matrix.getMaxScaleOnAxis(),
      ],
    );
    if (controllerViewport.isCloseTo(viewport)) {
      return;
    }

    _syncingViewportFromState = true;
    canvasTransform.value = canvasWorldMatrix(
      zoom: viewport.zoom,
      pan: Offset(viewport.pan[0], viewport.pan[1]),
    );
    _syncingViewportFromState = false;
  }

  /// Animates the viewport to center [nodeId] (keeping the current zoom)
  /// then clears the pending signal so it doesn't re-trigger on unrelated
  /// rebuilds. Triggered by [CanvasController.addNode] /
  /// [CanvasController.addPipelineDagNode] setting
  /// `pendingViewportFocusNodeId` -- see the `ref.listen` in `build`.
  void networkFollowPendingViewportFocus(String nodeId) {
    final canvasNotifier = ref.read(canvasProvider.notifier);
    canvasNotifier.clearPendingViewportFocusNodeId();

    CanvasNode? node;
    for (final CanvasNode n in ref.read(canvasProvider).graph.nodes) {
      if (n.id == nodeId) {
        node = n;
        break;
      }
    }
    if (node == null) return;

    final RenderBox? box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final Matrix4 current = canvasTransform.value;
    final double zoom = current.getMaxScaleOnAxis();
    final Offset sceneCenter = Offset(
      node.position[0] + node.width / 2,
      node.position[1] + node.height / 2,
    );
    final Offset pan = centeredPanFor(sceneCenter, zoom, box.size);
    final Matrix4 target = canvasWorldMatrix(zoom: zoom, pan: pan);

    final Animation<Matrix4> animation =
        Matrix4Tween(begin: current, end: target).animate(
          CurvedAnimation(
            parent: networkViewportFollowController,
            curve: Curves.easeOutCubic,
          ),
        );
    late final VoidCallback listener;
    listener = () => canvasTransform.value = animation.value;
    animation.addListener(listener);
    networkViewportFollowController
      ..reset()
      ..forward().whenCompleteOrCancel(
        () => animation.removeListener(listener),
      );
  }

  /// Applies a keyboard-shortcut zoom step, keeping [canvasProvider] and the
  /// transform in sync the same way a pinch/scroll gesture would.
  void networkAdjustZoom(double multiplier) {
    final Matrix4? updatedMatrix = canvasZoomedBy(multiplier);
    if (updatedMatrix == null) {
      return;
    }
    _syncingViewportFromState = true;
    canvasTransform.value = updatedMatrix;
    _syncingViewportFromState = false;
    ref
        .read(canvasProvider.notifier)
        .updateViewport(
          zoom: updatedMatrix.getMaxScaleOnAxis(),
          pan: <double>[updatedMatrix.storage[12], updatedMatrix.storage[13]],
        );
  }
}
