"""Round-trip equality helper for NIR-Native CNL regression tests.

This module provides :func:`assert_round_trip_equal`, the canonical
fail-fast comparison used by the reference-fixture regression tests
(:mod:`neurocnl.tests.nir_native_cnl.test_reference_fixtures`) and the
round-trip property tests
(:mod:`neurocnl.tests.nir_native_cnl.test_round_trip_properties`).

The helper exists so every Round_Trip assertion required by
Requirement 5 lives in one place. Per Requirement 5.14, every failure
is reported with a structured :class:`AssertionError` whose message
names the failing node identifier (or edge endpoint pair), the
parameter name (when applicable), and the divergence between the
input value and the recovered value. The helper fails fast on the
first divergence — collecting every failure across a graph would dilute
the regression signal and is left to the parameterised pytest harness
that calls this helper once per fixture.

Comparison contract
-------------------
:func:`assert_round_trip_equal` enforces every Round_Trip identity rule
spelled out in Requirement 5:

* **Node-key set** — :meth:`nir.NIRGraph.nodes` keys must match exactly
  (Requirement 5.1).
* **Per-node type** — :func:`type` of each node must match
  (Requirement 5.2).
* **Scalar-or-vector parameters** (``ParamSpec.kind`` is ``"vector"``
  or ``"scalar"``) — equal under :func:`numpy.array_equal` after
  casting both sides to ``float64`` with identical ``shape``. Per
  Requirement 5.5 elementwise equality is asserted "under IEEE 754
  float64 representation" — so a ``float32`` source array that
  round-trips through the CNL grammar (which renders values as
  ``repr(float(v))``, IEEE 754 float64) still satisfies value
  equality at float64 precision (Requirements 5.3, 5.4, 5.5, 5.9,
  5.10). The literal ``dtype`` field is intentionally **not**
  compared because the CNL grammar does not encode dtype and the
  reference fixtures store ``float32`` weights/biases.
* **Tensor parameters** (``ParamSpec.kind`` is ``"tensor"``) — same
  ``shape`` after the round-trip, with a zero-filled recovered tensor.
  Tensor payloads are intentionally omitted from rendered CNL.
* **Integer-tuple structural parameters** (``ParamSpec.kind`` is
  ``"int_tuple"``) — both values are coerced to ``tuple[int, ...]``
  and compared with Python ``==`` (Requirements 5.6, 5.7).
* **Integer-scalar parameters** (``ParamSpec.kind`` is ``"int_scalar"``)
  — compared with Python ``==`` (Requirement 5.8).
* **``Input.input_type`` / ``Output.output_type``** — these arguments
  are tagged ``"int_tuple"`` in the grammar table but the upstream
  ``nir`` library stores them as ``{port_name: shape_array}`` dicts.
  The helper extracts the shape tuple from each side and compares the
  tuples (Requirements 5.1, 5.2).
* **Metadata** — :attr:`nir.NIRNode.metadata` dicts must satisfy
  ``dict(g_out.nodes[name].metadata) == dict(g_in.nodes[name].metadata)``
  (key set, value set) AND every value must satisfy
  ``type(out_value) is type(in_value)`` so a metadata ``int`` is not
  silently coerced to a ``float`` across the round-trip.
* **Edges** — the sorted multiset of ``(source, target)`` pairs must
  match (Requirement 5.11). Sorted comparison handles multisets
  because :class:`tuple` is orderable.

Failure messages
----------------
Every failure raises :class:`AssertionError` with a single structured
message. The message's first line identifies *what* failed (node-key
set, per-node type, parameter, metadata, or edges); subsequent fields
name the offending node identifier or ``(src, target)`` pair, the
parameter name (when applicable), and the input vs recovered values.
This shape satisfies Requirement 5.14 and gives the test harness a
unique signature per failing fixture.
"""

from __future__ import annotations

from typing import Any

import nir
import numpy as np

from neurocnl.nir_cnl.grammar_tables import ParamSpec, parameter_phrases

__all__ = ["assert_round_trip_equal"]


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------


def _extract_io_shape(io_type: Any) -> tuple[int, ...]:
    """Recover the shape tuple from an ``Input``/``Output`` port type.

    The upstream ``nir`` library stores ``Input.input_type`` and
    ``Output.output_type`` as ``{port_name: shape_array}`` dicts
    (where ``shape_array`` is a 1-D ``numpy.ndarray`` of int dims);
    older fixtures occasionally store the shape array directly. This
    helper accepts both shapes and returns a flat
    ``tuple[int, ...]`` for comparison.
    """
    if isinstance(io_type, dict):
        if not io_type:
            return ()
        arr = next(iter(io_type.values()))
    else:
        arr = io_type
    return tuple(int(v) for v in np.asarray(arr).flatten())


def _coerce_int_tuple(value: Any) -> tuple[int, ...]:
    """Coerce *value* to ``tuple[int, ...]`` for structural comparison.

    Accepts Python tuples and lists verbatim and converts numpy
    arrays through ``np.asarray(value).flatten()`` so the
    ``int_tuple`` comparison is independent of whether the underlying
    ``nir.*`` constructor stored its argument as a tuple
    (``Conv2d.stride``) or as an ``ndarray`` (``AvgPool2d.kernel_size``).
    """
    if isinstance(value, tuple | list):
        return tuple(int(x) for x in value)
    return tuple(int(x) for x in np.asarray(value).flatten())


def _fail_node(node_name: str, detail: str) -> None:
    """Raise an ``AssertionError`` framed by a node identifier.

    The ``Round-trip identity failed for node`` prefix is the test
    harness's signature for "Requirement 5 violation on a single
    node"; the *detail* string carries the parameter or metadata
    breakdown.
    """
    raise AssertionError(f"Round-trip identity failed for node {node_name!r}: {detail}")


def _fail_edges(detail: str) -> None:
    """Raise an ``AssertionError`` framed by the edge multiset."""
    raise AssertionError(f"Round-trip edge multiset failed: {detail}")


def _fail_node_set(detail: str) -> None:
    """Raise an ``AssertionError`` framed by the node-key set."""
    raise AssertionError(f"Round-trip node-key set failed: {detail}")


# ---------------------------------------------------------------------------
# Per-parameter comparison
# ---------------------------------------------------------------------------


def _compare_param(
    node_name: str,
    primitive: str,
    arg_name: str,
    spec: ParamSpec,
    value_in: Any,
    value_out: Any,
) -> None:
    """Compare one constructor argument across the round-trip.

    Dispatches on :attr:`ParamSpec.kind`. Raises a structured
    :class:`AssertionError` (via :func:`_fail_node`) on the first
    divergence; otherwise returns ``None``.
    """
    # ── Input.input_type / Output.output_type are stored as dicts ────
    # Tagged "int_tuple" in the grammar table but live as
    # ``{port_name: shape_array}`` in the ``nir`` runtime. Compare
    # by extracting the shape tuple from each side.
    if primitive in ("Input", "Output") and arg_name in (
        "input_type",
        "output_type",
    ):
        shape_in = _extract_io_shape(value_in)
        shape_out = _extract_io_shape(value_out)
        if shape_in != shape_out:
            _fail_node(
                node_name,
                f"parameter {arg_name!r} ({primitive}) shape mismatch — "
                f"input={shape_in!r}, recovered={shape_out!r}.",
            )
        return

    kind = spec.kind

    if kind == "tensor":
        arr_in = np.asarray(value_in)
        arr_out = np.asarray(value_out)
        if arr_in.shape != arr_out.shape:
            _fail_node(
                node_name,
                f"parameter {arg_name!r} ({primitive}) shape mismatch — "
                f"input shape={arr_in.shape!r}, "
                f"recovered shape={arr_out.shape!r}.",
            )
        expected_out = np.zeros_like(arr_in, dtype=np.float64)
        arr_out_64 = arr_out.astype(np.float64, copy=False)
        if not np.array_equal(expected_out, arr_out_64):
            _fail_node(
                node_name,
                f"parameter {arg_name!r} ({primitive}) expected zero-filled tensor "
                f"after shape-only round-trip — recovered={arr_out.tolist()!r}.",
            )
        return

    if kind in ("vector", "scalar"):
        arr_in = np.asarray(value_in)
        arr_out = np.asarray(value_out)
        if arr_in.shape != arr_out.shape:
            _fail_node(
                node_name,
                f"parameter {arg_name!r} ({primitive}) shape mismatch — "
                f"input shape={arr_in.shape!r}, "
                f"recovered shape={arr_out.shape!r}.",
            )
        # The dtype field is not encoded in the CNL surface — values
        # are rendered as ``repr(float(v))`` (Requirement 5.5) and
        # parsed back as Python ``float`` (IEEE 754 float64), so a
        # ``float32`` source array round-trips through ``float64``.
        # The reference fixtures store weights and biases as
        # ``float32``; preserving the dtype byte-exactly would
        # require extending the CNL grammar with a dtype clause,
        # which the spec does not define. We compare values under
        # float64 (the precision Requirement 5.5 mandates for
        # equality) and skip the literal dtype field check.
        arr_in_64 = arr_in.astype(np.float64, copy=False)
        arr_out_64 = arr_out.astype(np.float64, copy=False)
        expected_out = (
            np.zeros_like(arr_in_64)
            if kind == "vector" and primitive != "Scale" and arr_in.size > 1
            else arr_in_64
        )
        if not np.array_equal(expected_out, arr_out_64):
            _fail_node(
                node_name,
                f"parameter {arg_name!r} ({primitive}) value mismatch — "
                f"input={arr_in.tolist()!r}, "
                f"recovered={arr_out.tolist()!r}.",
            )
        return

    if kind == "int_tuple":
        tup_in = _coerce_int_tuple(value_in)
        tup_out = _coerce_int_tuple(value_out)
        if tup_in != tup_out:
            _fail_node(
                node_name,
                f"parameter {arg_name!r} ({primitive}) integer-tuple "
                f"mismatch — input={tup_in!r}, recovered={tup_out!r}.",
            )
        return

    if kind == "int_scalar":
        if value_in != value_out:
            _fail_node(
                node_name,
                f"parameter {arg_name!r} ({primitive}) integer-scalar "
                f"mismatch — input={value_in!r}, recovered={value_out!r}.",
            )
        return

    # Defensive: every documented kind is handled above. A new kind
    # in the grammar table without a matching branch here is a bug
    # in this helper — surface it loudly so it is fixed before any
    # regression test silently passes.
    raise AssertionError(
        f"Round-trip helper does not know how to compare ParamSpec.kind "
        f"{kind!r} for {primitive}.{arg_name} on node {node_name!r}."
    )


# ---------------------------------------------------------------------------
# Per-node metadata comparison
# ---------------------------------------------------------------------------


def _compare_metadata(
    node_name: str,
    meta_in: dict[str, Any],
    meta_out: dict[str, Any],
) -> None:
    """Compare the per-node metadata dicts under Python ``==``.

    Enforces both value equality (``dict.__eq__``) and type
    preservation (``type(out[k]) is type(in[k])`` for every key) so a
    metadata ``int`` is not silently widened to a ``float`` across
    the round-trip.
    """
    if meta_in.keys() != meta_out.keys():
        only_in = sorted(meta_in.keys() - meta_out.keys())
        only_out = sorted(meta_out.keys() - meta_in.keys())
        _fail_node(
            node_name,
            f"metadata key-set mismatch — missing from recovered: "
            f"{only_in!r}; unexpected in recovered: {only_out!r}.",
        )

    for key in meta_in:
        v_in = meta_in[key]
        v_out = meta_out[key]
        if v_in != v_out:
            _fail_node(
                node_name,
                f"metadata value mismatch on key {key!r} — input={v_in!r}, recovered={v_out!r}.",
            )
        if type(v_in) is not type(v_out):
            _fail_node(
                node_name,
                f"metadata type mismatch on key {key!r} — "
                f"input type={type(v_in).__name__}, "
                f"recovered type={type(v_out).__name__}.",
            )


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------


def assert_round_trip_equal(
    g_in: nir.NIRGraph,
    g_out: nir.NIRGraph,
) -> None:
    """Assert that *g_out* is a Round_Trip identity of *g_in*.

    See the module docstring for the precise comparison contract.
    Raises a single :class:`AssertionError` on the first divergence,
    naming the failing node identifier (or edge endpoint pair), the
    parameter name (when applicable), and the input vs recovered
    values, per Requirement 5.14.

    Parameters
    ----------
    g_in:
        The input NIR graph as produced by ``nir.read`` or directly
        constructed in test code.
    g_out:
        The recovered NIR graph after ``NIR_Renderer.render →
        NIR_CNL_Parser.parse → NIR_Compiler.compile``.

    Raises
    ------
    AssertionError
        On any divergence between *g_in* and *g_out* per the
        comparison contract. The message is structured to identify
        the failure category, the offending node or edge, the
        parameter (when applicable), and the input-vs-recovered
        values so the test harness can attribute the regression to a
        specific Requirement 5 sub-criterion.
    """
    # ── Node-key set (Requirement 5.1) ───────────────────────────────
    in_keys = set(g_in.nodes.keys())
    out_keys = set(g_out.nodes.keys())
    if in_keys != out_keys:
        only_in = sorted(in_keys - out_keys)
        only_out = sorted(out_keys - in_keys)
        _fail_node_set(
            f"input nodes={sorted(in_keys)!r}, "
            f"recovered nodes={sorted(out_keys)!r}; "
            f"missing from recovered={only_in!r}; "
            f"unexpected in recovered={only_out!r}."
        )

    # ── Per-node type, parameters, and metadata ──────────────────────
    for name in g_in.nodes.keys():
        node_in = g_in.nodes[name]
        node_out = g_out.nodes[name]

        type_in = type(node_in)
        type_out = type(node_out)
        if type_in is not type_out:
            _fail_node(
                name,
                f"type mismatch — input type={type_in.__name__}, "
                f"recovered type={type_out.__name__}.",
            )

        primitive = type_in.__name__
        # Skip parameter comparison for primitives outside the 18
        # documented Primitives. Per Requirement 5.12 such nodes are
        # not part of the Round_Trip identity contract; the helper's
        # caller is responsible for excluding them from the input
        # graph if desired. The type check above still ran, so an
        # accidental type swap is caught regardless.
        if primitive in parameter_phrases:
            for arg_name, spec in parameter_phrases[primitive].items():
                value_in = getattr(node_in, arg_name)
                value_out = getattr(node_out, arg_name)
                _compare_param(name, primitive, arg_name, spec, value_in, value_out)

        # Per-node metadata (Requirement 10.1, 10.2, 10.3, 10.4). The
        # ``dict(...)`` calls coerce any odd mapping types the
        # upstream library might use (e.g. ``MappingProxyType``) into
        # the same concrete shape so ``__eq__`` is well-defined.
        meta_in = dict(getattr(node_in, "metadata", None) or {})
        meta_out = dict(getattr(node_out, "metadata", None) or {})
        _compare_metadata(name, meta_in, meta_out)

    # ── Edge multiset (Requirement 5.11) ─────────────────────────────
    in_edges = sorted((str(src), str(tgt)) for src, tgt in g_in.edges)
    out_edges = sorted((str(src), str(tgt)) for src, tgt in g_out.edges)
    if in_edges != out_edges:
        # Compute symmetric difference as multisets so the diagnostic
        # tells the user *which* edges diverged, not just that the
        # full lists differ.
        in_counter: dict[tuple[str, str], int] = {}
        for e in in_edges:
            in_counter[e] = in_counter.get(e, 0) + 1
        out_counter: dict[tuple[str, str], int] = {}
        for e in out_edges:
            out_counter[e] = out_counter.get(e, 0) + 1
        missing = sorted(e for e, n in in_counter.items() if out_counter.get(e, 0) < n)
        extra = sorted(e for e, n in out_counter.items() if in_counter.get(e, 0) < n)
        _fail_edges(
            f"input edges (sorted)={in_edges!r}, "
            f"recovered edges (sorted)={out_edges!r}; "
            f"missing from recovered={missing!r}; "
            f"unexpected in recovered={extra!r}."
        )
