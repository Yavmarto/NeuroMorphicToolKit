import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:neuro_toolkit/features/neurocnl/providers/canvas/canvas_selectors.dart';
import 'package:neuro_toolkit/features/neurocnl/widgets/canvas/canvas_shared_widgets.dart';

/// Everything [CanvasNodeCardWidget] needs to render one card, other than the
/// gesture callbacks that don't need a [BuildContext]/[WidgetRef] (see
/// [CanvasNodeCardWidget.onTap] et al.). Computed fresh on every build by
/// [CanvasNodeCardWidget.buildSpec] since most of it (selection state, theme
/// colors, live port state) is watched or context-derived.
typedef CanvasNodeCardSpec = ({
  Size cardSize,
  Color accentColor,
  IconData icon,
  String title,
  String? subtitle,
  Color background,
  bool isSelected,
  Color? borderColor,
  double? borderWidth,
  bool compact,
  bool collapsed,
  bool isConnecting,
  List<CanvasCardPort> ports,
  Widget? trailingBadge,
  GestureDragUpdateCallback onPanUpdate,
  GestureDragEndCallback onPanEnd,
  VoidCallback onLongPress,
  VoidCallback onDelete,
});

/// Base for every canvas's node card widget -- the Architecture canvas's
/// `CanvasNodeWidget` and the Train/Eval canvases' `_PipelineDagNodeWidget`.
///
/// Each canvas keeps its own adapter from its node model (`CanvasNode` /
/// `PipelineDagNode`) onto [CanvasNodeCard]'s props via [buildSpec], but the
/// actual gesture wiring -- watching the armed-for-delete provider and
/// assembling [CanvasNodeCard]'s callbacks -- used to be copy-pasted per
/// canvas. That duplication is why the mobile drag-vs-tap fix (CEL-476) only
/// reached the Architecture canvas: [onDragStart] replaces a raw
/// `onPanStart: (_) => onTap()`, so every canvas built on this base gets the
/// same caller-supplied drag-start behaviour instead of re-deriving it (see
/// `CanvasSurfaceState.dragStartGuard`).
abstract class CanvasNodeCardWidget extends ConsumerWidget {
  const CanvasNodeCardWidget({super.key});

  String get nodeId;

  VoidCallback get onTap;
  VoidCallback? get onDoubleTap => null;
  ValueChanged<PointerDeviceKind>? get onDoubleTapDown => null;

  /// Fires at pan-start. Callers should guard this with
  /// `CanvasSurfaceState.dragStartGuard` rather than wiring it straight to a
  /// selection callback, so a mobile touch-drag doesn't select (and pop the
  /// inspector sheet) before the drag is recognized.
  VoidCallback get onDragStart;

  /// Resolves the node model onto [CanvasNodeCard]'s visual props and its
  /// remaining (ref-dependent) gesture callbacks.
  CanvasNodeCardSpec buildSpec(BuildContext context, WidgetRef ref);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool armedForDelete = ref.watch(
      armedForDeleteNodeIdProvider.select((String? id) => id == nodeId),
    );
    final CanvasNodeCardSpec spec = buildSpec(context, ref);
    return CanvasNodeCard(
      nodeId: nodeId,
      cardSize: spec.cardSize,
      accentColor: spec.accentColor,
      icon: spec.icon,
      title: spec.title,
      subtitle: spec.subtitle,
      background: spec.background,
      isSelected: spec.isSelected,
      borderColor: spec.borderColor,
      borderWidth: spec.borderWidth,
      compact: spec.compact,
      collapsed: spec.collapsed,
      isConnecting: spec.isConnecting,
      ports: spec.ports,
      trailingBadge: spec.trailingBadge,
      armedForDelete: armedForDelete,
      onDelete: spec.onDelete,
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onDoubleTapDown: onDoubleTapDown,
      onPanStart: (_) => onDragStart(),
      onPanUpdate: spec.onPanUpdate,
      onPanEnd: spec.onPanEnd,
      onLongPress: spec.onLongPress,
    );
  }
}
