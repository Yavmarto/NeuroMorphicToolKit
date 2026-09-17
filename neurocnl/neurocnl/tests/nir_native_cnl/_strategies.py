"""Shared Hypothesis strategies for the NIR-Native CNL property tests.

This module exposes :func:`nir_graph_strategy`, the canonical generator
for random :class:`nir.NIRGraph` instances over the 18 documented NIR
Primitives. Several property tests across this directory call into the
same generator so the round-trip identity, renderer-token, parser
diagnostic, and shape-literal property tests all exercise the same
input space.

Generation contract
-------------------
The generated graphs satisfy the post-conditions Requirements 4 and 5
require for round-trip identity:

* every graph contains at least one ``Input`` and one ``Output`` node
  (Requirement 4.7);
* every graph carries the NIR-Native CNL header
  ``Define a network named graph.`` because the renderer emits one for
  every input;
* node identifiers match Requirement 1.3's ``[A-Za-z_][A-Za-z0-9_]*``
  contract (length 1–16) so the generated identifiers also cover
  hand-typed identifiers a user is likely to write;
* metadata dicts carry ``str``, ``int``, and finite-``float`` values
  only — Requirement 10 restricts metadata clauses to those three
  primitive types so a strategy that emits ``None`` or ``NaN`` would
  cause render-time comment fall-through that the round-trip test
  would then have to special-case.

The strategy is intentionally narrow on the "shape-and-value" axis to
keep round-trip identity reachable: dimension sizes are bounded to a
small range, weight tensors stay rank-2 for ``Linear``/``Affine``, and
``Conv2d`` weight kernels stay rank-4 with small spatial dimensions.
The bound choices match the Requirement 4.3 documented dimension range
``[1, 4096]`` while keeping per-iteration cost low.

Usage
-----
.. code-block:: python

    from hypothesis import given, settings
    from neurocnl.tests.nir_native_cnl._strategies import nir_graph_strategy

    @given(graph=nir_graph_strategy())
    @settings(max_examples=100, deadline=None)
    def test_some_property(graph):
        ...
"""

from __future__ import annotations

import re
import string
from typing import TYPE_CHECKING, Any

import nir
import numpy as np
from hypothesis import strategies as st

if TYPE_CHECKING:
    from neurocnl.nir_cnl.pipeline_config import PipelineConfig

__all__ = [
    "identifier_strategy",
    "metadata_strategy",
    "node_strategy",
    "nir_graph_strategy",
    "pipeline_config_strategy",
    "PRIMITIVE_NAMES",
]


# ---------------------------------------------------------------------------
# Identifiers
# ---------------------------------------------------------------------------


# Requirement 1.3 contract: ``[A-Za-z_][A-Za-z0-9_]*`` of length 1–64.
# We bound the strategy at length 16 to keep generated test inputs
# readable in failure traces without losing coverage of the edge cases.
_IDENT_FIRST = string.ascii_letters + "_"
_IDENT_REST = string.ascii_letters + string.digits + "_"
_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def identifier_strategy() -> st.SearchStrategy[str]:
    """Strategy emitting node identifiers per Requirement 1.3.

    The identifier always starts with a letter or underscore and
    contains 0–15 additional ``[A-Za-z0-9_]`` characters. The strategy
    filters out any output that — by sheer string-build coincidence —
    happened to look like a parser keyword such as ``shape`` or
    ``and``; that filter is cheap and keeps the round-trip property
    tests free of accidental keyword collisions.
    """
    return st.builds(
        lambda first, rest: first + rest,
        first=st.sampled_from(_IDENT_FIRST),
        rest=st.text(alphabet=_IDENT_REST, min_size=0, max_size=15),
    ).filter(
        lambda s: (
            _IDENT_RE.match(s) is not None
            and s.lower()
            not in {
                "define",
                "create",
                "named",
                "with",
                "and",
                "connect",
                "to",
                "network",
                "annotated",
                "metadata",
                "equal",
                "shape",
                "values",
                "a",
                "an",
            }
        )
    )


# ---------------------------------------------------------------------------
# Numeric value strategies
# ---------------------------------------------------------------------------


def _finite_float_strategy(
    *, min_value: float = -1e3, max_value: float = 1e3
) -> st.SearchStrategy[float]:
    """Strategy of finite IEEE 754 float64 values in a reasonable range.

    Excludes ``NaN`` and ``±inf`` so every generated value can be
    ``repr(float(v))``-rendered and parsed back as a ``float`` without
    falling into the metadata-comment fall-through path.
    """
    return st.floats(
        min_value=min_value,
        max_value=max_value,
        allow_nan=False,
        allow_infinity=False,
        allow_subnormal=False,
        width=64,
    )


def _vector_array_strategy(
    *, min_size: int = 1, max_size: int = 3
) -> st.SearchStrategy[np.ndarray[Any, np.dtype[np.float64]]]:
    """Strategy of 1-D ``float64`` arrays of small length.

    The grammar's ``vector`` kind covers per-neuron physical parameters
    (``tau``, ``r``, ``v_leak``, ``v_threshold``); these strategies
    bound the length to the same small range the eight reference
    fixtures exercise so the resulting graphs stay quick to materialise.
    """
    return st.lists(
        _finite_float_strategy(),
        min_size=min_size,
        max_size=max_size,
    ).map(lambda lst: np.asarray(lst, dtype=np.float64))


def _coord_vector_arrays(
    n: int, *, count: int, draw: st.DrawFn
) -> list[np.ndarray[Any, np.dtype[np.float64]]]:
    """Draw *count* 1-D ``float64`` arrays that all share length *n*.

    Several upstream NIR neuron constructors enforce that their per-
    neuron parameters share the same shape (``LIF`` checks
    ``self.tau.shape == self.r.shape == self.v_leak.shape ==
    self.v_threshold.shape``; ``CubaLIF``, ``CubaLI``, and ``IF``
    enforce similar invariants). Use this helper inside ``@composite``
    strategies so every drawn parameter list has the same length.
    """
    return [
        np.asarray(
            draw(st.lists(_finite_float_strategy(), min_size=n, max_size=n)),
            dtype=np.float64,
        )
        for _ in range(count)
    ]


# ---------------------------------------------------------------------------
# Metadata strategy
# ---------------------------------------------------------------------------


def metadata_strategy() -> st.SearchStrategy[dict[str, Any]]:
    """Strategy of small, type-safe metadata dicts (Requirement 10).

    Keys are short identifier strings (1–8 characters,
    ``[A-Za-z_][A-Za-z0-9_]*``) so they can appear literally in the
    rendered ``annotated with metadata <key> equal to <value>`` clause
    without further escaping.

    Values are restricted to ``str``, ``int``, and finite ``float`` —
    the three primitive types Requirement 10 declares supported. This
    restriction is intentional: emitting an unsupported value type
    triggers the renderer's comment fall-through path (Requirement
    10.5) and the round-trip equality contract no longer holds, which
    is not what the round-trip property test is asserting.

    The dict is bounded at 0–3 entries to keep generated graphs small
    and the resulting CNL text human-readable in failure traces.
    """
    key = st.from_regex(r"^[A-Za-z_][A-Za-z0-9_]{0,7}$", fullmatch=True)
    value = st.one_of(
        st.text(alphabet=string.ascii_letters + string.digits + " ", max_size=16),
        st.integers(min_value=-1000, max_value=1000),
        _finite_float_strategy(min_value=-100.0, max_value=100.0),
    )
    return st.dictionaries(keys=key, values=value, max_size=3)


# ---------------------------------------------------------------------------
# Per-Primitive node strategies
# ---------------------------------------------------------------------------


# The 18 documented Primitives. Defined here as the canonical name
# tuple so other tests can import it without re-deriving from the
# grammar table.
PRIMITIVE_NAMES: tuple[str, ...] = (
    "Input",
    "Output",
    "IF",
    "LIF",
    "LI",
    "CubaLIF",
    "CubaLI",
    "I",
    "Linear",
    "Affine",
    "Scale",
    "Conv1d",
    "Conv2d",
    "AvgPool2d",
    "SumPool2d",
    "Flatten",
    "Delay",
    "Threshold",
)


def _input_strategy() -> st.SearchStrategy[nir.Input]:
    return st.lists(st.integers(min_value=1, max_value=8), min_size=1, max_size=2).map(
        lambda dims: nir.Input(input_type=np.asarray(dims, dtype=int))
    )


def _output_strategy() -> st.SearchStrategy[nir.Output]:
    return st.lists(st.integers(min_value=1, max_value=8), min_size=1, max_size=2).map(
        lambda dims: nir.Output(output_type=np.asarray(dims, dtype=int))
    )


def _if_strategy() -> st.SearchStrategy[nir.IF]:
    @st.composite
    def _build(draw: st.DrawFn) -> Any:
        n = draw(st.integers(min_value=1, max_value=3))
        r, vth = _coord_vector_arrays(n, count=2, draw=draw)
        return nir.IF(r=r, v_threshold=vth)

    return _build()


def _lif_strategy() -> st.SearchStrategy[nir.LIF]:
    @st.composite
    def _build(draw: st.DrawFn) -> Any:
        n = draw(st.integers(min_value=1, max_value=3))
        tau, r, vleak, vth = _coord_vector_arrays(n, count=4, draw=draw)
        return nir.LIF(tau=tau, r=r, v_leak=vleak, v_threshold=vth)

    return _build()


def _li_strategy() -> st.SearchStrategy[nir.LI]:
    @st.composite
    def _build(draw: st.DrawFn) -> Any:
        n = draw(st.integers(min_value=1, max_value=3))
        tau, r, vleak = _coord_vector_arrays(n, count=3, draw=draw)
        return nir.LI(tau=tau, r=r, v_leak=vleak)

    return _build()


def _cubalif_strategy() -> st.SearchStrategy[nir.CubaLIF]:
    @st.composite
    def _build(draw: st.DrawFn) -> Any:
        n = draw(st.integers(min_value=1, max_value=3))
        tsyn, tmem, r, vleak, vth, win = _coord_vector_arrays(n, count=6, draw=draw)
        return nir.CubaLIF(
            tau_syn=tsyn,
            tau_mem=tmem,
            r=r,
            v_leak=vleak,
            v_threshold=vth,
            w_in=win,
        )

    return _build()


def _cubali_strategy() -> st.SearchStrategy[nir.CubaLI]:
    @st.composite
    def _build(draw: st.DrawFn) -> Any:
        n = draw(st.integers(min_value=1, max_value=3))
        tsyn, tmem, r, vleak, win = _coord_vector_arrays(n, count=5, draw=draw)
        return nir.CubaLI(tau_syn=tsyn, tau_mem=tmem, r=r, v_leak=vleak, w_in=win)

    return _build()


def _i_strategy() -> st.SearchStrategy[nir.I]:
    return st.builds(
        lambda r: nir.I(r=r),
        r=_vector_array_strategy(),
    )


def _linear_strategy() -> st.SearchStrategy[nir.Linear]:
    # Rank-2 weight matrices with small dimensions so generated
    # values lists stay short.
    @st.composite
    def _build(draw: st.DrawFn) -> Any:
        rows = draw(st.integers(min_value=1, max_value=3))
        cols = draw(st.integers(min_value=1, max_value=3))
        n = rows * cols
        vals = draw(st.lists(_finite_float_strategy(), min_size=n, max_size=n))
        weight = np.asarray(vals, dtype=np.float64).reshape((rows, cols))
        return nir.Linear(weight=weight)

    return _build()


def _affine_strategy() -> st.SearchStrategy[nir.Affine]:
    @st.composite
    def _build(draw: st.DrawFn) -> Any:
        rows = draw(st.integers(min_value=1, max_value=3))
        cols = draw(st.integers(min_value=1, max_value=3))
        weight_vals = draw(
            st.lists(
                _finite_float_strategy(), min_size=rows * cols, max_size=rows * cols
            )
        )
        weight = np.asarray(weight_vals, dtype=np.float64).reshape((rows, cols))
        bias_vals = draw(
            st.lists(_finite_float_strategy(), min_size=rows, max_size=rows)
        )
        bias = np.asarray(bias_vals, dtype=np.float64)
        return nir.Affine(weight=weight, bias=bias)

    return _build()


def _scale_strategy() -> st.SearchStrategy[nir.Scale]:
    return st.builds(
        lambda v: nir.Scale(scale=v),
        v=_vector_array_strategy(),
    )


def _flatten_strategy() -> st.SearchStrategy[nir.Flatten]:
    # Flatten requires that prod(input_shape) equals the product of
    # the post-flatten shape; we generate a single 1-D shape so this
    # invariant is trivially satisfied.
    return st.builds(
        lambda dim: nir.Flatten(
            input_type={"input": np.asarray([dim], dtype=int)},
            start_dim=0,
            end_dim=-1,
        ),
        dim=st.integers(min_value=1, max_value=8),
    )


def _delay_strategy() -> st.SearchStrategy[nir.Delay]:
    return st.builds(
        lambda v: nir.Delay(delay=v),
        v=_vector_array_strategy(),
    )


def _threshold_strategy() -> st.SearchStrategy[nir.Threshold]:
    return st.builds(
        lambda v: nir.Threshold(threshold=v),
        v=_vector_array_strategy(),
    )


# Convolution and pool primitives are deliberately omitted from the
# default *node* strategy because they require coordinated weight /
# input_shape / stride / padding / dilation tuples and the upstream
# library performs its own shape inference at construction time. The
# round-trip property test exercises Conv2d and the pool primitives
# through the targeted shape-literal property tests
# (test_shape_properties.py) instead.

_NODE_STRATEGIES: dict[str, st.SearchStrategy[Any]] = {
    "IF": _if_strategy(),
    "LIF": _lif_strategy(),
    "LI": _li_strategy(),
    "CubaLIF": _cubalif_strategy(),
    "CubaLI": _cubali_strategy(),
    "I": _i_strategy(),
    "Linear": _linear_strategy(),
    "Affine": _affine_strategy(),
    "Scale": _scale_strategy(),
    "Flatten": _flatten_strategy(),
    "Delay": _delay_strategy(),
    "Threshold": _threshold_strategy(),
}


def node_strategy() -> st.SearchStrategy[Any]:
    """Strategy of a single :class:`nir.NIRNode` of any non-IO primitive.

    Every value emitted by this strategy is one of the documented
    Primitives that does *not* require coordinated structural
    parameters (see the Conv/Pool note above). The graph-level
    strategy adds an ``Input`` and an ``Output`` separately so every
    output graph satisfies Requirement 4.7.
    """
    return st.one_of(*_NODE_STRATEGIES.values())


# ---------------------------------------------------------------------------
# Graph strategy
# ---------------------------------------------------------------------------


@st.composite
def nir_graph_strategy(draw: st.DrawFn) -> nir.NIRGraph:
    """Strategy of small, valid :class:`nir.NIRGraph` instances.

    Every emitted graph contains:

    * exactly one ``Input`` node named ``in_<id>``;
    * exactly one ``Output`` node named ``out_<id>``;
    * 0 to 4 internal nodes drawn from :func:`node_strategy`;
    * 0 to 6 directed edges connecting the existing node identifiers
      (deduplicated so no ``(src, target)`` pair appears twice — the
      compiler rejects duplicate edges per Requirement 4.6).

    Internal nodes carry randomised metadata dicts produced by
    :func:`metadata_strategy`. The ``Input``/``Output`` nodes do *not*
    carry metadata because the upstream ``nir.Input``/``nir.Output``
    constructors install a default ``metadata={}`` and the round-trip
    helper compares metadata dicts under Python ``==``; keeping IO
    metadata empty avoids accidental divergence from upstream defaults.
    """
    in_name = "in_" + draw(identifier_strategy())
    out_name = "out_" + draw(identifier_strategy())
    while out_name == in_name:  # pragma: no cover — extremely rare
        out_name = "out_" + draw(identifier_strategy())

    in_dim = draw(st.integers(min_value=1, max_value=8))
    out_dim = draw(st.integers(min_value=1, max_value=8))
    nodes: dict[str, Any] = {
        in_name: nir.Input(input_type=np.asarray([in_dim], dtype=int)),
        out_name: nir.Output(output_type=np.asarray([out_dim], dtype=int)),
    }

    # Internal nodes — random count, random primitives.
    n_internal = draw(st.integers(min_value=0, max_value=4))
    used_names = {in_name, out_name}
    for _ in range(n_internal):
        name = draw(identifier_strategy())
        # Avoid name collisions; redraw up to a few times before giving up.
        attempts = 0
        while name in used_names and attempts < 10:
            name = draw(identifier_strategy())
            attempts += 1
        if name in used_names:
            continue
        used_names.add(name)
        node = draw(node_strategy())
        # Attach random metadata.
        meta = draw(metadata_strategy())
        if meta:
            node.metadata = dict(meta)
        nodes[name] = node

    # Edges: each edge is a (src, target) drawn from the existing
    # identifier list; deduplicated.
    name_list = list(nodes.keys())
    n_edges = draw(st.integers(min_value=0, max_value=6))
    edge_set: set[tuple[str, str]] = set()
    for _ in range(n_edges):
        src = draw(st.sampled_from(name_list))
        target = draw(st.sampled_from(name_list))
        edge_set.add((src, target))
    edges = list(edge_set)

    return nir.NIRGraph(nodes=nodes, edges=edges, type_check=False)


# ---------------------------------------------------------------------------
# Pipeline config (Train / Evaluate / Export)
# ---------------------------------------------------------------------------


@st.composite
def pipeline_config_strategy(draw: st.DrawFn) -> PipelineConfig:
    """Strategy emitting random :class:`PipelineConfig` instances.

    ``epochs`` is drawn unconditionally so the Train-anchor invariant
    ``render_pipeline_config`` enforces (any other Train field implies
    ``epochs is not None``) always holds — every generated config is
    renderable without hitting the ``ValueError`` guard.
    """
    from neurocnl.nir_cnl.grammar_tables import (
        loss_function_id_to_phrase,
        optimizer_id_to_phrase,
        training_strategy_id_to_phrase,
    )
    from neurocnl.nir_cnl.pipeline_config import PipelineConfig

    epochs = draw(st.integers(min_value=1, max_value=1000))
    learning_rate = draw(
        st.none() | st.floats(min_value=1e-6, max_value=1.0, allow_nan=False)
    )
    batch_size = draw(st.none() | st.integers(min_value=1, max_value=4096))
    optimizer = draw(st.none() | st.sampled_from(sorted(optimizer_id_to_phrase.keys())))
    training_strategy = draw(
        st.none() | st.sampled_from(sorted(training_strategy_id_to_phrase.keys()))
    )
    loss_function = draw(
        st.none() | st.sampled_from(sorted(loss_function_id_to_phrase.keys()))
    )
    # An Evaluate sentence's mere presence always forces
    # ``run_evaluation=True`` on extraction (Requirement: presence of
    # the record signals evaluation should run, independent of the
    # metric list) — so ``eval_metrics`` being set implies
    # ``run_evaluation=True`` in any config that is actually reachable
    # by parsing rendered CNL. Draw the two together so the generated
    # config stays in that reachable subspace; a config with
    # ``eval_metrics`` set but ``run_evaluation=None`` is not something
    # any render/parse round trip can reproduce.
    evaluation_present = draw(st.booleans())
    run_evaluation = True if evaluation_present else None
    eval_metrics = (
        draw(
            st.none()
            | st.lists(
                st.sampled_from(["accuracy", "loss", "precision", "recall"]),
                min_size=1,
                max_size=3,
                unique=True,
            ).map(tuple)
        )
        if evaluation_present
        else None
    )
    export_nir = draw(st.none() | st.just(True))
    generate_py_download = draw(st.none() | st.just(True))

    return PipelineConfig(
        epochs=epochs,
        learning_rate=learning_rate,
        batch_size=batch_size,
        optimizer=optimizer,
        training_strategy=training_strategy,
        loss_function=loss_function,
        run_evaluation=run_evaluation,
        eval_metrics=eval_metrics,
        export_nir=export_nir,
        generate_py_download=generate_py_download,
    )
