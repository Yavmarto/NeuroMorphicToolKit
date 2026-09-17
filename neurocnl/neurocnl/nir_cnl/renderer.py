"""NIR-Native CNL renderer.

This module implements :class:`NIR_Renderer`, the natural-language
renderer that converts a :class:`nir.NIRGraph` into NIR-Native
Controlled Natural Language text.  The output is a series of English
NL_Sentences, one per network container, one per node, and one per
edge, terminated by periods.

Pipeline
--------
1. Emit a header NL_Sentence ``Define a network named <id>.`` for the
   graph itself (Requirement 1.7).  The identifier is taken from
   ``graph.name`` when present; otherwise the literal ``"graph"`` is
   used. When ``graph.metadata["dt"]`` is set (the compiler mirrors a
   declared network timestep there — see
   :mod:`neurocnl.nir_cnl.compiler`), the header instead reads
   ``Define a network named <id> with timestep <dt>.``, and any ``LIF``
   node whose own ``metadata["dt"]`` exactly equals that value has its
   per-node ``dt`` clause suppressed (it's just the inherited default,
   not an explicit override) to avoid duplicating the declaration.
2. For each ``(name, node)`` in ``graph.nodes`` (in dict iteration
   order — Requirement 3.2), dispatch on ``type(node).__name__``
   against :data:`~neurocnl.nir_cnl.grammar_tables.primitive_phrases`:

   * Supported Primitive — emit one node-declaration NL_Sentence
     ``Define a/an <noun phrase> named <name> with <param-clauses>.``
     followed by zero or more comment lines for unsupported metadata
     values.
   * Unsupported type — emit a single comment line
     ``# unsupported node type <T> for node <name>`` and continue
     (Requirement 3.6).

3. For each edge ``(src, target)`` in ``graph.edges`` (in topological
   order), emit either ``<src> connects to <target>.`` (Requirement
   3.1 / 3.2) or, when either endpoint references an unsupported node
   or one absent from ``graph.nodes``, the comment line
   ``# unsupported edge from <src> to <target>`` (Requirement 3.7).

4. Assemble the lines via ``"\n".join(lines) + "\n"`` and run the
   shared legacy-token validator on the result.  Any diagnostic raises
   :class:`~neurocnl.nir_cnl.errors.RenderError` with
   ``code="legacy_grammar_emission"`` and the renderer returns no
   partial output (Requirement 8.5).

Per-parameter emission strategy
-------------------------------
The renderer iterates
``parameter_phrases[primitive].items()`` so every constructor argument
the upstream ``nir.*`` class declares appears in the output
(Requirement 3.4).  Each :class:`ParamSpec.kind` has a fixed
emission strategy:

* ``"scalar"`` — single ``repr(float(v))`` literal.
* ``"int_scalar"`` — single ``int(v)`` literal.
* ``"int_tuple"`` — ``(d1, d2, ..., dN)`` for rank ≥ 2 and
  ``(N,)`` for rank 1 (Requirement 2.5).  For ``Input.input_type`` /
  ``Output.output_type`` the shape is extracted from the
  ``{port_name: shape_array}`` dict that the upstream ``nir`` library
  uses.
* ``"vector"`` — when the array's size is 1 (a length-1 array or a
  0-D scalar broadcast), the clause collapses to a single bare scalar
  ``<phrase> <value>`` for readability. Longer vectors remain shape-only
  except for ``Scale``, whose per-element factors are executable semantics.
* ``"tensor"`` — emits only ``<phrase> shape (...)``;
  exact tensor payloads stay in NIR/canvas data paths so the rendered
  CNL stays compact and readable.

Numeric values are always coerced through ``numpy.asarray(...)
.astype(np.float64)`` before formatting to ensure consistent
float64 precision (Requirement 5.5).  Each value formats via
``repr(float(v))`` so ``float(repr(v)) == v`` holds exactly under
IEEE 754.

Connectives between parameter clauses follow Requirement 1.4:

* zero clauses — no ``with`` block;
* one clause — ``with <c1>``;
* two clauses — ``with <c1> and <c2>``;
* three or more clauses — ``with <c1>, <c2>, ..., and <cN>``.

Article selection
-----------------
The English article (``a`` vs ``an``) is selected from the first
character of the canonical noun phrase (Requirement 1.2).  Phrases
beginning with a vowel letter (case-insensitive) take ``an``;
everything else — including digit-prefixed phrases such as
``1D convolution layer`` and ``2D average pooling layer`` — takes
``a`` (``Define a 2D convolution layer named ...`` reads naturally).

Metadata
--------
Each node's ``metadata`` dict is rendered in ascending lexicographic
order of keys (Requirement 10.1). Keys in ``COMPACT_METADATA_SKIP``
are silently omitted:

* ``str`` / ``int`` / finite ``float`` value — appended to the
  parameter clause list as
  ``annotated with metadata <key> equal to <value>``.  String values
  are wrapped in double quotes; integer and float values are
  unquoted.
* Anything else (``list``, ``dict``, ``None``, ``NaN``, ``±inf``) —
  emitted as a comment line on its own line immediately after the
  node sentence:
  ``# metadata <key> on <node_name> omitted: unsupported value type``
  (Requirement 10.5).
"""

from __future__ import annotations

import math
from collections import deque
from typing import Any

import nir
import numpy as np

from neurocnl.nir_cnl.errors import RenderError
from neurocnl.nir_cnl.grammar_tables import (
    COMPACT_METADATA_SKIP,
    ParamSpec,
    export_target_id_to_phrase,
    loss_function_id_to_phrase,
    optimizer_id_to_phrase,
    parameter_phrases,
    primitive_phrases,
    training_strategy_id_to_phrase,
)
from neurocnl.nir_cnl.pipeline_config import PipelineConfig
from neurocnl.nir_cnl.validator import scan_for_legacy_tokens

__all__ = ["NIR_Renderer"]


# ---------------------------------------------------------------------------
# Formatting helpers
# ---------------------------------------------------------------------------


def _format_scalar(v: Any) -> str:
    """Format *v* as a float64 scalar literal.

    Uses ``repr(float(v))`` so the resulting string round-trips exactly
    under IEEE 754 — ``float(repr(v)) == v`` for every finite float64
    value, which is required by Requirements 5.3–5.10 (bit-equal
    parameter values across the round-trip).
    """
    return repr(float(v))


def _format_compact_scalar(v: float) -> str:
    """Format *v* as an exact float literal for round-trip safety."""
    if not math.isfinite(v):
        return repr(v)
    s = repr(float(v))
    if "." not in s and "e" not in s:
        s += ".0"
    return s


def _format_int_tuple(t: tuple[int, ...] | list[int]) -> str:
    """Format an integer tuple as a parenthesised literal.

    Rank-1 tuples use the trailing-comma form ``(N,)`` — mirrors
    NumPy's 1-D shape convention as required by Requirement 2.5.
    Higher ranks render as ``(d1, d2, ..., dN)`` with comma-space
    separators.
    """
    items = [int(x) for x in t]
    if len(items) == 1:
        return f"({items[0]},)"
    return "(" + ", ".join(str(d) for d in items) + ")"


def _format_array_shape(arr: np.ndarray[Any, Any]) -> str:
    """Format a numpy array's shape as a parenthesised tuple literal."""
    arr = np.asarray(arr)
    return _format_int_tuple(arr.shape)


def _format_array_values(arr: np.ndarray[Any, Any]) -> str:
    """Format a numpy array as a flattened C-order values literal.

    Coerces to ``float64`` before formatting so every element uses the
    full IEEE 754 precision (Requirement 5.5).  Single-element arrays
    use the trailing-comma form ``(v,)`` to mirror the rank-1 shape
    convention.
    """
    arr = np.asarray(arr).astype(np.float64)
    flat = arr.flatten().tolist()
    if len(flat) == 1:
        return f"({_format_scalar(flat[0])},)"
    return "(" + ", ".join(_format_scalar(v) for v in flat) + ")"


def _extract_io_shape(io_type: Any) -> tuple[int, ...]:
    """Recover the shape tuple from an ``Input``/``Output`` port type.

    The upstream ``nir`` library stores ``Input.input_type`` /
    ``Output.output_type`` as ``{port_name: shape_array}``; older
    fixtures occasionally store the shape array directly.  This helper
    accepts both shapes and returns a flat tuple of ``int``.
    """
    if isinstance(io_type, dict):
        if not io_type:
            return ()
        arr = next(iter(io_type.values()))
    else:
        arr = io_type
    return tuple(int(v) for v in np.asarray(arr).flatten())


# ---------------------------------------------------------------------------
# Connective / article helpers
# ---------------------------------------------------------------------------


_VOWEL_LETTERS: frozenset[str] = frozenset("aeiouAEIOU")


def _article_for(noun_phrase: str) -> str:
    """Pick ``a`` or ``an`` for *noun_phrase* (Requirement 1.2).

    The decision uses only the first character of the noun phrase:

    * an alphabetic vowel (``a``, ``e``, ``i``, ``o``, ``u`` —
      case-insensitive) → ``an``;
    * anything else, including digit-prefixed phrases such as
      ``1D convolution layer`` and ``2D average pooling layer`` →
      ``a``.

    The digit-prefixed cases read naturally as ``a 2D convolution
    layer named ...``; treating them as consonants is an explicit
    requirement of the spec.
    """
    if not noun_phrase:
        return "a"
    first = noun_phrase[0]
    if first in _VOWEL_LETTERS:
        return "an"
    return "a"


def _join_clauses(clauses: list[str]) -> str:
    """Join parameter clauses with English connectives (Requirement 1.4).

    * ``[]`` → empty string (caller decides whether to emit ``with``);
    * ``[c]`` → ``c`` (just the clause);
    * ``[c1, c2]`` → ``c1 and c2``;
    * ``[c1, c2, ..., cN]`` (N ≥ 3) → ``c1, c2, ..., and cN`` —
      Oxford-style comma before ``and``.
    """
    if not clauses:
        return ""
    if len(clauses) == 1:
        return clauses[0]
    if len(clauses) == 2:
        return f"{clauses[0]} and {clauses[1]}"
    return ", ".join(clauses[:-1]) + ", and " + clauses[-1]


# ---------------------------------------------------------------------------
# Metadata helpers
# ---------------------------------------------------------------------------


def _is_supported_metadata_value(v: Any) -> bool:
    """Return ``True`` for ``str``, ``int``, or finite ``float`` values.

    ``bool`` is *not* treated as a supported metadata type because the
    grammar's metadata clause restricts values to the three primitive
    types ``str | int | float`` (Requirement 10).  ``NaN`` and
    ``±inf`` floats are excluded because they cannot be losslessly
    re-rendered as a numeric literal in NIR-Native CNL.
    """
    if isinstance(v, bool):
        return False
    if isinstance(v, str):
        return True
    if isinstance(v, int):
        return True
    if isinstance(v, float):
        return math.isfinite(v)
    return False


def _format_metadata_value(v: str | int | float) -> str:
    """Format a metadata value for emission inside an ``equal to`` clause.

    Strings are surrounded by double quotes with a small set of
    JSON-style escapes (``"``, ``\\``, ``\\n``, ``\\t``, ``\\r``)
    applied; integers render verbatim; floats render via
    :func:`_format_scalar` so float64 round-trip identity is
    preserved.
    """
    if isinstance(v, str):
        escaped = (
            v.replace("\\", "\\\\")
            .replace('"', '\\"')
            .replace("\n", "\\n")
            .replace("\t", "\\t")
            .replace("\r", "\\r")
        )
        return f'"{escaped}"'
    if isinstance(v, bool):  # pragma: no cover — filtered upstream
        return str(int(v))
    if isinstance(v, int):
        return str(v)
    return _format_scalar(v)


# ---------------------------------------------------------------------------
# Per-parameter clause emission
# ---------------------------------------------------------------------------


def _emit_param_clauses(
    primitive: str, arg_name: str, spec: ParamSpec, value: Any
) -> list[str]:
    """Emit one or two parameter clauses for a single ``nir.*`` argument.

    Returns the list of clause strings that should be appended to the
    node sentence's ``with`` block.  Most kinds emit a single clause;
    only ``"vector"`` (for small varied arrays) may emit two
    (``shape`` + ``values``) per Requirement 5.13.

    Parameters
    ----------
    primitive:
        Primitive class name (used by ``Input``/``Output`` for the
        port-type extraction quirk).
    arg_name:
        ``nir.*`` constructor argument name.
    spec:
        :class:`ParamSpec` describing the canonical phrase, kind, and
        rank.
    value:
        Raw value pulled from the ``nir`` node.  May be a numpy
        array, a Python scalar, a tuple, or — for
        ``Input``/``Output`` — a dict from port name to shape array.
    """
    phrase = spec.phrase
    kind = spec.kind

    # Input / Output ports store their shape in a ``{name: array}``
    # dict; the canonical phrase ``shape`` is rendered as a single
    # int_tuple clause.
    if primitive in ("Input", "Output") and arg_name in (
        "input_type",
        "output_type",
    ):
        shape = _extract_io_shape(value)
        return [f"{phrase} {_format_int_tuple(shape)}"]

    if kind == "scalar":
        return [f"{phrase} {_format_scalar(value)}"]

    if kind == "int_scalar":
        return [f"{phrase} {int(value)}"]

    if kind == "int_tuple":
        # The value may be a tuple/list, or a numpy array.  Coerce to
        # a plain Python int tuple for formatting.
        if isinstance(value, tuple | list):
            ints = tuple(int(x) for x in value)
        else:
            arr = np.asarray(value).flatten()
            ints = tuple(int(x) for x in arr)
        return [f"{phrase} {_format_int_tuple(ints)}"]

    if kind == "vector":
        arr = np.asarray(value).astype(np.float64)
        # Scalar broadcast: a 0-D scalar or a length-1 array collapses
        # to a single bare compact-scalar clause for readability.
        if arr.size == 1:
            return [f"{phrase} {_format_compact_scalar(arr.flatten()[0])}"]
        if primitive == "Scale":
            values = ", ".join(_format_scalar(item) for item in arr.flat)
            return [
                f"{phrase} shape {_format_array_shape(arr)}",
                f"{phrase} values ({values})",
            ]
        return [f"{phrase} shape {_format_array_shape(arr)}"]

    if kind == "tensor":
        arr = np.asarray(value).astype(np.float64)
        # ponytail: CNL only carries tensor shape; exact tensor payloads belong
        # in NIR/canvas sidecars if lossless import fidelity matters later.
        return [f"{phrase} shape {_format_array_shape(arr)}"]

    # Defensive fallback — every documented kind is handled above.
    raise RuntimeError(
        f"Internal error: unhandled ParamSpec.kind {kind!r} for {primitive}.{arg_name}"
    )


# ---------------------------------------------------------------------------
# Edge ordering helper
# ---------------------------------------------------------------------------


def _topological_edges(
    edges: list[tuple[str, str]], supported_nodes: set[str]
) -> list[tuple[str, str]]:
    """Sort edges so forward edges precede back-edges (recurrent connections).

    Uses Kahn's BFS on the subgraph induced by *supported_nodes*. Forward
    edges are emitted in topological order; back-edges (those that would
    create a cycle) are appended afterwards, preserving their relative order.
    """
    # Build adjacency for supported edges only
    supported_edges = [
        (e[0], e[1])
        for e in edges
        if e[0] in supported_nodes and e[1] in supported_nodes
    ]
    # In-degree count
    in_degree: dict[str, int] = dict.fromkeys(supported_nodes, 0)
    for s, t in supported_edges:
        if s != t:  # ignore self-loops for topological purposes
            in_degree[t] = in_degree.get(t, 0) + 1

    queue: deque[str] = deque(sorted(n for n, d in in_degree.items() if d == 0))
    topo_order: list[str] = []
    visited_nodes: set[str] = set()
    while queue:
        node = queue.popleft()
        if node in visited_nodes:
            continue
        visited_nodes.add(node)
        topo_order.append(node)
        for s, t in supported_edges:
            if s == node and t not in visited_nodes:
                in_degree[t] -= 1
                if in_degree[t] == 0:
                    queue.append(t)

    # Assign topological rank; nodes not in topo_order get rank = len(topo_order)
    rank: dict[str, int] = {n: i for i, n in enumerate(topo_order)}
    max_rank = len(topo_order)

    # Separate forward edges (src rank < tgt rank) from back-edges, then sort
    # forward edges by (source_rank, target_rank) so the list is in topological order.
    forward: list[tuple[str, str]] = []
    back: list[tuple[str, str]] = []
    for s, t in supported_edges:
        if rank.get(s, max_rank) < rank.get(t, max_rank):
            forward.append((s, t))
        else:
            back.append((s, t))

    forward.sort(key=lambda e: (rank.get(e[0], max_rank), rank.get(e[1], max_rank)))
    return forward + back


# ---------------------------------------------------------------------------
# Auto-summary and flow comment helpers
# ---------------------------------------------------------------------------


def _auto_summary(nodes: dict[str, Any], ordered_edges: list[tuple[str, str]]) -> str:
    """Generate a one-line plain-English summary comment body."""
    n_input = sum(1 for n in nodes.values() if type(n).__name__ == "Input")
    n_output = sum(1 for n in nodes.values() if type(n).__name__ == "Output")
    n_hidden = len(nodes) - n_input - n_output
    parts = []
    if n_input:
        parts.append(f"{n_input} input{'s' if n_input != 1 else ''}")
    if n_hidden:
        parts.append(f"{n_hidden} hidden node{'s' if n_hidden != 1 else ''}")
    if n_output:
        parts.append(f"{n_output} output{'s' if n_output != 1 else ''}")
    if not parts:
        return "Network summary unavailable."
    return "Network with " + ", ".join(parts) + "."


def _flow_comment(nodes: dict[str, Any], ordered_edges: list[tuple[str, str]]) -> str:
    """Build a compact ``flow: A → B → C (recurrent: X ↺ Y)`` comment body."""
    if not ordered_edges:
        return "flow: (no edges)"
    # Derive rank from first-appearance order in ordered_edges (which is already
    # topologically sorted by _topological_edges). This avoids depending on
    # nodes.keys() insertion order, which is alphabetical and not topological.
    node_rank: dict[str, int] = {}
    r = 0
    for s, t in ordered_edges:
        if s not in node_rank:
            node_rank[s] = r
            r += 1
        if t not in node_rank:
            node_rank[t] = r
            r += 1
    forward_edges = [
        (s, t)
        for s, t in ordered_edges
        if node_rank.get(s, 0) <= node_rank.get(t, 0) and s != t
    ]
    back_edges = [
        (s, t)
        for s, t in ordered_edges
        if node_rank.get(s, 0) > node_rank.get(t, 0) or s == t
    ]
    # Build a chain from forward edges without duplicating consecutive nodes
    chain: list[str] = []
    for s, t in forward_edges:
        if not chain or chain[-1] != s:
            chain.append(s)
        chain.append(t)
    if not chain:
        # Fallback: unique node names in edge order
        seen: set[str] = set()
        for s, t in ordered_edges:
            for n in (s, t):
                if n not in seen:
                    seen.add(n)
                    chain.append(n)
    result = "flow: " + " → ".join(chain)
    if back_edges:
        back_str = ", ".join(f"{s} ↺ {t}" for s, t in back_edges)
        result += f" (recurrent: {back_str})"
    return result


# ---------------------------------------------------------------------------
# NIR_Renderer
# ---------------------------------------------------------------------------


class NIR_Renderer:
    """Convert a :class:`nir.NIRGraph` into NIR-Native CNL text.

    Stateless — every call to :meth:`render` is independent.  See the
    module docstring for the emission contract.

    Examples
    --------
    >>> import nir, numpy as np
    >>> from neurocnl.nir_cnl.renderer import NIR_Renderer
    >>> graph = nir.NIRGraph(
    ...     nodes={
    ...         "in1": nir.Input(input_type={"input": np.array([1])}),
    ...         "out1": nir.Output(output_type={"output": np.array([1])}),
    ...     },
    ...     edges=[("in1", "out1")],
    ... )
    >>> text = NIR_Renderer().render(graph)
    >>> "in1 connects to out1." in text
    True
    """

    # ------------------------------------------------------------------
    # Public entry point
    # ------------------------------------------------------------------

    def render(self, graph: nir.NIRGraph) -> str:
        """Render *graph* as NIR-Native CNL text.

        Implements Requirements 1.1, 1.2, 1.4, 1.6, 1.7, 2.1, 3.1,
        3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 5.13, 8.5, and 10.1.

        Parameters
        ----------
        graph:
            The NIR graph to render.

        Returns
        -------
        str
            The rendered text.  Always ends with a single trailing
            newline.

        Raises
        ------
        RenderError
            If the assembled output contains a Structured_DSL_Token or
            a Biological_Grammar keyword (outside double-quoted
            metadata strings).  This is an internal-invariant
            violation — the renderer's emitters should never produce
            such tokens; a non-empty validator result indicates a bug.
        """
        # ── Header: network container declaration (Requirement 1.7) ───
        network_name = getattr(graph, "name", None) or "graph"
        network_dt = (getattr(graph, "metadata", None) or {}).get("dt")

        # ── Track which node names were rendered as supported nodes
        # so edge emission can correctly fall through to the comment
        # form when an endpoint is unsupported or missing
        # (Requirement 3.7).
        supported_node_names: set[str] = set()

        # ── Node sentences (Requirement 3.1, 3.2) ────────────────────
        node_lines: list[str] = []
        for name, node in graph.nodes.items():
            type_name = type(node).__name__
            if type_name not in primitive_phrases:
                # Unsupported primitive — comment line only
                # (Requirement 3.6).  Continue with the rest of the
                # graph; no exception.
                node_lines.append(
                    f"# unsupported node type {type_name} for node {name}"
                )
                continue

            supported_node_names.add(name)
            sentence, meta_comments = self._render_node_sentence(
                name, node, network_dt=network_dt
            )
            node_lines.append(sentence)
            node_lines.extend(meta_comments)

        # ── Topological edge ordering ─────────────────────────────────
        ordered_edges = _topological_edges(list(graph.edges), supported_node_names)

        # ── Edge sentences (Requirement 3.1, 3.7) ────────────────────
        edge_lines: list[str] = []
        for edge in graph.edges:
            src, target = edge[0], edge[1]
            if src not in supported_node_names or target not in supported_node_names:
                edge_lines.append(f"# unsupported edge from {src} to {target}")
                continue
            # Supported edges are already in ordered_edges; we emit them
            # in topological order below.

        # Emit ordered (supported) edges
        ordered_edge_lines: list[str] = []
        for src, target in ordered_edges:
            ordered_edge_lines.append(f"{src} connects to {target}.")

        # ── Assemble final output with section structure ──────────────
        lines: list[str] = []
        if network_dt is not None:
            lines.append(
                f"Define a network named {network_name} with timestep {_format_scalar(network_dt)}."
            )
        else:
            lines.append(f"Define a network named {network_name}.")
        lines.append(f"# {_auto_summary(graph.nodes, ordered_edges)}")
        lines.append(f"# {_flow_comment(graph.nodes, ordered_edges)}")
        lines.append("")
        lines.append("# Layers:")
        lines.extend(node_lines)
        lines.append("")
        lines.append("# Connections:")
        lines.extend(edge_lines)  # unsupported-edge comments first
        lines.extend(ordered_edge_lines)  # then topologically ordered edges

        text = "\n".join(lines) + "\n"

        # ── Post-emission legacy-token gate (Requirement 8.5) ─────────
        # The validator is the renderer's last line of defence: if any
        # emitter accidentally produced a Structured_DSL_Token or a
        # Biological_Grammar keyword outside a double-quoted metadata
        # string, raise RenderError and return no partial output.
        diagnostics = scan_for_legacy_tokens(text)
        if diagnostics:
            first = diagnostics[0]
            # Best-effort offending-token extraction: the validator
            # records the offending line in ``raw`` and the token form
            # in ``hint``; surface the most specific available value.
            offending = first.hint or first.raw or first.message
            raise RenderError(
                code="legacy_grammar_emission",
                offending_token=offending,
            )

        return text

    # ------------------------------------------------------------------
    # Pipeline (Train / Evaluate / Export) emission
    # ------------------------------------------------------------------

    def render_pipeline_config(self, cfg: PipelineConfig) -> str:
        """Render Train/Evaluate/Export sentences for *cfg*.

        Emits at most one sentence per group, only for fields that are
        non-``None`` (Train) / truthy (Evaluate's ``run_evaluation``,
        Export's two booleans). A ``cfg`` with every field ``None``
        renders to the empty string.

        Raises
        ------
        ValueError
            If any other Train field is set while ``cfg.epochs`` is
            ``None`` — every Train sentence requires the epoch-count
            anchor, so a caller must always populate ``epochs`` before
            rendering a Train-bearing config.
        RenderError
            If the assembled text trips the legacy-token gate
            (Requirement 8.5 parity with :meth:`render`).
        """
        train_fields_set = any(
            v is not None
            for v in (
                cfg.learning_rate,
                cfg.batch_size,
                cfg.optimizer,
                cfg.training_strategy,
                cfg.loss_function,
            )
        )
        if train_fields_set and cfg.epochs is None:
            raise ValueError(
                "PipelineConfig has a Train field set (learning_rate, "
                "batch_size, optimizer, training_strategy, or "
                "loss_function) but epochs is None — every Train "
                "sentence requires the epoch-count anchor."
            )

        lines: list[str] = []

        if cfg.epochs is not None:
            clauses: list[str] = []
            if cfg.learning_rate is not None:
                clauses.append(f"learning rate {_format_scalar(cfg.learning_rate)}")
            if cfg.batch_size is not None:
                clauses.append(f"batch size {cfg.batch_size}")
            if cfg.optimizer is not None:
                clauses.append(f"{optimizer_id_to_phrase[cfg.optimizer]} optimizer")
            if cfg.training_strategy is not None:
                clauses.append(
                    f"{training_strategy_id_to_phrase[cfg.training_strategy]} training strategy"
                )
            if cfg.loss_function is not None:
                clauses.append(f"{loss_function_id_to_phrase[cfg.loss_function]} loss")
            prefix = f"Train the network for {cfg.epochs} epochs"
            lines.append(
                f"{prefix} with {_join_clauses(clauses)}." if clauses else f"{prefix}."
            )

        if cfg.run_evaluation or cfg.eval_metrics:
            if cfg.eval_metrics:
                lines.append(
                    f"Evaluate the network with {_join_clauses(list(cfg.eval_metrics))} metrics."
                )
            else:
                lines.append("Evaluate the network.")

        export_targets: list[str] = []
        if cfg.export_nir:
            export_targets.append(export_target_id_to_phrase["export_nir"])
        if cfg.generate_py_download:
            export_targets.append(export_target_id_to_phrase["generate_py_download"])
        if export_targets:
            lines.append(
                f"Export the trained network to {_join_clauses(export_targets)}."
            )

        if not lines:
            return ""

        text = "\n".join(lines) + "\n"

        diagnostics = scan_for_legacy_tokens(text)
        if diagnostics:
            first = diagnostics[0]
            offending = first.hint or first.raw or first.message
            raise RenderError(
                code="legacy_grammar_emission",
                offending_token=offending,
            )

        return text

    # ------------------------------------------------------------------
    # Per-node emission
    # ------------------------------------------------------------------

    def _render_node_sentence(
        self,
        name: str,
        node: nir.NIRNode,
        *,
        network_dt: float | None = None,
    ) -> tuple[str, list[str]]:
        """Render one node-declaration NL_Sentence.

        Returns ``(sentence, metadata_comment_lines)``.  The caller
        emits the sentence first, then appends the comment lines (one
        per metadata key with an unsupported value type) on their own
        lines immediately after the sentence (Requirement 10.5).

        *network_dt* is the graph-level declared timestep (Requirement
        1.7's optional network-timestep clause), if any. A ``LIF``
        node's own ``metadata["dt"]`` is suppressed here only when it
        exactly equals *network_dt* — i.e. it's just the value the
        compiler inherited from the network declaration, not an
        explicit per-node override — so it isn't duplicated as its own
        clause on top of the network-level sentence. An explicit
        override that differs from *network_dt* still renders normally.
        """
        type_name = type(node).__name__
        noun_phrase = primitive_phrases[type_name]
        article = _article_for(noun_phrase)

        clauses: list[str] = []

        # Iterate the parameter table for this primitive in declared
        # order so every constructor argument the upstream ``nir.*``
        # class declares appears exactly once in the output
        # (Requirement 3.4).
        for arg_name, spec in parameter_phrases[type_name].items():
            value = getattr(node, arg_name)
            clauses.extend(_emit_param_clauses(type_name, arg_name, spec, value))

        # Metadata clauses are appended in ascending lexicographic key
        # order (Requirement 10.1). Keys in COMPACT_METADATA_SKIP are
        # silently omitted. Supported values (str, int, finite float)
        # become ``annotated with metadata <k> equal to <v>`` clauses;
        # unsupported values become comment lines.
        meta_comments: list[str] = []
        metadata: dict[str, Any] = getattr(node, "metadata", None) or {}
        if type_name == "Flatten":
            input_shape = _extract_io_shape(getattr(node, "input_type", None))
            clauses.append(
                "annotated with metadata nmtk_flatten_input_shape equal to "
                + _format_metadata_value(
                    ",".join(str(dimension) for dimension in input_shape)
                )
            )
        for key in sorted(k for k in metadata.keys() if k not in COMPACT_METADATA_SKIP):
            value = metadata[key]
            if (
                type_name == "LIF"
                and key == "dt"
                and network_dt is not None
                and value == network_dt
            ):
                # Inherited from the network-level timestep declaration
                # — already implied by the header sentence, so don't
                # duplicate it as a per-node clause.
                continue
            if _is_supported_metadata_value(value):
                clauses.append(
                    f"annotated with metadata {key} equal to {_format_metadata_value(value)}"
                )
            else:
                meta_comments.append(
                    f"# metadata {key} on {name} omitted: unsupported value type"
                )

        prefix = f"Define {article} {noun_phrase} named {name}"
        if not clauses:
            sentence = f"{prefix}."
        else:
            sentence = f"{prefix} with {_join_clauses(clauses)}."

        return sentence, meta_comments
