import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:neuro_toolkit/ui_core/nmtk_ui_core.dart';

import 'package:neuro_toolkit/features/neurocnl/models/canvas/grid.dart';
import 'package:neuro_toolkit/features/neurocnl/models/canvas/node_geometry.dart';

// Card footprint, port placement and hit-target sizes all live in
// models/canvas/node_geometry.dart (no widget dependencies, so the model and
// provider layers can share it). Re-exported so importing this file is enough.
export 'package:neuro_toolkit/features/neurocnl/models/canvas/node_geometry.dart';

// ── Widget ────────────────────────────────────────────────────────────────────

/// A shared, self-contained port-dot widget used identically by the
/// Architecture canvas ([NetworkCanvas]) and the pipeline-phase canvases
/// (Train / Eval / Infer in [PipelinePhaseCanvas]).
///
/// The widget handles **both** tap-to-connect and drag-to-connect interactions:
///
/// - **Output ports** receive [onTap] and [onPanStart/Update/End]
///   (drag-to-connect with live-wire preview). The pan recognizer competes
///   with the parent [InteractiveViewer]'s scale recognizer for 1-finger
///   drags, and wins for touches that begin on the port hit area.
///
/// - **Input ports** receive [onTap] only. No pan handlers are registered, so
///   the canvas can still be scrolled by dragging over an input port.
///
/// The dot doubles as the "add a connected node" affordance: it carries a `+`
/// glyph, and the host canvas gives the second consecutive tap on the same port
/// a different meaning (open the node palette) from the first (arm a
/// connection). See [isArmed].
///
/// Callers wrap this in a [Positioned] at the correct scene-space coordinate.
class CanvasPortWidget extends StatelessWidget {
  const CanvasPortWidget({
    super.key,
    this.gestureDetectorKey,
    required this.isInput,
    required this.isConnecting,
    required this.isActive,
    required this.canAcceptConnection,
    this.isHoverCandidate = false,
    this.isArmed = false,
    this.onTap,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.tooltip,
    this.portRadius = kCanvasPortRadius,
    this.hitTargetSize = kCanvasPortHitTargetSize,
  });

  /// Optional key forwarded to the inner [GestureDetector].
  /// Used by widget tests that look up ports by key.
  final Key? gestureDetectorKey;

  /// True for input (left-side) ports; false for output (right-side) ports.
  final bool isInput;

  /// True while any connection drag/tap is in progress on the canvas.
  final bool isConnecting;

  /// True when this specific port is the active connection source.
  final bool isActive;

  /// True when this port is a valid drop target for the in-progress connection.
  final bool canAcceptConnection;

  /// True when this is the single nearest compatible port to a currently
  /// hovering stylus (before contact) -- a stronger, more specific cue than
  /// [canAcceptConnection]'s uniform highlight: "this is where the
  /// connection will land if you touch down now."
  final bool isHoverCandidate;

  /// True when this port is the one the user tapped last, so the *next* tap on
  /// it opens the add-node palette rather than arming a connection. Drives the
  /// stronger `+` treatment that tells the user a second tap does something
  /// different.
  final bool isArmed;

  /// Clean-tap callback. Used for tap-to-connect (output) and
  /// tap-to-complete (input).
  final VoidCallback? onTap;

  /// Pan-start callback. Output ports pass this to begin a drag-to-connect.
  /// Having a pan recognizer registered here prevents [InteractiveViewer]
  /// from consuming the drag gesture when the touch begins on the port.
  final GestureDragStartCallback? onPanStart;

  /// Pan-update callback. Output ports provide the pointer's
  /// [DragUpdateDetails.globalPosition] to the canvas for coordinate
  /// conversion and live-wire preview.
  final GestureDragUpdateCallback? onPanUpdate;

  /// Pan-end callback. Output ports use this to resolve the drop target.
  final GestureDragEndCallback? onPanEnd;

  /// Optional tooltip shown on hover.
  final String? tooltip;

  /// Radius of the visual dot (before the active-state size boost).
  final double portRadius;

  /// Width and height of the square tap/drag hit-target area.
  final double hitTargetSize;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color baseFill = isInput
        ? theme.colorScheme.secondaryContainer
        : theme.colorScheme.primaryContainer;
    final Color baseBorder = isInput
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;
    final Color fillColor = isActive
        ? baseBorder.withValues(alpha: 0.2)
        : isHoverCandidate
        ? baseBorder.withValues(alpha: 0.35)
        : canAcceptConnection
        ? baseBorder.withValues(alpha: 0.14)
        : baseFill;

    final bool emphasized = isActive || isHoverCandidate || isArmed;

    final bool interactive =
        onTap != null || onPanStart != null || onPanUpdate != null;

    // Diameter of the dot. The `+` glyph is sized from this so it stays inside
    // the circle at both the resting and emphasized sizes.
    final double diameter = portRadius * 2 + (emphasized ? 8 : 4);

    Widget child = GestureDetector(
      key: gestureDetectorKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onPanStart: onPanStart,
      onPanUpdate: onPanUpdate,
      onPanEnd: onPanEnd,
      child: SizedBox(
        width: hitTargetSize,
        height: hitTargetSize,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: diameter,
            height: diameter,
            decoration: BoxDecoration(
              color: fillColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: baseBorder,
                width: isHoverCandidate ? 3 : 2,
              ),
            ),
            // The port *is* the add-node button. The `+` is faint at rest so a
            // graph full of ports doesn't read as a wall of buttons, and firms
            // up once the port is armed and a second tap will open the palette.
            child: Center(
              child: Icon(
                ZetaIcons.add,
                size: diameter - 5,
                color: baseBorder.withValues(alpha: isArmed ? 1.0 : 0.55),
              ),
            ),
          ),
        ),
      ),
    );

    if (interactive) {
      child = MouseRegion(cursor: SystemMouseCursors.click, child: child);
    }

    if (tooltip != null) {
      child = Tooltip(message: tooltip!, child: child);
    }

    return child;
  }
}

/// The `✕` shown at the midpoint of the currently selected edge.
///
/// Edges are thin, awkward hit targets and there was previously no on-screen way
/// to remove one — only a Delete/Backspace shortcut a user has no reason to
/// guess. Selecting an edge now reveals this.
///
/// Deliberately **tap-only**: pan handlers here would compete with the parent
/// [InteractiveViewer] for a gesture the button has no use for.
class CanvasEdgeDeleteButton extends StatelessWidget {
  const CanvasEdgeDeleteButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Delete connection',
    this.hitTargetSize = kCanvasEdgeDeleteHitTargetSize,
  });

  final VoidCallback onPressed;
  final String tooltip;

  /// Width and height of the square tap target.
  final double hitTargetSize;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: SizedBox(
            width: hitTargetSize,
            height: hitTargetSize,
            child: Center(
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: NmtkShellTokens.of(context).errorColor,
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  ZetaIcons.close,
                  size: 13,
                  color: NmtkShellTokens.of(context).errorColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shared node-card chrome: the box decoration (background, border, radius,
/// shadow) used identically by every canvas's node card ([NetworkCanvas]'s
/// `_CanvasNodeWidget` and [PipelinePhaseCanvas]'s `_PipelineDagNodeWidget`).
///
/// Before this widget existed, each canvas built its own near-identical
/// [BoxDecoration] by hand, so the two drifted out of sync (different corner
/// radius, border width, shadow). This is the single place that defines what
/// a node card looks like; canvases only supply the accent/selection state
/// and their own header/body content as [child].
///
/// Deliberately has no resize affordance — nodes are fixed-size on every
/// canvas.
class NodeCardChrome extends StatelessWidget {
  const NodeCardChrome({
    super.key,
    required this.width,
    required this.height,
    required this.isSelected,
    required this.background,
    this.borderColor,
    this.borderWidth,
    required this.child,
  });

  final double width;
  final double height;

  /// True when the node is selected or otherwise highlighted; thickens and
  /// recolors the border to the theme's accent.
  final bool isSelected;

  final Color background;

  /// Overrides the border color regardless of [isSelected] (e.g. a
  /// spike-rate color during a training/results scrub). Falls back to the
  /// theme's outline / accent color when null.
  final Color? borderColor;

  /// Overrides the border width regardless of [isSelected].
  final double? borderWidth;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final NmtkShellTokens tokens = NmtkShellTokens.of(context);
    final Color resolvedBorder =
        borderColor ??
        (isSelected ? tokens.studioPalette.accent : tokens.chromeBorder);
    final double resolvedWidth =
        borderWidth ?? (isSelected || borderColor != null ? 2 : 1);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        border: Border.all(color: resolvedBorder, width: resolvedWidth),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ── Shared header/title content ─────────────────────────────────────────────

const double kNodeCardIconSizeRegular = 14.0;
const double kNodeCardIconSizeDense = 12.0;
const double kNodeCardTitleFontSizeRegular = 12.0;
const double kNodeCardTitleFontSizeDense = 11.0;
const FontWeight kNodeCardTitleFontWeight = FontWeight.w700;
const double kNodeCardSubtitleFontSize = 9.0;
const EdgeInsets kNodeCardHeaderPadding = EdgeInsets.symmetric(horizontal: 10);

/// The icon + title (+ optional subtitle) row shared by every node card's
/// title area, in both the fixed header bar (desktop/horizontal) and the
/// centered-in-card row (mobile/vertical) layouts.
///
/// Before this widget existed, [network_canvas.dart]'s and
/// [pipeline_phase_canvas.dart]'s node widgets each built their own icon+text
/// row by hand, and drifted (different font weight, different size). This is
/// the single place that defines what a node card's title looks like.
///
/// [subtitle] is optional so a caller (currently only the pipeline canvases'
/// "key param" second line) can supply one without a second, parallel
/// implementation — callers that don't need it simply omit it.
class NodeCardTitleContent extends StatelessWidget {
  const NodeCardTitleContent({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.subtitleColor,
    this.dense = false,
    this.centered = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Color? subtitleColor;

  /// Uses the smaller icon/title type scale (mobile/vertical layouts).
  final bool dense;

  /// Centers the row instead of left-aligning + expanding the title
  /// (mobile/vertical centered-in-card layout vs. a fixed header bar).
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final double iconSize = dense
        ? kNodeCardIconSizeDense
        : kNodeCardIconSizeRegular;
    final double titleFontSize = dense
        ? kNodeCardTitleFontSizeDense
        : kNodeCardTitleFontSizeRegular;

    final Widget titleText = Text(
      title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: centered ? TextAlign.center : TextAlign.start,
      style: TextStyle(
        fontWeight: kNodeCardTitleFontWeight,
        fontSize: titleFontSize,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );

    final Widget titleColumn = subtitle == null
        ? titleText
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: centered
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              titleText,
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: centered ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  fontSize: kNodeCardSubtitleFontSize,
                  color: subtitleColor ?? iconColor,
                ),
              ),
            ],
          );

    final Icon iconWidget = Icon(icon, size: iconSize, color: iconColor);

    if (centered) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          iconWidget,
          const SizedBox(width: 6),
          Flexible(child: titleColumn),
        ],
      );
    }

    return Row(
      children: [
        iconWidget,
        const SizedBox(width: 6),
        Expanded(child: titleColumn),
      ],
    );
  }
}

/// The fixed-height, accent-tinted header bar at the top of a desktop/
/// horizontal node card. Wraps [NodeCardTitleContent] with the header's own
/// gesture handling and corner rounding.
///
/// [roundBottomCorners] is Architecture-only: pass `!node.isVisible` there —
/// a collapsed node has no body under the header, so the whole card is just
/// the header and needs bottom corners rounded too. Pipeline nodes have no
/// collapse concept and always pass `false`.
class NodeCardHeaderBar extends StatelessWidget {
  const NodeCardHeaderBar({
    super.key,
    required this.height,
    required this.accentColor,
    required this.icon,
    required this.title,
    this.subtitle,
    this.roundBottomCorners = false,
    this.onTap,
    this.onDoubleTap,
    this.onDoubleTapDown,
  });

  final double height;
  final Color accentColor;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool roundBottomCorners;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final GestureTapDownCallback? onDoubleTapDown;

  @override
  Widget build(BuildContext context) {
    final Radius topRadius = Radius.circular(NmtkShellTokens.of(context).radiusSm);
    final Radius bottomRadius = roundBottomCorners ? topRadius : Radius.zero;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.only(
          topLeft: topRadius,
          topRight: topRadius,
          bottomLeft: bottomRadius,
          bottomRight: bottomRadius,
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onDoubleTapDown: onDoubleTapDown,
        child: Padding(
          padding: kNodeCardHeaderPadding,
          child: NodeCardTitleContent(
            icon: icon,
            iconColor: accentColor,
            title: title,
            subtitle: subtitle,
            subtitleColor: accentColor,
          ),
        ),
      ),
    );
  }
}

// ── Shared outside-port-label placement ─────────────────────────────────────

/// Gap between a card's edge and its nearest outside label, in the
/// compact (mobile/vertical) layout.
const double kOutsideLabelCardGap = 4.0;

/// Vertical distance between stacked rows of outside labels sharing an edge,
/// in the compact (mobile/vertical) layout.
const double kOutsideLabelRowHeight = 20.0;

/// Places a [CanvasOutsideLabel] for one port outside its node card.
///
/// In the desktop/horizontal layout, each port already has a distinct
/// position along its edge, so one row per label is enough. In the compact
/// (mobile/vertical) layout every input sits on the shared top edge and
/// every output on the shared bottom edge; [edgeIndex] (this port's position
/// among the ports on the *same* edge) pushes each successive label one more
/// row further from the card, so labels fan outward instead of overlapping.
Widget buildOutsidePortLabel({
  required String text,
  required Offset anchor,
  required bool portIsInput,
  required bool isCompact,
  required double nodeWidth,
  required double nodeHeight,
  required int edgeIndex,
}) {
  if (isCompact) {
    final double outward =
        nodeHeight + kOutsideLabelCardGap + edgeIndex * kOutsideLabelRowHeight;
    return Positioned(
      left: anchor.dx - 40,
      width: 80,
      top: portIsInput ? null : outward,
      bottom: portIsInput ? outward : null,
      child: Center(
        child: CanvasOutsideLabel(text: text, textAlign: TextAlign.center),
      ),
    );
  }
  return Positioned(
    top: anchor.dy - 10,
    right: portIsInput ? nodeWidth + 6 : null,
    left: portIsInput ? null : nodeWidth + 6,
    child: CanvasOutsideLabel(text: text),
  );
}

/// A small trash badge shown on a node's corner while it is armed for
/// deletion (long-pressed). Tapping it deletes the node; tapping anywhere
/// else on the canvas disarms it without deleting.
///
/// Occupies the same corner the old per-canvas resize handle used to sit in
/// — nodes are no longer resizable, so that corner was free.
class NodeDeleteBadge extends StatelessWidget {
  const NodeDeleteBadge({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final NmtkShellTokens tokens = NmtkShellTokens.of(context);

    return Tooltip(
      message: 'Delete node',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: tokens.errorColor,
              shape: BoxShape.circle,
              border: Border.all(color: Zeta.of(context).colors.mainInverse, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Icon(ZetaIcons.delete, size: 14, color: Zeta.of(context).colors.mainInverse),
          ),
        ),
      ),
    );
  }
}

/// Opaque pill label for a port name drawn outside its node card, next to
/// the connecting line.
///
/// An opaque background (rather than bare colored text) guarantees
/// legibility regardless of what's behind it — a wire crossing underneath,
/// the canvas grid, or a neighboring node card — instead of depending on one
/// text color happening to contrast with every wire color and theme.
class CanvasOutsideLabel extends StatelessWidget {
  const CanvasOutsideLabel({
    super.key,
    required this.text,
    this.textAlign = TextAlign.start,
    this.maxWidth = 96,
  });

  final String text;
  final TextAlign textAlign;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final NmtkShellTokens tokens = NmtkShellTokens.of(context);
    final ThemeData theme = Theme.of(context);
    return IgnorePointer(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.chromeBorder),
          ),
          child: Text(
            text,
            textAlign: textAlign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Shared node card ────────────────────────────────────────────────────────

/// One port on a [CanvasNodeCard]: everything the card needs to draw the dot,
/// label it, and report interactions back to its canvas.
///
/// Canvas-model-agnostic on purpose — the Architecture canvas builds these
/// from `NirPortDef`s and the pipeline canvases from `PortSpec`s, which are
/// unrelated types.
class CanvasCardPort {
  const CanvasCardPort({
    required this.id,
    required this.label,
    required this.isInput,
    this.tooltip,
    this.isActive = false,
    this.canAcceptConnection = false,
    this.isHoverCandidate = false,
    this.isArmed = false,
    this.onTap,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
  });

  final String id;

  /// Text shown in the label pill outside the card, next to the dot.
  final String label;

  final bool isInput;
  final String? tooltip;
  final bool isActive;
  final bool canAcceptConnection;
  final bool isHoverCandidate;
  final bool isArmed;

  final VoidCallback? onTap;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
}

/// The node card drawn on every canvas — Architecture, Train and Eval.
///
/// Composes the pieces above ([NodeCardChrome], [NodeCardHeaderBar] /
/// [NodeCardTitleContent], [NodeDeleteBadge], [CanvasPortWidget],
/// [buildOutsidePortLabel]) into the one card layout, and takes its footprint
/// and port positions from `canvas_node_geometry.dart`.
///
/// Each canvas keeps a thin adapter that maps its own node model onto these
/// props; nothing about a specific graph model appears here. The card sizes
/// itself to [cardSize] and expects the caller to place it (Architecture wraps
/// it in a scene-space [Positioned]; the pipeline canvases position it from
/// their own node list).
class CanvasNodeCard extends StatelessWidget {
  const CanvasNodeCard({
    super.key,
    required this.nodeId,
    required this.cardSize,
    required this.accentColor,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.background,
    this.isSelected = false,
    this.borderColor,
    this.borderWidth,
    this.compact = false,
    this.collapsed = false,
    this.ports = const <CanvasCardPort>[],
    this.isConnecting = false,
    this.trailingBadge,
    this.armedForDelete = false,
    this.onDelete,
    this.onTap,
    this.onDoubleTap,
    this.onDoubleTapDown,
    this.onPanStart,
    this.onPanUpdate,
    this.onPanEnd,
    this.onLongPress,
  });

  /// Used to key each port's gesture detector (`port_<nodeId>_<portId>`), which
  /// widget tests look up.
  final String nodeId;

  /// Footprint from [canvasNodeSize].
  final Size cardSize;

  final Color accentColor;
  final IconData icon;
  final String title;

  /// Optional second line under the title — the node's most telling parameter.
  final String? subtitle;

  final Color background;
  final bool isSelected;

  /// Overrides the border color regardless of [isSelected] (e.g. a spike-rate
  /// color while scrubbing training results).
  final Color? borderColor;
  final double? borderWidth;

  /// Compact (narrow pane / vertical) layout: no header bar, title centred,
  /// ports on the top and bottom edges instead of left and right.
  final bool compact;

  /// Architecture-only: the card is just a header with no body under it.
  final bool collapsed;

  final List<CanvasCardPort> ports;

  /// True while any connection drag/tap is in progress anywhere on the canvas.
  final bool isConnecting;

  /// Optional badge pinned to the card's top-right corner (the spike-rate
  /// pill during a training/results scrub).
  final Widget? trailingBadge;

  final bool armedForDelete;
  final VoidCallback? onDelete;

  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final ValueChanged<PointerDeviceKind>? onDoubleTapDown;
  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final VoidCallback? onLongPress;

  List<CanvasCardPort> get _inputs =>
      ports.where((CanvasCardPort p) => p.isInput).toList();

  List<CanvasCardPort> get _outputs =>
      ports.where((CanvasCardPort p) => !p.isInput).toList();

  Offset _portCentre(int index, int count, bool isInput) =>
      canvasNodePortCentre(
        index: index,
        count: count,
        cardSize: cardSize,
        isInput: isInput,
        compact: compact,
        collapsed: collapsed,
      );

  Widget _dot(CanvasCardPort port, Offset centre) => Positioned(
    left: centre.dx - kCanvasPortHitTargetSize / 2,
    top: centre.dy - kCanvasPortHitTargetSize / 2,
    child: CanvasPortWidget(
      gestureDetectorKey: ValueKey<String>('port_${nodeId}_${port.id}'),
      isInput: port.isInput,
      isConnecting: isConnecting,
      isActive: port.isActive,
      canAcceptConnection: port.canAcceptConnection,
      isHoverCandidate: port.isHoverCandidate,
      isArmed: port.isArmed,
      tooltip: port.tooltip,
      onTap: port.onTap,
      onPanStart: port.onPanStart,
      onPanUpdate: port.onPanUpdate,
      onPanEnd: port.onPanEnd,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final List<CanvasCardPort> inputs = _inputs;
    final List<CanvasCardPort> outputs = _outputs;

    final Widget titleRow = NodeCardTitleContent(
      icon: icon,
      iconColor: accentColor,
      title: title,
      subtitle: subtitle,
      dense: true,
      centered: true,
    );

    // Compact cards have no header bar: the title sits in the middle of the
    // card, clear of the ports on the top and bottom edges.
    final Widget cardContent = compact
        ? Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              onDoubleTap: onDoubleTap,
              onDoubleTapDown: onDoubleTapDown == null
                  ? null
                  : (TapDownDetails details) => onDoubleTapDown!(
                      details.kind ?? PointerDeviceKind.mouse,
                    ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: titleRow,
              ),
            ),
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NodeCardHeaderBar(
                height: kCanvasNodeHeaderHeight,
                accentColor: accentColor,
                icon: icon,
                title: title,
                subtitle: subtitle,
                roundBottomCorners: collapsed,
                onTap: onTap,
                onDoubleTap: onDoubleTap,
                onDoubleTapDown: onDoubleTapDown == null
                    ? null
                    : (TapDownDetails details) => onDoubleTapDown!(
                        details.kind ?? PointerDeviceKind.mouse,
                      ),
              ),
            ],
          );

    return SizedBox(
      width: cardSize.width,
      height: cardSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            onDoubleTapDown: onDoubleTapDown == null
                ? null
                : (TapDownDetails details) =>
                      onDoubleTapDown!(details.kind ?? PointerDeviceKind.mouse),
            onPanStart: onPanStart,
            onPanUpdate: onPanUpdate,
            onPanEnd: onPanEnd,
            onLongPress: onLongPress,
            child: NodeCardChrome(
              width: cardSize.width,
              height: cardSize.height,
              isSelected: isSelected,
              background: background,
              borderColor: borderColor,
              borderWidth: borderWidth,
              child: cardContent,
            ),
          ),

          if (armedForDelete && onDelete != null)
            Positioned(
              right: -8,
              top: -8,
              child: NodeDeleteBadge(onPressed: onDelete!),
            ),

          for (int i = 0; i < inputs.length; i += 1)
            _dot(inputs[i], _portCentre(i, inputs.length, true)),
          for (int i = 0; i < outputs.length; i += 1)
            _dot(outputs[i], _portCentre(i, outputs.length, false)),

          for (int i = 0; i < inputs.length; i += 1)
            buildOutsidePortLabel(
              text: inputs[i].label,
              anchor: _portCentre(i, inputs.length, true),
              portIsInput: true,
              isCompact: compact,
              nodeWidth: cardSize.width,
              nodeHeight: cardSize.height,
              edgeIndex: i,
            ),
          for (int i = 0; i < outputs.length; i += 1)
            buildOutsidePortLabel(
              text: outputs[i].label,
              anchor: _portCentre(i, outputs.length, false),
              portIsInput: false,
              isCompact: compact,
              nodeWidth: cardSize.width,
              nodeHeight: cardSize.height,
              edgeIndex: i,
            ),

          if (trailingBadge != null)
            Positioned(right: 4, top: 4, child: trailingBadge!),
        ],
      ),
    );
  }
}

// ── Shared background grid ──────────────────────────────────────────────────

/// The canvas background grid, drawn under every canvas's content.
///
/// Lived in `network_canvas.dart` and was reached from the pipeline canvases
/// by a cross-widget `show GridPainter` import, which made the Architecture
/// canvas a de-facto library for the others.
class GridPainter extends CustomPainter {
  GridPainter({
    required this.transform,
    this.sceneOrigin = Offset.zero,
    this.lineColor = const Color(0x14FFFFFF),
  });

  final Matrix4 transform;
  final Offset sceneOrigin;
  final Color lineColor;
  final Paint _linePaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    final Matrix4? inverse = Matrix4.tryInvert(transform);
    if (inverse == null) return;

    final Offset childTopLeft = MatrixUtils.transformPoint(
      inverse,
      Offset.zero,
    );
    final Offset childBottomRight = MatrixUtils.transformPoint(
      inverse,
      Offset(size.width, size.height),
    );

    final Offset worldTopLeft = childTopLeft - sceneOrigin;
    final Offset worldBottomRight = childBottomRight - sceneOrigin;
    final double startX =
        (worldTopLeft.dx / kGridCellWidth).floorToDouble() * kGridCellWidth;
    final double endX =
        (worldBottomRight.dx / kGridCellWidth).ceilToDouble() * kGridCellWidth;
    final double startY =
        (worldTopLeft.dy / kGridCellHeight).floorToDouble() * kGridCellHeight;
    final double endY =
        (worldBottomRight.dy / kGridCellHeight).ceilToDouble() *
        kGridCellHeight;

    final double scale = transform.getMaxScaleOnAxis();
    _linePaint
      ..color = lineColor
      ..strokeWidth = scale > 0 ? 1.0 / scale : 1.0;

    canvas.save();
    canvas.transform(transform.storage);
    canvas.translate(sceneOrigin.dx, sceneOrigin.dy);

    for (double x = startX; x <= endX; x += kGridCellWidth) {
      canvas.drawLine(Offset(x, startY), Offset(x, endY), _linePaint);
    }
    for (double y = startY; y <= endY; y += kGridCellHeight) {
      canvas.drawLine(Offset(startX, y), Offset(endX, y), _linePaint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant GridPainter oldDelegate) =>
      oldDelegate.transform != transform ||
      oldDelegate.sceneOrigin != sceneOrigin ||
      oldDelegate.lineColor != lineColor;
}

/// Rubber-band rectangle drawn over a canvas while marquee-selecting nodes.
class MarqueeSelectionPainter extends CustomPainter {
  const MarqueeSelectionPainter({
    required this.start,
    required this.end,
    required this.transform,
    this.sceneOrigin = Offset.zero,
    required this.color,
  });

  final Offset start;
  final Offset end;
  final Matrix4 transform;
  final Offset sceneOrigin;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect sceneRect = Rect.fromPoints(start, end);
    final Offset topLeft = MatrixUtils.transformPoint(
      transform,
      sceneRect.topLeft + sceneOrigin,
    );
    final Offset bottomRight = MatrixUtils.transformPoint(
      transform,
      sceneRect.bottomRight + sceneOrigin,
    );
    final Rect screenRect = Rect.fromPoints(topLeft, bottomRight);
    final Paint fill = Paint()
      ..color = color.withValues(alpha: 0.12)
      ..style = PaintingStyle.fill;
    final Paint stroke = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(screenRect, fill);
    canvas.drawRect(screenRect, stroke);
  }

  @override
  bool shouldRepaint(covariant MarqueeSelectionPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.transform != transform ||
        oldDelegate.sceneOrigin != sceneOrigin ||
        oldDelegate.color != color;
  }
}
