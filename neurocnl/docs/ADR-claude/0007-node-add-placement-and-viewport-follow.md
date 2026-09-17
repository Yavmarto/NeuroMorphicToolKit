# ADR 0007: Deterministic right/below node placement with viewport-follow on add

## Status
Accepted

## Context
Adding a node to the architecture graph or a pipeline phase DAG used to snap it to
whichever free grid cell was nearest to an arbitrary drop/tap position, and never
moved the viewport. On a large or zoomed-in canvas, a newly added node could land
off-screen with no visual indication of where it went, and repeated adds produced
an unpredictable scatter instead of a readable layout.

## Decision
`CanvasController.addNode` and `addPipelineDagNode` (`canvas_provider.dart`) now
place a new node relative to a resolved "reference node": the single selected node
if there is exactly one, otherwise the most recently added node (list append order
already guarantees `.last` is it), otherwise (empty graph) the prior
nearest-free-cell behavior. `findNextCellRightOrBelow` (`grid.dart`) picks the
immediate right or below cell first, expanding outward within that quadrant only if
both are occupied, so a node never lands to the left of or above its reference.

Direction is controlled by a `preferRight` flag the caller supplies, keyed off the
same `NmtkShellTokens.compactBreakpoint` (840px) mobile/desktop split already used
for canvas layout: desktop-width canvases try right-then-below, narrow/mobile-width
canvases try below-then-right — mirroring how the canvas itself reflows from a
horizontal to a vertical layout at that breakpoint. This mapping is not obvious
from the requirement alone, which is why it is recorded here.

Both `addNode` and `addPipelineDagNode` also set a transient
`pendingViewportFocusNodeId` on `CanvasState`. The owning canvas widget
(`network_canvas.dart`, `pipeline_phase_canvas.dart`) listens for it and animates
its `TransformationController` to pan (keeping zoom) onto the new node, then clears
the flag. The transient-state route (rather than the widget driving the pan
directly) was necessary because one add-node entry point
(`canvas_screen.dart`'s "+" popup picker) lives outside the canvas widget's own
state and has no handle on its `TransformationController`.

## Consequences
- **Positive:** New-node placement is predictable and readable regardless of drop
  position; the viewport always shows the user where the new node landed.
- **Positive:** The `preferRight` parameter defaults to `true` rather than being
  required, so the ~25 existing test call sites across the frontend suite did not
  need to change.
- **Negative:** A node's on-screen position after `addNode` no longer reflects
  where the user dropped it (except for the first node in an empty graph/DAG) —
  only its position relative to the reference node.
