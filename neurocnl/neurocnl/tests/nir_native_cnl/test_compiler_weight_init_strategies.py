"""Unit tests for concrete weight-initialisation strategies in ``NIR_Compiler``.

Split from ``test_compiler_weight_init.py``: covers the default zero-fill
behaviour plus the Xavier and Kaiming strategies. Tests use ``NIRNodeRecord``
directly — no CNL text round-trip — to exercise the compiler's
materialisation stage in isolation.
"""

from __future__ import annotations

from typing import Any

import numpy as np

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

_CompilerRecord = (
    NIRNodeRecord
    | NIREdgeRecord
    | NetworkContainer
    | TrainingConfigRecord
    | EvaluationConfigRecord
    | ExportConfigRecord
)

from ._weight_init_helpers import (
    compile_conv1d,
    compile_linear,
    make_conv1d_record,
    make_linear_record,
)

# ---------------------------------------------------------------------------
# TestDefaultZeroFill
# ---------------------------------------------------------------------------


class TestDefaultZeroFill:
    """Tests for backward-compatible zero-fill default.

    When no ``weight_init`` key is present, or the value is empty or
    whitespace-only, ``_resolve_tensor`` SHALL materialise the parameter
    as ``numpy.zeros(shape, dtype=float)``.

    Requirement references: 1.1, 1.2
    """

    def _compile_zero_fill(
        self,
        shape: tuple[int, ...],
        metadata: dict[str, Any],
    ) -> np.ndarray[Any, Any]:
        """Helper: build a Linear record with given metadata and compile it."""
        records: list[_CompilerRecord] = [
            NIRNodeRecord(
                name="inp",
                primitive="Input",
                params={"input_type": (shape[1],)},
                metadata={},
                line=1,
            ),
            NIRNodeRecord(
                name="w1",
                primitive="Linear",
                params={"weight": ArraySpec(shape=shape)},
                metadata=metadata,
                line=2,
            ),
            NIRNodeRecord(
                name="out",
                primitive="Output",
                params={"output_type": (shape[0],)},
                metadata={},
                line=3,
            ),
            NIREdgeRecord(src="inp", target="w1", line=4),
            NIREdgeRecord(src="w1", target="out", line=5),
        ]
        graph = NIR_Compiler().compile(records)
        weight: np.ndarray[Any, Any] = graph.nodes["w1"].weight
        return weight

    def test_no_weight_init_produces_zeros(self) -> None:
        """No ``weight_init`` key → all elements are zero.

        _Validates: Requirement 1.1_
        """
        shape = (3, 4)
        result = self._compile_zero_fill(shape, metadata={})

        assert result.shape == shape
        assert np.all(
            result == 0.0
        ), f"Expected all-zero array for shape {shape}, got {result}"

    def test_empty_weight_init_produces_zeros(self) -> None:
        """``weight_init: ""`` (empty string) → all elements are zero.

        _Validates: Requirement 1.1_
        """
        shape = (5, 2)
        result = self._compile_zero_fill(shape, metadata={"weight_init": ""})

        assert result.shape == shape
        assert np.all(
            result == 0.0
        ), f"Expected all-zero array for empty weight_init, got {result}"

    def test_whitespace_weight_init_produces_zeros(self) -> None:
        """``weight_init: "  "`` (whitespace-only) → all elements are zero.

        _Validates: Requirement 1.1_
        """
        shape = (4, 6)
        result = self._compile_zero_fill(shape, metadata={"weight_init": "  "})

        assert result.shape == shape
        assert np.all(
            result == 0.0
        ), f"Expected all-zero array for whitespace weight_init, got {result}"

    def test_zero_fill_dtype_is_float64(self) -> None:
        """Zero-fill materialisation produces a ``float64`` array.

        _Validates: Requirement 1.2_
        """
        shape = (3, 3)
        result = self._compile_zero_fill(shape, metadata={})

        assert result.dtype == np.float64, f"Expected dtype float64, got {result.dtype}"


# ---------------------------------------------------------------------------
# TestXavierInitialisation
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# TestXavierInitialisation
# ---------------------------------------------------------------------------


class TestXavierInitialisation:
    """Tests for Xavier (Glorot) uniform weight initialisation.

    Requirement references: 1.2, 2.1, 2.3, 2.4, 2.5, 5.2
    """

    # ── test_xavier_rank2_bound_small_matrix ─────────────────────────────

    def test_xavier_rank2_bound_small_matrix(self) -> None:
        """All weights lie in [-a, a] for a small rank-2 shape.

        **Validates: Requirements 2.1, 2.4**
        Shape (4, 8): fan_in=8, fan_out=4 → a = sqrt(6/(8+4)) = sqrt(0.5).
        """
        M, N = 4, 8
        record = make_linear_record(M, N, weight_init="xavier", seed=0)
        weight = compile_linear(record)

        fan_in = N
        fan_out = M
        a = np.sqrt(6.0 / (fan_in + fan_out))

        assert weight.shape == (
            M,
            N,
        ), f"Expected weight shape ({M}, {N}), got {weight.shape}"
        assert np.all(weight >= -a) and np.all(
            weight <= a
        ), f"Some weights lie outside [-{a}, {a}]: min={weight.min()}, max={weight.max()}"

    # ── test_xavier_rank2_bound_large_matrix ─────────────────────────────

    def test_xavier_rank2_bound_large_matrix(self) -> None:
        """Variance is within 5 % of a²/3 for shape (100, 100).

        **Validates: Requirement 2.5**
        fan_in=100, fan_out=100 → a = sqrt(6/200) = sqrt(0.03).
        Theoretical variance of U(-a,a) = a²/3.
        """
        M, N = 100, 100
        record = make_linear_record(M, N, weight_init="xavier", seed=42)
        weight = compile_linear(record)

        fan_in = N
        fan_out = M
        a = np.sqrt(6.0 / (fan_in + fan_out))
        expected_variance = (a**2) / 3.0

        actual_variance = float(np.var(weight))
        relative_error = abs(actual_variance - expected_variance) / expected_variance

        assert relative_error <= 0.05, (
            f"Variance relative error {relative_error:.4f} exceeds 5 %; "
            f"expected ~{expected_variance:.6f}, got {actual_variance:.6f}"
        )
        # Also check bounds hold
        assert np.all(weight >= -a) and np.all(
            weight <= a
        ), f"Some weights exceed bound [-{a}, {a}]: min={weight.min()}, max={weight.max()}"

    # ── test_xavier_rank3_bound ───────────────────────────────────────────

    def test_xavier_rank3_bound(self) -> None:
        """Rank-3 tensor: fan derivation uses receptive_field_size=kernel.

        **Validates: Requirement 2.3**
        Shape (8, 4, 3): receptive_field_size=3,
        fan_in = 4*3 = 12, fan_out = 8*3 = 24 → a = sqrt(6/(12+24)).
        Every weight must lie in [-a, a].
        """
        out_ch, in_ch, kernel = 8, 4, 3
        record = make_conv1d_record(out_ch, in_ch, kernel, weight_init="xavier", seed=0)
        weight = compile_conv1d(record)

        receptive_field_size = kernel
        fan_in = in_ch * receptive_field_size
        fan_out = out_ch * receptive_field_size
        a = np.sqrt(6.0 / (fan_in + fan_out))

        assert weight.shape == (
            out_ch,
            in_ch,
            kernel,
        ), f"Expected weight shape ({out_ch}, {in_ch}, {kernel}), got {weight.shape}"
        assert np.all(weight >= -a) and np.all(
            weight <= a
        ), f"Some conv1d weights lie outside [-{a}, {a}]: min={weight.min()}, max={weight.max()}"

    # ── test_xavier_case_insensitive ──────────────────────────────────────

    def test_xavier_case_insensitive(self) -> None:
        """``"XAVIER"`` is accepted and produces non-zero weights.

        **Validates: Requirement 5.2**
        """
        M, N = 4, 4
        record = make_linear_record(M, N, weight_init="XAVIER", seed=7)
        weight = compile_linear(record)

        # Must compile without error and not be all zeros
        assert weight.shape == (M, N)
        fan_in, fan_out = N, M
        a = np.sqrt(6.0 / (fan_in + fan_out))
        assert np.all(weight >= -a) and np.all(
            weight <= a
        ), f"Weights from 'XAVIER' lie outside bound: min={weight.min()}, max={weight.max()}"

    # ── test_xavier_whitespace_trimmed ────────────────────────────────────

    def test_xavier_whitespace_trimmed(self) -> None:
        """``"  xavier  "`` is accepted (whitespace is stripped).

        **Validates: Requirement 5.2**
        """
        M, N = 4, 4
        record = make_linear_record(M, N, weight_init="  xavier  ", seed=7)
        weight = compile_linear(record)

        assert weight.shape == (M, N)
        fan_in, fan_out = N, M
        a = np.sqrt(6.0 / (fan_in + fan_out))
        assert np.all(weight >= -a) and np.all(
            weight <= a
        ), f"Weights from '  xavier  ' lie outside bound: min={weight.min()}, max={weight.max()}"

    # ── test_xavier_dtype_is_float64 ──────────────────────────────────────

    def test_xavier_dtype_is_float64(self) -> None:
        """Xavier-initialised weight array has dtype float64.

        **Validates: Requirement 1.2**
        """
        M, N = 6, 5
        record = make_linear_record(M, N, weight_init="xavier", seed=0)
        weight = compile_linear(record)

        assert weight.dtype == np.float64, f"Expected dtype float64, got {weight.dtype}"


# ---------------------------------------------------------------------------
# TestArrayValuesPassthrough
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# TestKaimingInitialisation
# ---------------------------------------------------------------------------


class TestKaimingInitialisation:
    """Tests for Kaiming (He) uniform weight initialisation.

    Exercises Requirements 1.2, 3.1, 3.3, 3.4, 3.5, and 5.3:
    bound correctness, rank-3 fan_in derivation, variance convergence,
    case-insensitive scheme name, and float64 dtype.
    """

    def test_kaiming_rank2_bound_small_matrix(self) -> None:
        """All weights are within the Kaiming bound ``[-a, a]`` for a small shape.

        For rank-2 shape ``(M, N)``, ``fan_in = N`` and
        ``a = sqrt(3.0 / fan_in)``.

        _Validates: Requirement 3.4_
        """
        M, N = 6, 8
        fan_in = N
        a = np.sqrt(3.0 / fan_in)

        record = make_linear_record(M, N, weight_init="kaiming", seed=0)
        result = compile_linear(record)

        assert result.shape == (M, N)
        assert np.all(result >= -a) and np.all(result <= a), (
            f"Some weights outside Kaiming bound [-{a}, {a}] for shape ({M},{N}).\n"
            f"min={result.min()}, max={result.max()}"
        )

    def test_kaiming_rank2_bound_large_matrix(self) -> None:
        """Variance of a 100×100 Kaiming-initialised matrix is within 5 % of ``a²/3``.

        For shape ``(100, 100)``: ``fan_in = 100``, ``a = sqrt(3.0 / 100)``.
        Expected variance = ``a² / 3 = 1.0 / 100 = 0.01``.

        _Validates: Requirement 3.5_
        """
        M, N = 100, 100
        fan_in = N
        a = np.sqrt(3.0 / fan_in)
        expected_var = (a**2) / 3.0

        record = make_linear_record(M, N, weight_init="kaiming", seed=7)
        result = compile_linear(record)

        actual_var = float(np.var(result))
        rel_err = abs(actual_var - expected_var) / expected_var

        assert rel_err <= 0.05, (
            f"Variance {actual_var:.6f} deviates from expected {expected_var:.6f} "
            f"by {rel_err * 100:.2f}% (> 5%) for Kaiming shape ({M},{N})."
        )

    def test_kaiming_rank3_bound(self) -> None:
        """Rank-3 Kaiming tensor uses ``fan_in = shape[1] * shape[2]``.

        For shape ``(8, 4, 3)``: ``receptive_field_size = shape[2] = 3``,
        ``fan_in = shape[1] * 3 = 12``, ``a = sqrt(3.0 / 12)``.

        _Validates: Requirement 3.3_
        """
        out_ch, in_ch, kernel = 8, 4, 3
        fan_in = in_ch * kernel  # = 12
        a = np.sqrt(3.0 / fan_in)

        record = make_conv1d_record(
            out_ch, in_ch, kernel, weight_init="kaiming", seed=1
        )
        result = compile_conv1d(record)

        assert result.shape == (
            out_ch,
            in_ch,
            kernel,
        ), f"Expected shape ({out_ch}, {in_ch}, {kernel}), got {result.shape}"
        assert np.all(result >= -a) and np.all(result <= a), (
            f"Some rank-3 Kaiming weights outside bound [-{a:.6f}, {a:.6f}].\n"
            f"min={result.min():.6f}, max={result.max():.6f}"
        )

    def test_kaiming_case_insensitive(self) -> None:
        """``"KAIMING"`` (upper-case) is accepted and produces valid initialisation.

        _Validates: Requirement 5.3_
        """
        M, N = 4, 4
        fan_in = N
        a = np.sqrt(3.0 / fan_in)

        record = make_linear_record(M, N, weight_init="KAIMING", seed=99)
        result = compile_linear(record)

        assert result.shape == (M, N)
        assert np.all(result >= -a) and np.all(result <= a), (
            f"Weights outside Kaiming bound after upper-case scheme name.\n"
            f"min={result.min()}, max={result.max()}"
        )
        # Must not be all-zeros (should be initialised, not zero-filled).
        assert not np.all(
            result == 0.0
        ), '"KAIMING" produced an all-zero array — case-insensitive path is not being applied.'

    def test_kaiming_dtype_is_float64(self) -> None:
        """Kaiming-initialised arrays have ``dtype`` equal to ``float64``.

        _Validates: Requirement 1.2_
        """
        record = make_linear_record(5, 7, weight_init="kaiming", seed=3)
        result = compile_linear(record)

        assert (
            result.dtype == np.float64
        ), f"Expected dtype float64 for Kaiming init, got {result.dtype}"


# ---------------------------------------------------------------------------
# TestDiagnosticErrors
# ---------------------------------------------------------------------------
