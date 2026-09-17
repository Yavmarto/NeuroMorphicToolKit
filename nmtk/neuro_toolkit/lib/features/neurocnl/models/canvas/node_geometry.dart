import 'dart:math' as math;
import 'dart:ui';

/// Single source of truth for **how big a node card is and where its ports
/// sit**, shared by every canvas: the Architecture canvas ([NetworkCanvas]),
/// the pipeline-phase canvases (Train / Eval in [PipelinePhaseCanvas]), the
/// edge painters, the edge/port hit-testing, the minimap projection and
/// `canvas_provider.dart`'s grid-snap / auto-layout math.
///
/// Before this file existed each canvas carried its own footprint constants
/// and its own port-position math (four copies in `network_canvas.dart`, two
/// in `pipeline_phase_canvas.dart`), which is why the Architecture cards
/// rendered 150x132 with proportionally-spread ports while the Train/Eval
/// cards rendered 200-wide with fixed 28px port spacing — visibly two
/// different families of node. Every consumer now derives its numbers from
/// here.
///
/// Re-exported by `canvas_shared_widgets.dart`, so importing that file is
/// enough to get these.

// ── Port / edge hit geometry ─────────────────────────────────────────────────

/// Radius of the port dot circle.
const double kCanvasPortRadius = 6.0;

/// Square side length of the hit-target area around each port dot.
const double kCanvasPortHitTargetSize = 30.0;

/// Side length of the square hit target around an edge's delete `✕`.
const double kCanvasEdgeDeleteHitTargetSize = 26.0;

/// How far (in screen pixels) a tap may land from a wire and still select it.
const double kCanvasEdgeHitTolerance = 8.0;

// ── Card footprint ──────────────────────────────────────────────────────────

/// Card width in the desktop/horizontal layout.
const double kCanvasNodeWidth = 150.0;

/// Card width in the compact (narrow/vertical) layout. Deliberately equal to
/// [kCanvasNodeWidth] — the compact layout changes which *edges* the ports sit
/// on, not how wide a card is, so a card doesn't visibly resize when a pane
/// crosses the breakpoint.
const double kCanvasNodeWidthCompact = kCanvasNodeWidth;

/// Baseline card height. Cards only grow past this when their port count
/// demands it (see [canvasNodeSize]).
const double kCanvasNodeBaseHeight = 132.0;

/// Height of the accent-tinted header bar in the desktop/horizontal layout.
const double kCanvasNodeHeaderHeight = 44.0;

/// The compact layout has no header bar — the title is centred in the card —
/// but the ports still keep this much clearance from the top edge.
const double kCanvasNodeHeaderHeightCompact = 28.0;

/// Height of a collapsed card (Architecture-only: `!node.isVisible`), which
/// is just the header with nothing under it.
const double kCanvasNodeCollapsedHeight = 52.0;

/// Smallest gap allowed between two adjacent port dots on the same edge.
/// Ports are spread proportionally across the card, so this is what makes a
/// card grow: below roughly this spacing the 30px hit targets and the
/// 20px-tall outside labels start colliding.
const double kCanvasNodeMinPortSpacing = 26.0;

/// Largest port count a card's height accounts for. A node with more ports
/// than this crowds rather than growing without bound.
const int kCanvasNodeMaxPortsForHeight = 10;

/// Header height for the given layout.
double canvasNodeHeaderHeight({required bool compact}) =>
    compact ? kCanvasNodeHeaderHeightCompact : kCanvasNodeHeaderHeight;

/// On-canvas footprint of a node card holding [inputs] input and [outputs]
/// output ports.
///
/// Height stays at [kCanvasNodeBaseHeight] for the common 1–2 port node and
/// grows only when proportional port spacing would otherwise fall below
/// [kCanvasNodeMinPortSpacing].
Size canvasNodeSize({
  required int inputs,
  required int outputs,
  required bool compact,
  bool collapsed = false,
}) {
  final double width = compact ? kCanvasNodeWidthCompact : kCanvasNodeWidth;
  if (collapsed) {
    return Size(width, kCanvasNodeCollapsedHeight);
  }
  // Compact cards put every input on the top edge and every output on the
  // bottom, so port count drives *width* pressure, not height.
  if (compact) {
    return Size(width, kCanvasNodeBaseHeight);
  }
  final int ports = math
      .max(1, math.max(inputs, outputs))
      .clamp(1, kCanvasNodeMaxPortsForHeight);
  final double needed =
      kCanvasNodeHeaderHeight + (ports + 1) * kCanvasNodeMinPortSpacing;
  return Size(width, math.max(kCanvasNodeBaseHeight, needed));
}

// ── Port placement ──────────────────────────────────────────────────────────

/// Spreads port [index] of [count] evenly across [length], dividing the span
/// into `count + 1` gaps so the ports stay centred as [length] changes.
/// [inset] is how far in from the origin the usable span starts (e.g. past a
/// header bar).
double distributePortOffset({
  required int index,
  required int count,
  required double length,
  double inset = 0,
}) => inset + (length - inset) * (index + 1) / (count + 1);

/// Node-local centre of a port's dot — the point wires attach to, the point
/// the hit-test measures distance from, and the anchor an outside label is
/// placed against.
///
/// Horizontal layout: inputs run down the left edge and outputs down the
/// right, both below the header. Compact layout: inputs run along the top
/// edge and outputs along the bottom.
Offset canvasNodePortCentre({
  required int index,
  required int count,
  required Size cardSize,
  required bool isInput,
  required bool compact,
  bool collapsed = false,
}) {
  if (compact) {
    return Offset(
      distributePortOffset(index: index, count: count, length: cardSize.width),
      isInput
          ? kCanvasPortHitTargetSize / 2
          : cardSize.height - kCanvasPortHitTargetSize / 2,
    );
  }
  final double along = distributePortOffset(
    index: index,
    count: count,
    length: cardSize.height,
    // A collapsed card is only a header, so its ports use the whole height.
    inset: collapsed ? 0 : kCanvasNodeHeaderHeight,
  );
  return Offset(
    isInput
        ? kCanvasPortHitTargetSize / 2
        : cardSize.width - kCanvasPortHitTargetSize / 2,
    along,
  );
}

/// Node-local top-left of a port's square hit target. Callers that position
/// a [CanvasPortWidget] want this; callers that draw or measure want
/// [canvasNodePortCentre].
Offset canvasNodePortTopLeft({
  required int index,
  required int count,
  required Size cardSize,
  required bool isInput,
  required bool compact,
  bool collapsed = false,
}) =>
    canvasNodePortCentre(
      index: index,
      count: count,
      cardSize: cardSize,
      isInput: isInput,
      compact: compact,
      collapsed: collapsed,
    ) -
    const Offset(kCanvasPortHitTargetSize / 2, kCanvasPortHitTargetSize / 2);
