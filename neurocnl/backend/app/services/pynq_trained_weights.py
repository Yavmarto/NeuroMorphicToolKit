"""Overlay trained weights from a NIR graph onto a target network.

Two callers, one problem
------------------------
The PYNQ deploy payload is built from the **CNL spec**, and CNL deliberately
carries tensor *shape* only — ``nir_cnl/renderer.py`` says so outright ("CNL only
carries tensor shape; exact tensor payloads belong in NIR/canvas sidecars") and
the round-trip contract specifies a zero-filled recovered tensor. So
``linear_weight_matrix()`` hands back ``np.zeros(shape)`` and a *trained* network
used to deploy successfully, load the overlay, and fire nothing at all: correct
shape, correct synapse count, every value 0.0.

The software simulators hit the identical wall for the identical reason:
``POST /api/simulators/run`` recompiles the spec with ``compile_to_nir`` on every
run, ``_resolve_tensor`` zero-fills every weight matrix, and all three backends
then run a network in which nothing can reach threshold — completing in
milliseconds with an empty raster. :func:`apply_trained_weights` serves the deploy
IR; :func:`apply_trained_weights_to_graph` serves the simulators' NIR graph. They
share the matching rule below.

Akida solves the same problem with a bundle sidecar (``*.akida-bundle.zip``
carrying the converted model). PYNQ has no bundle format, so this module uses the
artifact that already exists: the trained ``.nir`` written by the **NIR Exporter**
canvas node, which loads ``best_model.pt`` and overlays the learned weights onto
the graph before ``nir.write``.

Scope
-----
Overlay-v2 stores a chain of up to ``MAX_LAYERS`` dense matrices, so this fills in
every population-to-population connection rather than a single one. Matching is
still done by *shape and position*, not by name — the CNL spec and the NIR graph
disagree about names, and reconciling them was never reliable. Both sides are put
into chain order and zipped, which also disambiguates two layers that happen to
share a shape (a ``256 → 256 → 256`` network), something shape alone cannot do.

Overlay-v1's version of this refused any network with more than one matrix, which
would now reject an MNIST-scale ``784 → 256 → 10`` chain that the planner accepts.
"""

from __future__ import annotations

import io
from dataclasses import dataclass
from typing import TYPE_CHECKING, Any

import numpy as np

from neurocnl.lif_semantics import DEFAULT_LIF_DT_SECONDS

if TYPE_CHECKING:
    from neurocnl.ir.types import NetworkIR

# NIR primitives that carry a 2-D weight matrix. `Linear` is weights only,
# `Affine` adds a bias — the overlay has no bias register, so the bias is dropped
# either way and both are treated the same here.
_WEIGHTED_PRIMITIVES: tuple[str, ...] = ("Linear", "Affine")
_NEURON_PRIMITIVES: tuple[str, ...] = ("LIF", "CubaLIF", "IF", "LI")
# What the training codegen's nir.LIF branch falls back to for a zero tau:
# beta = 0.95 at dt = 1e-4, i.e. tau = dt/(1 - beta). Used only to recover a
# trained file that was written before the exporter recorded real parameters.
_TRAINING_FALLBACK_TAU_SECONDS = DEFAULT_LIF_DT_SECONDS / (1.0 - 0.95)
_NEURON_PARAMETERS: tuple[str, ...] = (
    "tau",
    "tau_mem",
    "tau_syn",
    "v_threshold",
    "v_leak",
    "r",
    "w_in",
)


class TrainedWeightError(Exception):
    """A trained NIR graph could not be applied to this network."""


@dataclass(frozen=True)
class TrainedWeightResult:
    """Outcome of an overlay attempt, for reporting back to the caller.

    ``applied`` is the load-bearing field: a false value means the deploy will
    carry zeros, which the UI has to say out loud rather than presenting the
    deploy as a hardware result.
    """

    applied: bool
    source_node: str | None
    #: Shape of the FIRST layer only — the one ``source_node`` names — because
    #: the Deploy badge shows a single matrix. ``nonzero`` counts *every* layer,
    #: so ``nonzero / prod(shape)`` is meaningless on a multi-layer network.
    #: Use :attr:`layers` for anything per-layer, such as sparsity.
    shape: tuple[int, ...] | None
    nonzero: int
    detail: str
    #: One entry per weighted layer, in chain order:
    #: ``{"name": str, "shape": [rows, cols], "nonzero": int}``. Defaults to
    #: empty so producers that predate it keep working unchanged.
    layers: tuple[dict[str, Any], ...] = ()

    def to_dict(self) -> dict[str, Any]:
        return {
            "applied": self.applied,
            "source_node": self.source_node,
            "shape": list(self.shape) if self.shape is not None else None,
            "nonzero": self.nonzero,
            "detail": self.detail,
            "layers": [dict(layer) for layer in self.layers],
        }


def _weighted_nodes(graph: Any) -> list[tuple[str, np.ndarray]]:
    """Every ``(name, weight_matrix)`` in a NIR graph, 2-D matrices only.

    Returned in the graph's own execution order when its edges describe one, so
    that two same-shaped layers can be told apart by position. Falls back to
    node-dict order, which is what a single-matrix graph always had.
    """
    found: list[tuple[str, np.ndarray]] = []
    for name, node in getattr(graph, "nodes", {}).items():
        if type(node).__name__ not in _WEIGHTED_PRIMITIVES:
            continue
        weight = getattr(node, "weight", None)
        if weight is None:
            continue
        array = np.asarray(weight, dtype=float)
        if array.ndim != 2:
            continue
        found.append((str(name), array))
    return _in_graph_order(graph, found)


def _neuron_nodes(graph: Any) -> list[tuple[str, Any]]:
    """Every LIF-family ``(name, node)`` in a NIR graph, in execution order.

    Ordered the same way as :func:`_weighted_nodes` so the two overlays agree on
    what "layer 2" means.
    """
    found: list[tuple[str, Any]] = []
    for name, node in getattr(graph, "nodes", {}).items():
        if type(node).__name__ in _NEURON_PRIMITIVES:
            found.append((str(name), node))
    # _in_graph_order only reads item[0], so the node payload rides along.
    return _in_graph_order(graph, found)  # type: ignore[arg-type]


def _is_shape_only(node: Any) -> bool:
    """True when a neuron's parameters are placeholders rather than values.

    The test is the *time constant*, not each field in turn. ``v_leak = 0`` and
    ``v_threshold = 0`` are values a user could legitimately mean, so judging
    field by field would overwrite real settings; a time constant of zero is
    never meaningful — it describes a membrane that cannot integrate at all —
    and ``compile_to_nir`` zero-fills a shape-only node's parameters together.
    So a zero tau identifies the whole population as unset.
    """
    for field in ("tau", "tau_mem"):
        value = getattr(node, field, None)
        if value is None:
            continue
        array = np.asarray(value, dtype=float)
        if array.size and np.all(array == 0.0):
            return True
    return False


def _fill_from_training_fallback(node: Any) -> bool:
    """Reconstruct a blank neuron from the constants training itself fell back to.

    When ``compile_to_nir`` hands the training codegen a zero time constant, its
    ``nir.LIF`` branch uses ``beta = 0.95`` and applies no threshold rescale
    (``w_scale`` collapses to 1.0). So a network exported from that path was
    genuinely fitted at ``beta = 0.95``, ``threshold = 1.0`` — inverting those
    gives ``tau = dt/(1 - 0.95)``, which describes the trained model exactly.

    This is a recovery path for artifacts already on disk. Exports written after
    the NIR Exporter fix carry their real parameters and never reach here.
    """
    tau = getattr(node, "tau", None)
    if tau is None:
        return False
    size = np.asarray(tau).size or 1
    dtype = np.asarray(tau).dtype
    node.tau = np.full(size, _TRAINING_FALLBACK_TAU_SECONDS, dtype=dtype)
    if getattr(node, "v_threshold", None) is not None:
        node.v_threshold = np.full(size, 1.0, dtype=np.asarray(node.v_threshold).dtype)
    if getattr(node, "r", None) is not None:
        node.r = np.full(size, 1.0, dtype=np.asarray(node.r).dtype)
    return True


def _overlay_neuron_parameters(compiled: Any, trained: Any) -> tuple[int, int]:
    """Copy tau / threshold / resistance / leak from *trained* onto *compiled*.

    Weights alone are not enough to run a network. A CNL spec records a neuron's
    parameters as a *shape* rather than values (``with time constant shape
    (256,)``), so ``compile_to_nir`` zero-fills them: the compiled graph reaches
    the simulators with ``tau = 0``, ``v_threshold = 0`` and ``r = 0``. The
    trained ``.nir`` is the only artifact that carries the real numbers, so it
    has to supply them alongside the weight matrices.

    Matched by position among LIF-family nodes, for the same reason the weight
    overlay is: the compiled names come from the CNL spec and the trained names
    from the exporter. Copies only where the arrays already agree in shape, and
    only into a population that is *entirely* unset — see :func:`_is_shape_only`.
    A neuron the user actually configured is never overwritten.

    Returns ``(copied, reconstructed)`` population counts — the two cases read
    very differently to a user, so the caller reports them separately.
    """
    targets = _neuron_nodes(compiled)
    sources = _neuron_nodes(trained)
    if not targets or len(targets) != len(sources):
        # A count mismatch is not fatal here: the weight overlay already
        # rejected the graphs that are genuinely out of step, and a network
        # whose neuron parameters are fine does not need this pass at all.
        return 0, 0

    filled = 0
    rebuilt = 0
    for (target_name, target), (_, source) in zip(targets, sources, strict=True):
        if not _is_shape_only(target):
            continue
        if _is_shape_only(source):
            # The trained file is blank too — it was written by an exporter that
            # copied weight matrices onto the same shape-only compiled graph. The
            # network still trained, and the codegen's own fallback says exactly
            # how: a zero tau there yields beta = 0.95 with no threshold rescale.
            # Reconstructing from that constant reproduces the model that was
            # actually fitted, which is strictly better than refusing to run an
            # artifact that is merely missing its provenance.
            rebuilt += 1 if _fill_from_training_fallback(compiled.nodes[target_name]) else 0
            continue
        touched = False
        for field in _NEURON_PARAMETERS:
            want = getattr(source, field, None)
            have = getattr(target, field, None)
            if want is None or have is None:
                continue
            want_arr = np.asarray(want, dtype=float)
            have_arr = np.asarray(have, dtype=float)
            if want_arr.shape != have_arr.shape:
                continue
            setattr(compiled.nodes[target_name], field, want_arr.astype(have_arr.dtype, copy=True))
            touched = True
        source_dt = (getattr(source, "metadata", None) or {}).get("dt")
        if source_dt is not None:
            metadata = getattr(compiled.nodes[target_name], "metadata", None)
            if isinstance(metadata, dict):
                metadata.setdefault("dt", source_dt)
        filled += 1 if touched else 0
    return filled, rebuilt


def _in_graph_order(
    graph: Any, weighted: list[tuple[str, np.ndarray]]
) -> list[tuple[str, np.ndarray]]:
    """Sort *weighted* by how far each node is from the graph's input.

    A NIR graph's ``nodes`` is a plain dict, so its order is however the exporter
    happened to write it — fine for one matrix, not fine for a chain. Walking the
    edges gives the real order. Anything unreachable keeps its dict position at
    the end rather than being dropped, because the shape check downstream is the
    thing that should reject a graph, not this ordering step.
    """
    if len(weighted) < 2:
        return weighted

    edges = getattr(graph, "edges", None)
    if not edges:
        return weighted

    successors: dict[str, list[str]] = {}
    targets: set[str] = set()
    for edge in edges:
        try:
            source, target = str(edge[0]), str(edge[1])
        except (TypeError, IndexError):
            return weighted
        successors.setdefault(source, []).append(target)
        targets.add(target)

    roots = [name for name in successors if name not in targets]
    depth: dict[str, int] = {}
    queue: list[tuple[str, int]] = [(root, 0) for root in roots]
    while queue:
        name, distance = queue.pop(0)
        if name in depth and depth[name] <= distance:
            continue
        depth[name] = distance
        for successor in successors.get(name, ()):
            queue.append((successor, distance + 1))

    fallback = len(weighted)
    return sorted(
        weighted,
        key=lambda item: (depth.get(item[0], fallback), weighted.index(item)),
    )


def load_trained_nir_graph(nir_bytes: bytes) -> Any:
    """Read a NIR graph from raw ``.nir`` (HDF5) bytes.

    ``nir.read`` wants a path or file-like object; a BytesIO keeps this off the
    filesystem, since the graph arrives over HTTP from the frontend.

    A graph whose neuron parameters were written once per layer instead of once
    per neuron fails ``nir.read``'s type check, so that one case is repaired and
    retried — see :func:`neurocnl.export.nir_shapes.broadcast_neuron_parameters`.
    Everything else still raises, because a genuinely corrupt upload must not be
    papered over.
    """
    import nir

    try:
        return nir.read(io.BytesIO(nir_bytes))
    except Exception as exc:  # noqa: BLE001 - any h5py/nir failure is one bad upload
        if "type mismatch" not in str(exc):
            raise TrainedWeightError(
                f"The trained NIR file could not be read as a NIR graph: {exc}"
            ) from exc
        from neurocnl.export.nir_shapes import broadcast_neuron_parameters

        try:
            graph = nir.read(io.BytesIO(nir_bytes), type_check=False)
            return broadcast_neuron_parameters(graph)
        except Exception as repair_exc:  # noqa: BLE001
            raise TrainedWeightError(
                f"The trained NIR file could not be read as a NIR graph: {repair_exc}"
            ) from repair_exc


def _layer_connections(ir: NetworkIR) -> list[Any]:
    """The IR's population-to-population connections, in chain order.

    Port projections are DMA-streamed rather than stored, and the exporter drops
    them, so they must not be counted here either.
    """
    from neurocnl.planner import _is_port_population

    real_connections = [
        conn
        for conn in ir.connections
        if not (
            _is_port_population(ir.populations.get(conn.source))
            or _is_port_population(ir.populations.get(conn.target))
        )
    ]
    if len(real_connections) < 2:
        return real_connections

    by_source = {conn.source: conn for conn in real_connections}
    targets = {conn.target for conn in real_connections}
    starts = [conn.source for conn in real_connections if conn.source not in targets]
    if len(starts) != 1:
        # A branch or a merge. The planner rejects it too; leaving the order
        # alone lets the shape check below report against the network the user
        # actually drew rather than failing here with a topology message they
        # will see twice.
        return real_connections

    ordered: list[Any] = []
    node: str | None = starts[0]
    while node is not None and node in by_source:
        connection = by_source[node]
        ordered.append(connection)
        node = connection.target
    return ordered if len(ordered) == len(real_connections) else real_connections


def _expected_shape(ir: NetworkIR, connection: Any) -> tuple[int, int]:
    pre = ir.populations.get(connection.source)
    post = ir.populations.get(connection.target)
    return (
        int(getattr(post, "size", 0) or 0),
        int(getattr(pre, "size", 0) or 0),
    )


def graph_is_all_zero(graph: Any) -> bool:
    """True when the graph has weight matrices and every one of them is zero.

    A graph with no weighted node at all is not "all zero" — there is nothing to
    be zero — so the caller does not warn about it.
    """
    weighted = _weighted_nodes(graph)
    return bool(weighted) and not any(np.any(matrix) for _, matrix in weighted)


def apply_trained_weights_to_graph(compiled: Any, trained: Any) -> TrainedWeightResult:
    """Write *trained*'s weight matrices onto *compiled*'s weighted nodes.

    The NIR-graph sibling of :func:`apply_trained_weights`, for the simulator run
    path. Mutates ``compiled`` in place and returns what happened; the matching
    rule is the same one the deploy path uses — both sides are put into chain
    order and zipped, so **position, not name**, identifies a layer. That matters
    because the compiled graph's names come from the CNL spec and the trained
    file's come from the exporter, and reconciling them was never reliable.

    Raises :class:`TrainedWeightError` for a mismatch the user can act on. A
    compiled graph with no weighted node is not an error: there is nothing to
    fill in.
    """
    targets = _weighted_nodes(compiled)
    if not targets:
        return TrainedWeightResult(
            applied=False,
            source_node=None,
            shape=None,
            nonzero=0,
            detail=("This network has no weight matrix, so there are no trained weights to load."),
        )

    candidates = _weighted_nodes(trained)
    if not candidates:
        raise TrainedWeightError(
            "The trained NIR file contains no Linear or Affine node, so it holds "
            "no weight matrix. Check that the NIR Exporter node ran after "
            "training finished."
        )

    if len(candidates) != len(targets):
        needed = " → ".join(f"{arr.shape[0]}×{arr.shape[1]}" for _, arr in targets)
        shapes = ", ".join(f"{name} {arr.shape}" for name, arr in candidates)
        raise TrainedWeightError(
            f"The trained NIR file holds {len(candidates)} weight "
            f"{'matrix' if len(candidates) == 1 else 'matrices'} but this network "
            f"has {len(targets)} layer{'' if len(targets) == 1 else 's'}. Running "
            f"it needs {needed}; the file has: {shapes}. The trained model and the "
            f"network on the canvas are out of step — re-run training after your "
            f"last edit."
        )

    mismatched = [
        f"layer {index + 1} ({target_name}) needs "
        f"{want.shape[0]}×{want.shape[1]} but {name} is {arr.shape[0]}×{arr.shape[1]}"
        for index, ((target_name, want), (name, arr)) in enumerate(
            zip(targets, candidates, strict=True)
        )
        if arr.shape != want.shape
    ]
    if mismatched:
        raise TrainedWeightError(
            "The trained NIR file does not match this network: "
            + "; ".join(mismatched)
            + ". The trained model and the network on the canvas are probably out "
            "of step — re-run training after your last edit."
        )

    applied_names: list[str] = []
    layers: list[dict[str, Any]] = []
    total_nonzero = 0
    for (target_name, _), (name, matrix) in zip(targets, candidates, strict=True):
        compiled.nodes[target_name].weight = matrix.astype(
            np.asarray(compiled.nodes[target_name].weight).dtype, copy=True
        )
        applied_names.append(name)
        layer_nonzero = int(np.count_nonzero(matrix))
        # The trained-file name, matching source_node and applied_names, so a
        # per-layer row can be read against the detail line without a lookup.
        layers.append(
            {
                "name": name,
                "shape": [int(dim) for dim in matrix.shape],
                "nonzero": layer_nonzero,
            }
        )
        total_nonzero += layer_nonzero

    neurons_filled, neurons_rebuilt = _overlay_neuron_parameters(compiled, trained)

    first_name, first_matrix = candidates[0]
    if total_nonzero:
        detail = (
            f"Loaded trained weights from {', '.join(applied_names)} "
            f"({len(applied_names)} layer"
            f"{'' if len(applied_names) == 1 else 's'}, "
            f"{total_nonzero} non-zero)."
        )
        if neurons_filled:
            detail += (
                f" Also took time constants and firing thresholds for "
                f"{neurons_filled} population"
                f"{'' if neurons_filled == 1 else 's'} from the same file, "
                f"since a CNL spec records those as a shape rather than values."
            )
        if neurons_rebuilt:
            detail += (
                f" {neurons_rebuilt} population"
                f"{'' if neurons_rebuilt == 1 else 's'} carried no time constant "
                f"in the trained file either, so the values training itself used "
                f"were reconstructed. Re-run training to record the real ones."
            )
    else:
        detail = (
            f"{', '.join(applied_names)} match this network but every weight is "
            f"zero — the model was probably exported before training ran, so "
            f"nothing will fire."
        )
    return TrainedWeightResult(
        applied=True,
        source_node=first_name,
        shape=tuple(int(dim) for dim in first_matrix.shape),
        nonzero=total_nonzero,
        detail=detail,
        layers=tuple(layers),
    )


def apply_trained_weights(ir: NetworkIR, graph: Any) -> TrainedWeightResult:
    """Write the trained weight matrices onto the IR's dense connections.

    Mutates ``ir`` in place and returns what happened. Raises
    :class:`TrainedWeightError` only for a mismatch the user can act on — a graph
    with no weighted node, or one whose matrices are the wrong shapes for the
    network being deployed. A network with no dense connection at all is *not* an
    error: there is simply nothing to fill in.

    Both sides are put into chain order and zipped. Position, not name, is what
    identifies a layer, and it is also the only thing that can separate two
    layers of identical shape.
    """
    connections = _layer_connections(ir)
    if not connections:
        return TrainedWeightResult(
            applied=False,
            source_node=None,
            shape=None,
            nonzero=0,
            detail=(
                "This network has no weight matrix between two populations, so "
                "there are no trained weights to load."
            ),
        )

    candidates = _weighted_nodes(graph)
    if not candidates:
        raise TrainedWeightError(
            "The trained NIR file contains no Linear or Affine node, so it holds "
            "no weight matrix. Check that the NIR Exporter node ran after "
            "training finished."
        )

    expected = [_expected_shape(ir, conn) for conn in connections]
    if len(candidates) != len(connections):
        needed = " → ".join(f"{rows}×{cols}" for rows, cols in expected)
        shapes = ", ".join(f"{name} {arr.shape}" for name, arr in candidates)
        raise TrainedWeightError(
            f"The trained NIR file holds {len(candidates)} weight "
            f"{'matrix' if len(candidates) == 1 else 'matrices'} but this network "
            f"has {len(connections)} layer"
            f"{'' if len(connections) == 1 else 's'}. Deploying it needs {needed}; "
            f"the file has: {shapes}. The trained model and the network on the "
            f"canvas are out of step — re-run training after your last edit."
        )

    mismatched = [
        f"layer {index + 1} ({conn.source} → {conn.target}) needs "
        f"{want[0]}×{want[1]} but {name} is {arr.shape[0]}×{arr.shape[1]}"
        for index, (conn, want, (name, arr)) in enumerate(
            zip(connections, expected, candidates, strict=True)
        )
        if arr.shape != want
    ]
    if mismatched:
        raise TrainedWeightError(
            "The trained NIR file does not match this network: "
            + "; ".join(mismatched)
            + ". The trained model and the network on the canvas are probably out "
            "of step — re-run training after your last edit."
        )

    applied_names: list[str] = []
    layers: list[dict[str, Any]] = []
    total_nonzero = 0
    for connection, (name, matrix) in zip(connections, candidates, strict=True):
        connection.weight = matrix.copy()
        applied_names.append(name)
        layer_nonzero = int(np.count_nonzero(matrix))
        layers.append(
            {
                "name": name,
                "shape": [int(dim) for dim in matrix.shape],
                "nonzero": layer_nonzero,
            }
        )
        total_nonzero += layer_nonzero

    # The result reports one source node and one shape because the badge in the
    # Deploy step names them; for a chain, the first layer is the one users
    # recognise as "their" Linear. The detail line carries the whole chain.
    first_name, first_matrix = candidates[0]
    if total_nonzero:
        detail = (
            f"Loaded trained weights from {', '.join(applied_names)} "
            f"({len(applied_names)} layer"
            f"{'' if len(applied_names) == 1 else 's'}, "
            f"{total_nonzero} non-zero)."
        )
    else:
        detail = (
            f"{', '.join(applied_names)} match this network but every weight is "
            f"zero — the model was probably exported before training ran."
        )
    return TrainedWeightResult(
        applied=True,
        source_node=first_name,
        shape=tuple(int(dim) for dim in first_matrix.shape),
        nonzero=total_nonzero,
        detail=detail,
        layers=tuple(layers),
    )
