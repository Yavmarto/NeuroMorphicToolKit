"""NIR-Native CNL compiler.

This module implements :class:`NIR_Compiler`, the materialisation stage
of the NIR-Native CNL pipeline. The compiler converts the intermediate
record list produced by :class:`~neurocnl.nir_cnl.parser.NIR_CNL_Parser`
into a :class:`nir.NIRGraph` suitable for downstream simulators or
serialisation back to disk.

Pipeline
--------
The compiler runs four validation phases in strict order. A non-empty
diagnostic list at the end of any phase raises a single
:class:`~neurocnl.compile.CompileError` carrying every diagnostic
collected in that phase; downstream phases are skipped and no
``nir.NIRGraph`` is constructed.

1. **Ghost nodes** (``code="ghost_node"``). Every edge endpoint must
   resolve to a declared :class:`~neurocnl.nir_cnl.ir_types.NIRNodeRecord`
   in the same record list (Requirement 4.5).
2. **Duplicate edges** (``code="duplicate_edge"``). No ``(src, target)``
   pair may appear more than once (Requirement 4.6).
3. **Missing endpoints** (``code="missing_endpoint"``). The graph must
   contain at least one ``Input`` and one ``Output`` node
   (Requirement 4.7). A single diagnostic names whichever role(s) are
   missing.
4. **Per-node materialisation**. Each node record is dispatched to the
   appropriate per-Primitive builder. Builders raise
   :class:`CompileError` with codes such as ``"missing_shape"``,
   ``"missing_required_parameter"``, ``"shape_for_scalar"``,
   ``"shape_rank_mismatch"``, ``"invalid_shape"``, or
   ``"invalid_value"`` (Requirements 2.6, 2.9, 2.10, 11.6–11.8). The
   outer loop catches each per-node :class:`CompileError`, extends the
   master diagnostic list with ``exc.diagnostics``, and continues so
   the user sees every per-node failure in one pass.

Parameter materialisation
-------------------------
The compiler dispatches on the ``ParamSpec.kind`` declared in
:data:`~neurocnl.nir_cnl.grammar_tables.parameter_phrases`. The five
documented kinds are handled as follows:

* ``"vector"`` — accepts a Python ``int``/``float`` (broadcast to a
  length-1 ``float64`` array), an
  :class:`~neurocnl.nir_cnl.ir_types.ArraySpec` (materialised as
  ``numpy.zeros(shape, dtype=float)`` — the Dummy_Array convenience of
  Requirement 11.1), or an
  :class:`~neurocnl.nir_cnl.ir_types.ArrayValues` (materialised as
  ``numpy.asarray(values, dtype=float).reshape(shape)``).
* ``"tensor"`` — accepts only :class:`ArraySpec` or
  :class:`ArrayValues`; a bare scalar raises
  ``CompileError(code="invalid_value")``.
* ``"int_tuple"`` — accepts a Python ``tuple[int, ...]``; an
  :class:`ArraySpec`/:class:`ArrayValues` raises
  ``CompileError(code="shape_for_scalar")``. The result is delivered
  to the ``nir.*`` constructor either as a plain tuple (``Conv2d``) or
  as a ``numpy.ndarray`` with ``dtype=int`` (``AvgPool2d`` /
  ``SumPool2d``), per the upstream constructor signature. ``Conv1d``
  unwraps the rank-1 tuple to a Python ``int`` because its
  constructor takes scalar ``stride`` / ``padding`` / ``dilation``.
* ``"int_scalar"`` — accepts a Python ``int`` (or ``bool``, which is
  cast via ``int()``); an :class:`ArraySpec`/:class:`ArrayValues`
  raises ``CompileError(code="shape_for_scalar")``.
* ``"scalar"`` — currently unused by the documented parameter table;
  reserved for future grammar extensions.

Auto-bias derivation
--------------------
Per Requirement 11.2–11.5, when an ``Affine`` or ``Conv2d`` record
carries an explicit ``weight`` clause and no ``bias`` clause, the
compiler synthesises ``bias = numpy.zeros((weight.shape[0],),
dtype=float)``. An explicit bias clause always wins; auto-derivation
never overrides user input. ``Conv1d`` is *not* covered by the
auto-bias rule — its ``bias`` argument is required and the user must
supply it explicitly.

Metadata
--------
After every node is constructed, the compiler copies the record's
metadata dict onto the ``nir.*`` instance via
``node.metadata = dict(record.metadata)`` (Requirements 10.3, 10.4).
The shallow copy preserves the Python types ``str``, ``int``, and
``float`` as the parser produced them.

Network containers
------------------
The grammar permits zero or more ``Define a network named <id>.``
sentences (Requirement 1.7). The compiler uses the *first* container's
identifier as the resulting graph's ``name`` field and silently skips
any subsequent containers — multi-network compilation is out of scope
for this surface.

Timestep propagation
---------------------
The network sentence's optional ``with timestep <seconds>`` clause
(also Requirement 1.7) is likewise taken from the first container only.
When declared, the compiler:

* injects it as ``metadata["dt"]`` onto every compiled ``nir.LIF`` node
  that doesn't already carry its own explicit ``dt`` (an explicit
  per-node ``metadata dt`` clause always wins over the network
  default), and
* mirrors it onto the compiled graph's own ``metadata["dt"]``, so the
  renderer can re-emit one concise network-level declaration instead of
  duplicating a clause on every LIF node.

``nir.CubaLIF`` and other dynamical node types are deliberately left
untouched — they have their own, separately-scoped ``dt`` handling
downstream and are out of scope for this clause.

Input / Output ports
--------------------
The upstream ``nir`` library represents ``Input.input_type`` and
``Output.output_type`` as ``{port_name: shape_array}`` dicts. The CNL
grammar carries only the shape, so the compiler wraps the parsed
``int_tuple`` as ``{"input": numpy.asarray(shape, dtype=int)}`` and
``{"output": numpy.asarray(shape, dtype=int)}`` respectively.

Design references
-----------------
* ``.kiro/specs/nir-native-cnl/requirements.md`` — Requirements 2.6–2.10,
  4.5–4.7, 10.3–10.4, 11.1–11.8.
* ``.kiro/specs/nir-native-cnl/design.md`` — § "CNL → NIR (parse +
  compile)", § "NIR_Compiler", and § "Error Codes".
"""

from __future__ import annotations

import nir

from neurocnl._nir_compat import make_nir_graph
from neurocnl.compile import CompileError, Diagnostic
from neurocnl.nir_cnl.ir_types import (
    EvaluationConfigRecord,
    ExportConfigRecord,
    NetworkContainer,
    NIREdgeRecord,
    NIRNodeRecord,
    TrainingConfigRecord,
)
from neurocnl.nir_cnl.node_factories import _BUILDERS, _build_flatten, _flatten_input_shape
from neurocnl.nir_cnl.param_resolution import (
    _diag,
    _raise_single,
)
from neurocnl.nir_cnl.param_resolution import (
    _resolve_tensor as _resolve_tensor,  # noqa: F401 — compatibility re-export; imported by tests
)
from neurocnl.nir_cnl.shape_inference import (
    conv2d_output_shape,
    infer_known_shapes,
    infer_output_shape,
    pair,
    pool2d_output_shape,
    shape_tuple,
    vector_node_shape,
)

__all__ = ["NIR_Compiler"]

# Private compatibility aliases retained for one release while tests and
# downstream callers migrate to ``shape_inference``.
_conv2d_output_shape = conv2d_output_shape
_infer_known_shapes = infer_known_shapes
_infer_output_shape = infer_output_shape
_pair = pair
_pool2d_output_shape = pool2d_output_shape
_shape_tuple = shape_tuple
_vector_node_shape = vector_node_shape


# Record types accepted by :meth:`NIR_Compiler.compile`. Pipeline
# config records (``TrainingConfigRecord`` / ``EvaluationConfigRecord``
# / ``ExportConfigRecord``) are included here for type-checker
# completeness only — the compiler's Phase 0 partition loop below
# intentionally ignores them; they carry no graph semantics and are
# extracted separately via ``nir_cnl.pipeline_config.extract_pipeline_config``.
_Record = (
    NIRNodeRecord
    | NIREdgeRecord
    | NetworkContainer
    | TrainingConfigRecord
    | EvaluationConfigRecord
    | ExportConfigRecord
)


# ---------------------------------------------------------------------------
# NIR_Compiler
# ---------------------------------------------------------------------------


class NIR_Compiler:
    """Materialise NIR-Native CNL records into a :class:`nir.NIRGraph`.

    The compiler is stateless — every call to :meth:`compile` is
    independent. See the module docstring for the full validation
    contract.

    Examples
    --------
    >>> from neurocnl.nir_cnl.parser import NIR_CNL_Parser
    >>> from neurocnl.nir_cnl.compiler import NIR_Compiler
    >>> records = NIR_CNL_Parser().parse(
    ...     "Define a network named demo.\\n"
    ...     "Define an input port named in1 with shape (1,).\\n"
    ...     "Define an output port named out1 with shape (1,).\\n"
    ...     "Connect in1 to out1."
    ... )
    >>> graph = NIR_Compiler().compile(records)
    >>> sorted(graph.nodes.keys())
    ['in1', 'out1']
    """

    # ------------------------------------------------------------------
    # Public entry point
    # ------------------------------------------------------------------

    def compile(self, records: list[_Record]) -> nir.NIRGraph:
        """Materialise *records* into a :class:`nir.NIRGraph`.

        Parameters
        ----------
        records:
            Mixed list of :class:`NIRNodeRecord`, :class:`NIREdgeRecord`,
            and :class:`NetworkContainer` records as returned by
            :meth:`NIR_CNL_Parser.parse`.

        Returns
        -------
        nir.NIRGraph
            The compiled NIR graph. The graph's ``name`` attribute is
            taken from the first :class:`NetworkContainer` (if any).

        Raises
        ------
        CompileError
            On any structural or per-node failure. The exception
            carries every collected :class:`Diagnostic`.
        """
        # ── Phase 0: partition records ────────────────────────────────
        node_records: list[NIRNodeRecord] = []
        edge_records: list[NIREdgeRecord] = []
        container_records: list[NetworkContainer] = []
        for rec in records:
            if isinstance(rec, NIRNodeRecord):
                node_records.append(rec)
            elif isinstance(rec, NIREdgeRecord):
                edge_records.append(rec)
            elif isinstance(rec, NetworkContainer):
                container_records.append(rec)
            # Pipeline config records (TrainingConfigRecord /
            # EvaluationConfigRecord / ExportConfigRecord) fall through
            # here intentionally: they carry training/eval/export
            # scalars, not graph structure, so nir.NIRGraph's shape and
            # this method's signature stay exactly as they were before
            # the pipeline-CNL grammar extension. Callers who need that
            # config call ``pipeline_config.extract_pipeline_config``
            # on the same record list separately.

        # The grammar permits multiple network-container declarations
        # but this surface only honours the first; subsequent containers
        # are dropped silently per the implementation note.
        graph_name: str | None = container_records[0].name if container_records else None
        # Requirement 1.7's optional network-timestep clause: when
        # declared, propagate into every nir.LIF node's metadata["dt"]
        # (Phase 4 below) and mirror it onto the compiled graph itself
        # (Phase 5) so the renderer can round-trip a single network-level
        # declaration instead of duplicating a per-node clause.
        graph_dt: float | None = (
            container_records[0].timestep_seconds if container_records else None
        )

        declared_names: set[str] = {rec.name for rec in node_records}

        # ── Phase 1: ghost-node validation (Requirement 4.5) ──────────
        ghost_diagnostics: list[Diagnostic] = []
        for edge in edge_records:
            if edge.src not in declared_names:
                ghost_diagnostics.append(
                    _diag(
                        code="ghost_node",
                        message=(
                            f"Edge ({edge.src!r} -> {edge.target!r}) "
                            f"references undeclared source node "
                            f"{edge.src!r}."
                        ),
                        line=edge.line,
                        hint=(
                            f"Declare a node named {edge.src!r} before "
                            f"using it in a Connect sentence."
                        ),
                    )
                )
            if edge.target not in declared_names:
                ghost_diagnostics.append(
                    _diag(
                        code="ghost_node",
                        message=(
                            f"Edge ({edge.src!r} -> {edge.target!r}) "
                            f"references undeclared target node "
                            f"{edge.target!r}."
                        ),
                        line=edge.line,
                        hint=(
                            f"Declare a node named {edge.target!r} before "
                            f"using it in a Connect sentence."
                        ),
                    )
                )
        if ghost_diagnostics:
            raise CompileError(
                f"Ghost node reference(s): {len(ghost_diagnostics)} undeclared endpoint(s).",
                ghost_diagnostics,
            )

        # ── Phase 2: duplicate-edge validation (Requirement 4.6) ──────
        seen: dict[tuple[str, str], int] = {}
        dup_diagnostics: list[Diagnostic] = []
        for idx, edge in enumerate(edge_records):
            key = (edge.src, edge.target)
            if key in seen:
                dup_diagnostics.append(
                    _diag(
                        code="duplicate_edge",
                        message=(
                            f"Duplicate edge ({edge.src!r} -> "
                            f"{edge.target!r}); first declared at index "
                            f"{seen[key]}, repeated at index {idx} "
                            f"(line {edge.line})."
                        ),
                        line=edge.line,
                        hint="Remove one of the duplicate Connect sentences.",
                    )
                )
            else:
                seen[key] = idx
        if dup_diagnostics:
            raise CompileError(
                f"Duplicate edge(s): {len(dup_diagnostics)} duplicate(s) found.",
                dup_diagnostics,
            )

        # ── Phase 3: missing-endpoint validation (Requirement 4.7) ────
        has_input = any(r.primitive == "Input" for r in node_records)
        has_output = any(r.primitive == "Output" for r in node_records)
        if not (has_input and has_output):
            missing: list[str] = []
            if not has_input:
                missing.append("Input")
            if not has_output:
                missing.append("Output")
            roles = " and ".join(missing)
            msg = f"Graph is missing the following endpoint role(s): {roles}."
            raise CompileError(
                msg,
                [
                    _diag(
                        code="missing_endpoint",
                        message=msg,
                        hint=(
                            "Add at least one "
                            + roles
                            + " node — e.g. "
                            + " and ".join(
                                [
                                    (
                                        "'Define an input port named in1 with shape (1,).'"
                                        if role == "Input"
                                        else "'Define an output port named out1 with shape (1,).'"
                                    )
                                    for role in missing
                                ]
                            )
                        ),
                    )
                ],
            )

        # ── Phase 4: per-node materialisation ─────────────────────────
        built_nodes: dict[str, nir.NIRNode] = {}
        node_diagnostics: list[Diagnostic] = []
        for record in node_records:
            if record.primitive == "Flatten":
                continue
            try:
                node = self._build_nir_node(record)
            except CompileError as exc:
                # Stamp the source line on every per-node diagnostic
                # that did not already carry one; the per-kind helpers
                # set ``line`` themselves but the missing-parameter
                # path threads it through ``_missing_param_error``.
                for d in exc.diagnostics:
                    if d.line is None:
                        d.line = record.line
                node_diagnostics.extend(exc.diagnostics)
                continue
            # Requirement 10.3 / 10.4: attach the metadata dict, copying
            # so downstream mutation of either dict is independent.
            node.metadata = dict(record.metadata)
            if graph_dt is not None and isinstance(node, nir.LIF) and "dt" not in node.metadata:
                # Explicit per-node ``metadata dt`` always wins over the
                # declared network default (checked just above).
                node.metadata["dt"] = graph_dt
            built_nodes[record.name] = node

        shapes = _infer_known_shapes(built_nodes, edge_records)
        for record in node_records:
            if record.primitive != "Flatten":
                continue
            try:
                node = _build_flatten(record, _flatten_input_shape(record, edge_records, shapes))
            except CompileError as exc:
                for d in exc.diagnostics:
                    if d.line is None:
                        d.line = record.line
                node_diagnostics.extend(exc.diagnostics)
                continue
            node.metadata = dict(record.metadata)
            node.metadata.pop("nmtk_flatten_input_shape", None)
            built_nodes[record.name] = node
            shapes = _infer_known_shapes(built_nodes, edge_records)

        if node_diagnostics:
            raise CompileError(
                f"Per-node materialisation failed for "
                f"{len({d.line for d in node_diagnostics})} record(s).",
                node_diagnostics,
            )
        built_nodes = {record.name: built_nodes[record.name] for record in node_records}

        # ── Phase 5: assemble the graph ───────────────────────────────
        edges: list[tuple[str, str]] = [(e.src, e.target) for e in edge_records]
        graph = make_nir_graph(built_nodes, edges)
        if graph_dt is not None:
            graph.metadata["dt"] = graph_dt
        if graph_name is not None:
            # ``nir.NIRGraph`` does not declare ``name`` as a constructor
            # argument; setattr keeps the round-trip honest when the
            # upstream library exposes the field, and is a no-op
            # otherwise.
            try:
                graph.name = graph_name
            except AttributeError:  # pragma: no cover - defensive
                pass
        return graph

    # ------------------------------------------------------------------
    # Internal: per-node dispatch
    # ------------------------------------------------------------------

    def _build_nir_node(self, record: NIRNodeRecord) -> nir.NIRNode:
        """Dispatch *record* to the appropriate per-Primitive builder.

        Raises :class:`CompileError` with ``code="unknown_primitive"``
        when ``record.primitive`` does not name one of the documented
        Primitives (see ``_BUILDERS``). In practice the parser rejects
        unknown noun phrases
        long before reaching this branch, but the explicit guard keeps
        the compiler honest if the IR is hand-constructed.
        """
        builder = _BUILDERS.get(record.primitive)
        if builder is None:
            _raise_single(
                code="unknown_primitive",
                message=(
                    f"NIR_Compiler does not know how to build primitive {record.primitive!r}."
                ),
                line=record.line,
                hint=(f"Supported primitives: {', '.join(sorted(_BUILDERS))}."),
            )
        return builder(record)
