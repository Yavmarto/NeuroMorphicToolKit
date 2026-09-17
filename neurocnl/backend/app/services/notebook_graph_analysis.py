"""Target-aware graph flattening, ordering, naming, and width validation for NIR graphs."""

from __future__ import annotations

import math
import re
from pathlib import Path

import nir
import numpy as np

from backend.app.schemas.pipeline_dag import _LOADER_TYPES, PipelinePhasesPayload
from neurocnl.lif_semantics import resolve_dt
from neurocnl.runtime.cnl_flatten import flatten_cnl_ops
from neurocnl.runtime.nir_support import (
    SupportClassification,
    classify_nir_graph,
    get_supported_node_types,
    list_supported_backends,
)
from neurocnl.training.dataset_loader import pt_feature_width


class GraphWidthMismatchError(Exception):
    """A dataset/network feature-width disagreement found while validating a graph.

    Carries the exact message the router turns into an HTTP 422 detail, so this
    module never has to import FastAPI to report a validation failure.
    """

    def __init__(self, detail: str) -> None:
        super().__init__(detail)
        self.detail = detail


# Targets that lack native cnl.* support but are safe to flatten for — this
# excludes lava/lava_sim/sc_neurocore_sim/sc_neurocore_fpga, since flattening
# cnl.RSynaptic/Synaptic to nir.CubaLIF would turn lava's silent no-op today
# into a hard AttributeError crash (CubaLIF has no .tau — see nir_support.py's
# "lava"/"brian2"/"pynn" comments), an untested regression outside this scope.
CNL_FLATTEN_TARGETS: frozenset[str] = frozenset(
    {"brian2", "sinabs", "rockpool", "pynn", "nengo", "akida"}
)


def graph_needs_cnl_flatten(graph: nir.NIRGraph, target: str) -> bool:
    """True if `graph` has a cnl.* node the target's support table doesn't mark exact.

    Data-driven: reads get_supported_node_types(target) per node type rather
    than assuming a fixed set of cnl.* types always needs flattening.
    """
    if target not in CNL_FLATTEN_TARGETS:
        return False
    support_table = get_supported_node_types(target)
    return any(
        hasattr(node, "CNL_NIR_TYPE")
        and support_table.get(type(node).__name__, "unsupported") != "exact"
        for node in graph.nodes.values()
    )


def flatten_and_classify(
    graph: nir.NIRGraph, target: str
) -> tuple[nir.NIRGraph, SupportClassification | None, bool]:
    """Flatten cnl.* nodes if target's table needs it, then classify the final graph.

    Returns (graph_to_use_for_codegen, classification_or_None, flattened_bool).
    Both _build_v2_notebook (for the in-notebook warning cell) and
    generate_notebook_v2 (for the API response) must call this exact function
    rather than classify_nir_graph directly, so the two never silently
    disagree about a flattened graph's classification.
    """
    flattened = False
    flatten_diagnostics: list[str] = []
    if graph_needs_cnl_flatten(graph, target):
        graph, flatten_diagnostics = flatten_cnl_ops(graph)
        flattened = True

    if target not in list_supported_backends():
        return graph, None, flattened

    classification = classify_nir_graph(graph, target)
    if flatten_diagnostics:
        classification.diagnostics = classification.diagnostics + flatten_diagnostics
    return graph, classification, flattened


def node_order_key(name: str) -> tuple[int, int | str]:
    try:
        return (0, int(name))
    except ValueError:
        return (1, name)


def ordered_graph_node_names(graph: nir.NIRGraph) -> list[str]:
    """Return node names in graph topology order with numeric ids sorted naturally."""
    node_names = list(graph.nodes)
    indegree = dict.fromkeys(node_names, 0)
    outgoing: dict[str, list[str]] = {name: [] for name in node_names}
    for src, dst in graph.edges:
        if src not in indegree or dst not in indegree:
            continue
        outgoing[src].append(dst)
        indegree[dst] += 1

    ready = sorted((name for name, degree in indegree.items() if degree == 0), key=node_order_key)
    ordered: list[str] = []
    while ready:
        name = ready.pop(0)
        ordered.append(name)
        for dst in sorted(outgoing[name], key=node_order_key):
            indegree[dst] -= 1
            if indegree[dst] == 0:
                ready.append(dst)
        ready.sort(key=node_order_key)

    if len(ordered) != len(node_names):
        remaining = sorted((name for name in node_names if name not in ordered), key=node_order_key)
        ordered.extend(remaining)
    return ordered


def graph_weighted_node_names(graph: nir.NIRGraph) -> list[str]:
    """Names of graph nodes whose tensor values affect inference accuracy."""
    return [
        name
        for name in ordered_graph_node_names(graph)
        if isinstance(graph.nodes[name], nir.Linear | nir.Affine | nir.Conv2d)
    ]


def nir_node_slugs(graph: nir.NIRGraph) -> list[str]:
    """Return slugified variable names for each NIR graph node.

    Matches the naming convention used by Brian2IO, LavaIO, and PyNNIO when
    generating code from a NIR graph — each converter slugifies node names the
    same way (lowercase, non-alphanumeric → underscore).
    """
    return [python_identifier(name) for name in graph.nodes]


def nir_pop_slugs(graph: nir.NIRGraph) -> list[str]:
    """Slugified names of neuron-population nodes (LIF, CubaLIF, IF)."""
    return [
        python_identifier(name)
        for name, node in graph.nodes.items()
        if isinstance(node, nir.LIF | nir.CubaLIF | nir.IF)
    ]


def nir_syn_slugs(graph: nir.NIRGraph) -> list[str]:
    """Slugified names of synapse/weight nodes (Linear, Affine)."""
    return [
        python_identifier(name)
        for name, node in graph.nodes.items()
        if isinstance(node, nir.Linear | nir.Affine)
    ]


def nir_first_process_slug(graph: nir.NIRGraph) -> str:
    """Slug of first non-Input/Output node — used as Lava run target."""
    for name, node in graph.nodes.items():
        if not isinstance(node, nir.Input | nir.Output):
            return python_identifier(name)
    slugs = nir_node_slugs(graph)
    return slugs[0] if slugs else "process"


def slugify(text: str) -> str:
    """Convert an arbitrary string to a safe directory name."""
    slug = text.lower().strip()
    slug = re.sub(r"[^a-z0-9]+", "-", slug)
    slug = slug.strip("-")
    return slug or "workspace"


def python_identifier(text: str) -> str:
    """Convert arbitrary node ids to valid Python identifiers."""
    slug = re.sub(r"[^a-z0-9_]+", "_", text.lower()).strip("_")
    if not slug:
        return "node"
    if slug[0].isdigit():
        return f"n_{slug}"
    return slug


def endpoint_shape_literal(io_type: object) -> tuple[int, ...] | None:
    """Return a flat endpoint shape tuple when available."""
    try:
        raw = next(iter(io_type.values())) if isinstance(io_type, dict) else io_type
        return tuple(int(v) for v in np.asarray(raw).flatten())
    except Exception:
        return None


def declared_endpoint_width(node: object) -> int | None:
    """Flat neuron count declared on a ``nir.Input``/``nir.Output`` port."""
    io_type = getattr(node, "input_type", None)
    if io_type is None:
        io_type = getattr(node, "output_type", None)
    shape = endpoint_shape_literal(io_type)
    if not shape:
        return None
    return math.prod(shape)


def weighted_node_in_out(node: object) -> tuple[int, int] | None:
    """``(in_features, out_features)`` for a 2-D weighted node, else None.

    Deliberately mirrors ``_generate_snntorch_code``'s ``nir.Linear`` branch,
    which reads ``out_f, in_f = np.asarray(node.weight).shape`` — so this sees
    exactly the widths the emitted ``nn.Linear`` will enforce at runtime.
    """
    weight = getattr(node, "weight", None)
    if weight is None:
        return None
    try:
        shape = np.asarray(weight).shape
    except Exception:
        return None
    if len(shape) != 2:
        return None
    return int(shape[1]), int(shape[0])


# Node types whose output width equals their input width, because they map to
# elementwise operations that take no size argument. Anything absent from this
# tuple — Conv1d/Conv2d/SumPool2d/AvgPool2d/Flatten, or any future node — ends
# width tracking rather than being assumed transparent: a spatial layer changes
# the flat width in ways this diagnostic deliberately does not model.
WIDTH_PRESERVING_NIR_NODES: tuple[type, ...] = (
    nir.Input,
    nir.LIF,
    nir.CubaLIF,
    nir.IF,
    nir.I,
    nir.LI,
    nir.Threshold,
    nir.Delay,
    nir.Scale,
    nir.Output,
)


def propagate_graph_widths(
    graph: nir.NIRGraph, seed_widths: dict[str, int]
) -> list[tuple[str, int, int]]:
    """Walk the graph forward from its input ports, checking every weighted node.

    ``seed_widths`` maps input-port name to the width that actually arrives
    there. Returns one ``(node_name, arriving_width, expected_width)`` tuple per
    2-D weighted node whose ``in_features`` disagrees with what reaches it.

    Width only survives a hop through ``WIDTH_PRESERVING_NIR_NODES``; at any
    other node it becomes unknown and that branch stops being checked. Neuron
    nodes are in that set because ``snn.Leaky`` is elementwise and takes no size
    argument — precisely why an upstream width mismatch stays invisible until the
    first ``nn.Linear``. Cycles are traversed once and then dropped; this is a
    diagnostic, not a solver.
    """
    successors: dict[str, list[str]] = {name: [] for name in graph.nodes}
    for source, target in graph.edges:
        if source in successors:
            successors[source].append(target)

    conflicts: list[tuple[str, int, int]] = []
    widths: dict[str, int] = dict(seed_widths)
    queue = list(seed_widths)
    visited: set[str] = set()

    while queue:
        name = queue.pop(0)
        if name in visited:
            continue
        visited.add(name)
        arriving = widths.get(name)
        node = graph.nodes.get(name)
        if node is None or arriving is None:
            continue

        in_out = weighted_node_in_out(node)
        if in_out is not None:
            expected_in, out_features = in_out
            if arriving != expected_in:
                conflicts.append((name, arriving, expected_in))
                # Stop propagating past a conflict — every downstream width
                # would be derived from a number we already know is wrong.
                continue
            outgoing_width = out_features
        elif isinstance(node, WIDTH_PRESERVING_NIR_NODES):
            outgoing_width = arriving
        else:
            # Spatial or unmodelled node — the flat width past here is unknown,
            # so stop rather than guess. Keeps CNN graphs (Conv2d → SumPool2d →
            # Flatten → Linear) from raising a bogus conflict.
            continue

        for target in successors.get(name, []):
            widths.setdefault(target, outgoing_width)
            queue.append(target)

    return conflicts


def pt_dataset_widths(pipeline_phases: PipelinePhasesPayload) -> dict[str, tuple[str, int]]:
    """Feature width of every readable ``.pt`` loader, keyed by node id.

    Skips anything whose width cannot be established without guessing —
    non-``pt`` formats, tonic auto-download, client-scope paths the backend
    cannot see, missing files, unrecognised layouts. A guard that cannot read
    the data must never block a run, so every one of those is a silent skip.
    """
    widths: dict[str, tuple[str, int]] = {}
    for phase in (pipeline_phases.train, pipeline_phases.eval):
        for node in phase.nodes:
            if node.type not in _LOADER_TYPES:
                continue
            if node.parameters.get("format") != "pt":
                continue
            raw_path = str(node.parameters.get("dataset_path", "")).strip()
            if not raw_path:
                continue
            path = Path(raw_path)
            if not path.is_file():
                continue
            width = pt_feature_width(path)
            if width is None:
                continue
            widths[node.id] = (path.name, width)
    return widths


def check_input_width_against_datasets(
    graph: nir.NIRGraph, pipeline_phases: PipelinePhasesPayload
) -> None:
    """Fail generation when the dataset's width cannot reach the weighted layers.

    A graph whose own layers disagree is already rejected upstream by NIR's
    ``NIRGraph.infer_types``. What nothing checked before this is the width
    *arriving from the dataset*: ``nir.Input`` emits no code at all, and the
    neuron layers are elementwise, so a 784-feature file wired to a 32-wide
    network runs until the first ``nn.Linear`` and dies as
    ``mat1 and mat2 shapes cannot be multiplied`` — a message naming neither the
    dataset nor the Input node.

    Reports the port-level disagreement first because that is what a user fixes
    on the canvas, then propagates the real arriving width so the specific layer
    that cannot accept it is named. Raises GraphWidthMismatchError; returns
    silently whenever the dataset width could not be established.
    """
    input_ports = {name: node for name, node in graph.nodes.items() if isinstance(node, nir.Input)}
    if not input_ports:
        return

    dataset_widths = pt_dataset_widths(pipeline_phases)
    # Only one input port can be attributed to a loader without guessing which
    # feeds which; with several, fall back to the declared widths alone.
    dataset_source: tuple[str, int] | None = None
    if len(input_ports) == 1 and dataset_widths:
        distinct = {width for _, width in dataset_widths.values()}
        if len(distinct) == 1:
            dataset_source = next(iter(dataset_widths.values()))

    port_name = next(iter(input_ports))
    declared = declared_endpoint_width(input_ports[port_name])

    # Mismatch 1: the dataset disagrees with the declared port width. Report it
    # before propagation, because it is the more actionable of the two and the
    # one a user can fix from the canvas.
    if dataset_source is not None and declared is not None:
        filename, data_width = dataset_source
        if data_width != declared:
            raise GraphWidthMismatchError(
                f"'{filename}' provides {data_width} features per sample, but the "
                f"network's input port '{port_name}' declares {declared}. "
                f"Set the Input node's Size to {data_width}, and resize the layers "
                f"after it to match — or choose a dataset with {declared} features "
                "per sample."
            )

    # Mismatch 2: whatever the real arriving width is, it must survive to every
    # weighted node. Seed from the data when we could read it, otherwise from
    # the declaration.
    seed = dataset_source[1] if dataset_source is not None else declared
    if seed is None:
        return
    conflicts = propagate_graph_widths(graph, {port_name: seed})
    if not conflicts:
        return

    node_name, arriving, expected = conflicts[0]
    origin = (
        f"'{dataset_source[0]}' provides {arriving} features per sample"
        if dataset_source is not None
        else f"input port '{port_name}' declares {arriving}"
    )
    raise GraphWidthMismatchError(
        f"{origin}, so {arriving} values reach '{node_name}', which is sized for "
        f"{expected}. Neuron layers pass their input width through unchanged, so "
        f"set '{node_name}' Cols to {arriving} (or resize the populations before "
        "it) so the widths line up."
    )


def scalar(arr: object, default: float) -> float:
    """Return the first scalar from a numpy array or fall back to default."""
    try:
        a = np.asarray(arr, dtype=float)
        return float(a.flat[0]) if a.size > 0 else default
    except Exception:
        return default


def implausible_lif_thresholds(graph: nir.NIRGraph, cutoff: float = 50.0) -> list[str]:
    """Read-only scan for ``nir.LIF`` nodes whose effective snnTorch
    threshold looks unreachable for typically-scaled inputs.

    Deliberately a separate function from ``_generate_snntorch_code``'s
    ``nir.LIF`` branch, so a change here can never move codegen output. The
    *formula* is no longer duplicated though: both sides now resolve the
    timestep through :func:`neurocnl.lif_semantics.resolve_dt`, so the default
    cannot drift apart between them. Returns one human-readable warning line
    per implausible node, empty when none are found.
    """
    warnings: list[str] = []
    for name, node in graph.nodes.items():
        if not isinstance(node, nir.LIF):
            continue
        lif_dt, _ = resolve_dt(node, graph)
        tau = scalar(getattr(node, "tau", None), 0.02)
        r = scalar(getattr(node, "r", None), 1.0)
        thr = scalar(getattr(node, "v_threshold", None), 1.0) or 1.0
        w_scale = r * lif_dt / tau if tau > 0 else 1.0
        thr_out = thr / w_scale if abs(w_scale - 1.0) > 1e-6 else thr
        if thr_out > cutoff:
            warnings.append(
                f"- `{name}`: effective threshold ≈{thr_out:.1f} (tau={tau}, dt={lif_dt}) "
                "may be unreachable for typically-scaled inputs. Declare a network "
                "timestep close to this neuron's time constant "
                "(`Define a network named ... with timestep <value>.`), or lower "
                "`firing threshold`."
            )
    return warnings
