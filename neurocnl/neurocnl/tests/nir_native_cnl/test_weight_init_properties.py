"""Property-based tests for weight initialisation in ``NIR_Compiler._resolve_tensor``.

Properties implemented here:

* **Property 1** — Xavier bound invariant.
  Every element of a Xavier-initialised rank-2 array lies in ``[-a, a]``
  where ``a = sqrt(6.0 / (M + N))``
  (Requirements 2.1, 2.4, 9.1).
* **Property 2** — Kaiming bound invariant.
  Every element of a Kaiming-initialised rank-2 array lies in ``[-a, a]``
  where ``a = sqrt(3.0 / N)``
  (Requirements 3.1, 3.4, 9.2).
* **Property 3** — Determinism under same seed.
  Compiling the same record twice with the same seed yields bit-identical arrays
  (Requirements 4.1, 4.3, 7.1, 9.3).
* **Property 4** — dtype is always float64.
  Every initialised array has ``dtype == float64``
  (Requirements 1.2, 9.4).
* **Property 5** — Global numpy random state is not mutated.
  The legacy ``numpy.random`` module state is unchanged after any
  weight-initialisation compilation call
  (Requirements 1.3, 7.3, 9.5).
"""

from __future__ import annotations

from typing import Any

import numpy as np
from hypothesis import given, settings
from hypothesis import strategies as st

from neurocnl.nir_cnl.compiler import NIR_Compiler
from neurocnl.nir_cnl.ir_types import (
    ArraySpec,
    EvaluationConfigRecord,
    ExportConfigRecord,
    NetworkContainer,
    NIREdgeRecord,
    NIRNodeRecord,
    TrainingConfigRecord,
)

from ._weight_init_helpers import legacy_rng_state

_CompilerRecord = (
    NIRNodeRecord
    | NIREdgeRecord
    | NetworkContainer
    | TrainingConfigRecord
    | EvaluationConfigRecord
    | ExportConfigRecord
)

# ---------------------------------------------------------------------------
# Shared helper
# ---------------------------------------------------------------------------


def _make_linear_record(
    M: int,
    N: int,
    scheme: str,
    seed: int | None = None,
) -> NIRNodeRecord:
    """Build a minimal Linear ``NIRNodeRecord`` with an ``ArraySpec`` weight.

    No CNL text round-trip — this exercises the compiler materialisation
    stage in isolation following the pattern in ``test_shape_properties.py``.
    """
    metadata: dict[str, Any] = {"weight_init": scheme}
    if seed is not None:
        metadata["seed"] = seed
    return NIRNodeRecord(
        name="w1",
        primitive="Linear",
        params={"weight": ArraySpec(shape=(M, N))},
        metadata=metadata,
        line=1,
    )


def _compile_weight(
    M: int, N: int, scheme: str, seed: int | None = None
) -> np.ndarray[Any, Any]:
    """Compile a Linear node and return its ``weight`` array."""
    records: list[_CompilerRecord] = [
        NIRNodeRecord(
            name="inp",
            primitive="Input",
            params={"input_type": (N,)},
            metadata={},
            line=1,
        ),
        _make_linear_record(M, N, scheme, seed),
        NIRNodeRecord(
            name="out",
            primitive="Output",
            params={"output_type": (M,)},
            metadata={},
            line=3,
        ),
        NIREdgeRecord(src="inp", target="w1", line=4),
        NIREdgeRecord(src="w1", target="out", line=5),
    ]
    graph = NIR_Compiler().compile(records)
    weight: np.ndarray[Any, Any] = graph.nodes["w1"].weight
    return weight


# ---------------------------------------------------------------------------
# Property 1: Xavier bound invariant
# ---------------------------------------------------------------------------


# Feature: weight-init-option-b, Property 1: Xavier bound invariant
@given(
    M=st.integers(min_value=1, max_value=512),
    N=st.integers(min_value=1, max_value=512),
    seed=st.integers(min_value=0, max_value=2**32 - 1),
)
@settings(max_examples=100, deadline=None)
def test_property_1_xavier_bound_invariant(M: int, N: int, seed: int) -> None:
    """Every element of a Xavier-initialised array lies in ``[-a, a]``.

    **Validates: Requirements 2.1, 2.4, 9.1**
    """
    a = np.sqrt(6.0 / (M + N))
    weights = _compile_weight(M, N, "xavier", seed)

    assert weights.shape == (M, N), f"Expected shape ({M}, {N}), got {weights.shape}"
    assert np.all(weights >= -a) and np.all(weights <= a), (
        f"Xavier weights out of bound [-{a}, {a}] for shape ({M}, {N}): "
        f"min={weights.min()}, max={weights.max()}"
    )


# ---------------------------------------------------------------------------
# Property 2: Kaiming bound invariant
# ---------------------------------------------------------------------------


# Feature: weight-init-option-b, Property 2: Kaiming bound invariant
@given(
    M=st.integers(min_value=1, max_value=512),
    N=st.integers(min_value=1, max_value=512),
    seed=st.integers(min_value=0, max_value=2**32 - 1),
)
@settings(max_examples=100, deadline=None)
def test_property_2_kaiming_bound_invariant(M: int, N: int, seed: int) -> None:
    """Every element of a Kaiming-initialised array lies in ``[-a, a]``.

    **Validates: Requirements 3.1, 3.4, 9.2**
    """
    a = np.sqrt(3.0 / N)
    weights = _compile_weight(M, N, "kaiming", seed)

    assert weights.shape == (M, N), f"Expected shape ({M}, {N}), got {weights.shape}"
    assert np.all(weights >= -a) and np.all(weights <= a), (
        f"Kaiming weights out of bound [-{a}, {a}] for shape ({M}, {N}): "
        f"min={weights.min()}, max={weights.max()}"
    )


# ---------------------------------------------------------------------------
# Property 3: Determinism under same seed
# ---------------------------------------------------------------------------


# Feature: weight-init-option-b, Property 3: Determinism under same seed
@given(
    M=st.integers(min_value=1, max_value=512),
    N=st.integers(min_value=1, max_value=512),
    seed=st.integers(min_value=0, max_value=2**32 - 1),
    scheme=st.sampled_from(["xavier", "kaiming"]),
)
@settings(max_examples=100, deadline=None)
def test_property_3_determinism_same_seed(
    M: int, N: int, seed: int, scheme: str
) -> None:
    """Compiling the same record twice with the same seed yields identical arrays.

    Both compilations are independent; no shared state is expected between calls.
    The isolated ``numpy.random.default_rng(seed)`` per call guarantees that the
    same seed always produces the same sequence regardless of call order or
    global RNG state.

    **Validates: Requirements 4.1, 4.3, 7.1, 9.3**
    """
    w1 = _compile_weight(M, N, scheme, seed)
    w2 = _compile_weight(M, N, scheme, seed)

    assert numpy_array_equal(w1, w2), (
        f"Determinism violated for scheme={scheme!r}, shape=({M}, {N}), seed={seed}: "
        f"arrays differ.\nw1={w1}\nw2={w2}"
    )


def numpy_array_equal(a: np.ndarray[Any, Any], b: np.ndarray[Any, Any]) -> bool:
    """Thin wrapper around ``numpy.array_equal`` for clarity in assertions."""
    return np.array_equal(a, b)


# ---------------------------------------------------------------------------
# Property 4: dtype is always float64
# ---------------------------------------------------------------------------


# Feature: weight-init-option-b, Property 4: dtype is always float64
@given(
    M=st.integers(min_value=1, max_value=64),
    N=st.integers(min_value=1, max_value=64),
    scheme=st.sampled_from(["xavier", "kaiming"]),
)
@settings(max_examples=100, deadline=None)
def test_property_4_dtype_float64(M: int, N: int, scheme: str) -> None:
    """Every initialised weight array has ``dtype == float64``.

    **Validates: Requirements 1.2, 9.4**
    """
    weights = _compile_weight(M, N, scheme, seed=42)

    assert (
        weights.dtype == np.float64
    ), f"Expected dtype float64, got {weights.dtype} for scheme={scheme!r}, shape=({M}, {N})"


# ---------------------------------------------------------------------------
# Property 5: Global numpy random state is not mutated
# ---------------------------------------------------------------------------


# Feature: weight-init-option-b, Property 5: Global numpy random state not mutated
@given(
    M=st.integers(min_value=1, max_value=64),
    N=st.integers(min_value=1, max_value=64),
    scheme=st.sampled_from(["xavier", "kaiming"]),
    seed=st.integers(min_value=0, max_value=2**32 - 1),
)
@settings(max_examples=100, deadline=None)
def test_property_5_global_state_unchanged(
    M: int, N: int, scheme: str, seed: int
) -> None:
    """The legacy ``numpy.random`` module state is unchanged after compilation.

    Snapshots both the state name string and the state array before and after
    the compilation call, and asserts they are equal.

    **Validates: Requirements 1.3, 7.3, 9.5**
    """
    state_before = legacy_rng_state()
    _compile_weight(M, N, scheme, seed)
    state_after = legacy_rng_state()

    # state_before / state_after are tuples: (name_str, state_array, pos, has_gauss, cached_gauss)
    name_before, arr_before = state_before[0], state_before[1]
    name_after, arr_after = state_after[0], state_after[1]

    assert (
        name_before == name_after
    ), f"Global RNG state name changed: {name_before!r} → {name_after!r}"
    assert np.array_equal(
        arr_before, arr_after
    ), f"Global RNG state array mutated for scheme={scheme!r}, shape=({M}, {N}), seed={seed}"
