"""Diagnostic and passthrough tests for weight-initialisation in ``NIR_Compiler``.

Split from ``test_compiler_weight_init.py``: covers ``ArrayValues``
passthrough (weight_init must not override explicit values) and the
``CompileError`` diagnostics raised for invalid ``weight_init``/``seed``
metadata.
"""

from __future__ import annotations

import numpy as np
import pytest

from neurocnl.compile import CompileError
from neurocnl.nir_cnl.compiler import NIR_Compiler
from neurocnl.nir_cnl.ir_types import (
    ArraySpec,
    ArrayValues,
    EvaluationConfigRecord,
    ExportConfigRecord,
    NetworkContainer,
    NIREdgeRecord,
    NIRNodeRecord,
    TrainingConfigRecord,
)

from ._weight_init_helpers import compile_linear, make_linear_record

_CompilerRecord = (
    NIRNodeRecord
    | NIREdgeRecord
    | NetworkContainer
    | TrainingConfigRecord
    | EvaluationConfigRecord
    | ExportConfigRecord
)


# ---------------------------------------------------------------------------
# TestArrayValuesPassthrough
# ---------------------------------------------------------------------------


class TestArrayValuesPassthrough:
    """Tests for Requirement 5.5: explicit-values arrays are never overridden.

    When a ``NIRNodeRecord`` carries an ``ArrayValues`` parameter (with
    explicit numeric values already supplied), the compiler SHALL return
    those exact values regardless of any ``weight_init`` metadata that is
    also present on the same record.
    """

    def test_arrayvalues_not_overridden_by_weight_init(self) -> None:
        """``ArrayValues`` with ``weight_init`` metadata set is returned as-is.

        The compiled weight must match the explicit values provided in the
        ``ArrayValues`` instance, not a random draw from the requested
        initialisation scheme.

        _Validates: Requirement 5.5_
        """
        shape = (2, 3)
        explicit_values = [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]
        expected = np.array([[1, 2, 3], [4, 5, 6]], dtype=float)

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
                params={
                    "weight": ArrayValues(
                        shape=shape,
                        values=tuple(explicit_values),
                    )
                },
                metadata={"weight_init": "xavier"},
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
        result_weight = graph.nodes["w1"].weight

        assert np.array_equal(
            result_weight, expected
        ), f"Expected ArrayValues passthrough {expected!r}, got {result_weight!r}"


# ---------------------------------------------------------------------------
# TestRNGIsolation
# ---------------------------------------------------------------------------


# ---------------------------------------------------------------------------
# TestDiagnosticErrors
# ---------------------------------------------------------------------------


class TestDiagnosticErrors:
    """Tests for diagnostic / error-raising behaviour.

    Covers Requirements 2.6, 2.7, 3.6, 3.7, 4.7, 6.1, 6.2, 6.3, 6.5.

    Several tests call ``_resolve_tensor`` directly so they can exercise
    error paths that are unreachable via the full compiler pipeline because
    an earlier validation stage (e.g. shape-rank check) fires first.
    """

    # -- invalid weight_init --------------------------------------------------

    def test_invalid_weight_init_raises(self) -> None:
        """Unsupported ``weight_init`` value raises ``CompileError`` with
        ``code="invalid_value"``.

        _Validates: Requirement 2.6_
        """
        record = make_linear_record(4, 4, weight_init="normal", seed=0)
        with pytest.raises(CompileError) as exc_info:
            compile_linear(record)

        diag = exc_info.value.diagnostics[0]
        assert (
            diag.code == "invalid_value"
        ), f"Expected code='invalid_value', got {diag.code!r}"

    def test_invalid_weight_init_message_content(self) -> None:
        """Diagnostic message for invalid ``weight_init`` includes the raw
        value and lists the accepted alternatives.

        _Validates: Requirement 6.1_
        """
        record = make_linear_record(4, 4, weight_init="UNIFORM", seed=0)
        with pytest.raises(CompileError) as exc_info:
            compile_linear(record)

        diag = exc_info.value.diagnostics[0]
        msg = diag.message.lower()
        # Raw offending value must appear in the message.
        assert (
            "uniform" in msg
        ), f"Expected offending value 'UNIFORM' in message, got: {diag.message!r}"
        # Accepted alternatives must be listed.
        assert (
            "xavier" in msg
        ), f"Expected 'xavier' listed as accepted alternative, got: {diag.message!r}"
        assert (
            "kaiming" in msg
        ), f"Expected 'kaiming' listed as accepted alternative, got: {diag.message!r}"

    # -- invalid seed ---------------------------------------------------------

    def test_invalid_seed_string_raises(self) -> None:
        """``seed: "abc"`` (non-integer string) raises ``CompileError``.

        _Validates: Requirements 4.7, 6.2_
        """
        record = NIRNodeRecord(
            name="lin1",
            primitive="Linear",
            params={"weight": ArraySpec(shape=(4, 4))},
            metadata={"weight_init": "xavier", "seed": "abc"},
            line=1,
        )
        with pytest.raises(CompileError) as exc_info:
            compile_linear(record)

        diag = exc_info.value.diagnostics[0]
        assert (
            diag.code == "invalid_value"
        ), f"Expected code='invalid_value', got {diag.code!r}"

    def test_invalid_seed_negative_raises(self) -> None:
        """``seed: -1`` (negative integer) raises ``CompileError``.

        _Validates: Requirement 4.7_
        """
        record = NIRNodeRecord(
            name="lin1",
            primitive="Linear",
            params={"weight": ArraySpec(shape=(4, 4))},
            metadata={"weight_init": "xavier", "seed": -1},
            line=1,
        )
        with pytest.raises(CompileError) as exc_info:
            compile_linear(record)

        diag = exc_info.value.diagnostics[0]
        assert (
            diag.code == "invalid_value"
        ), f"Expected code='invalid_value', got {diag.code!r}"

    def test_invalid_seed_float_raises(self) -> None:
        """``seed: 1.5`` (non-integer float) raises ``CompileError``.

        Requirement 4.7 lists "float" explicitly as an invalid seed type.
        The compiler must reject float values even when they could be
        truncated to an integer.

        _Validates: Requirement 4.7_
        """
        record = NIRNodeRecord(
            name="lin1",
            primitive="Linear",
            params={"weight": ArraySpec(shape=(4, 4))},
            metadata={"weight_init": "xavier", "seed": 1.5},
            line=1,
        )
        with pytest.raises(CompileError) as exc_info:
            compile_linear(record)

        diag = exc_info.value.diagnostics[0]
        assert (
            diag.code == "invalid_value"
        ), f"Expected code='invalid_value', got {diag.code!r}"

    # -- ordering: weight_init checked before seed ----------------------------

    def test_weight_init_checked_before_seed(self) -> None:
        """When both ``weight_init`` and ``seed`` are invalid, only the
        ``weight_init`` error is raised (weight_init is evaluated first).

        _Validates: Requirement 6.5_
        """
        record = NIRNodeRecord(
            name="lin1",
            primitive="Linear",
            params={"weight": ArraySpec(shape=(4, 4))},
            metadata={"weight_init": "bogus", "seed": "bad"},
            line=1,
        )
        with pytest.raises(CompileError) as exc_info:
            compile_linear(record)

        # There must be exactly one diagnostic, and it must be about
        # weight_init (the message mentions the unsupported value 'bogus').
        diags = exc_info.value.diagnostics
        assert (
            len(diags) == 1
        ), f"Expected exactly 1 diagnostic, got {len(diags)}: {diags}"
        msg = diags[0].message.lower()
        assert (
            "bogus" in msg
        ), f"Expected weight_init value 'bogus' in message, got: {diags[0].message!r}"
        # Seed error must NOT be present.
        assert "seed" not in msg, (
            f"Seed error must not appear when weight_init error fires first; "
            f"got: {diags[0].message!r}"
        )

    # -- rank-1 guard ---------------------------------------------------------

    def test_rank1_xavier_raises(self) -> None:
        """Shape ``(5,)`` + ``weight_init="xavier"`` raises ``CompileError``.

        ``_validate_shape_rank`` fires for rank != 2 before reaching the
        weight_init path in the full-compiler pipeline, so we call
        ``_resolve_tensor`` directly with ``expected_rank=1`` to bypass
        the rank-mismatch check and confirm the weight_init rank guard.

        _Validates: Requirement 2.7_
        """
        from neurocnl.nir_cnl.compiler import _resolve_tensor

        record = NIRNodeRecord(
            name="w1",
            primitive="Linear",
            params={"weight": ArraySpec(shape=(5,))},
            metadata={"weight_init": "xavier"},
            line=1,
        )
        with pytest.raises(CompileError) as exc_info:
            _resolve_tensor(
                ArraySpec(shape=(5,)),
                expected_rank=1,  # bypass shape_rank_mismatch check
                primitive="Linear",
                arg_name="weight",
                line=1,
                record=record,
            )

        diag = exc_info.value.diagnostics[0]
        assert (
            diag.code == "invalid_value"
        ), f"Expected code='invalid_value', got {diag.code!r}"
        assert (
            "rank" in diag.message.lower()
        ), f"Expected 'rank' in message, got: {diag.message!r}"

    def test_rank1_kaiming_raises(self) -> None:
        """Shape ``(5,)`` + ``weight_init="kaiming"`` raises ``CompileError``.

        Same approach as ``test_rank1_xavier_raises`` — call
        ``_resolve_tensor`` directly with ``expected_rank=1``.

        _Validates: Requirement 3.6_
        """
        from neurocnl.nir_cnl.compiler import _resolve_tensor

        record = NIRNodeRecord(
            name="w1",
            primitive="Linear",
            params={"weight": ArraySpec(shape=(5,))},
            metadata={"weight_init": "kaiming"},
            line=1,
        )
        with pytest.raises(CompileError) as exc_info:
            _resolve_tensor(
                ArraySpec(shape=(5,)),
                expected_rank=1,  # bypass shape_rank_mismatch check
                primitive="Linear",
                arg_name="weight",
                line=1,
                record=record,
            )

        diag = exc_info.value.diagnostics[0]
        assert (
            diag.code == "invalid_value"
        ), f"Expected code='invalid_value', got {diag.code!r}"
        assert (
            "rank" in diag.message.lower()
        ), f"Expected 'rank' in message, got: {diag.message!r}"

    # -- zero fan_in ----------------------------------------------------------

    def test_zero_fan_in_kaiming_raises(self) -> None:
        """Degenerate shape where ``fan_in`` is zero raises ``CompileError``.

        ``_validate_shape_dims`` blocks any shape dimension < 1 in the
        normal pipeline, so ``fan_in == 0`` cannot occur via the public
        compile path with a valid ``ArraySpec``.  We test this guard by
        calling ``_resolve_tensor`` directly while bypassing
        ``_validate_shape_dims`` via monkeypatching.

        Shape ``(4, 0, 3)`` → ``fan_in = shape[1] * shape[2] = 0``.

        _Validates: Requirement 3.7_
        """
        from unittest.mock import patch

        from neurocnl.nir_cnl import param_resolution as param_resolution_module

        degenerate_shape = (4, 0, 3)
        record = NIRNodeRecord(
            name="w1",
            primitive="Linear",
            params={"weight": ArraySpec(shape=degenerate_shape)},
            metadata={"weight_init": "kaiming"},
            line=1,
        )

        # Patch _validate_shape_dims to be a no-op so we reach the fan_in check.
        with (
            patch.object(
                param_resolution_module, "_validate_shape_dims", return_value=None
            ),
            pytest.raises(CompileError) as exc_info,
        ):
            param_resolution_module._resolve_tensor(
                ArraySpec(shape=degenerate_shape),
                expected_rank=3,
                primitive="Linear",
                arg_name="weight",
                line=1,
                record=record,
            )

        diag = exc_info.value.diagnostics[0]
        assert (
            diag.code == "invalid_value"
        ), f"Expected code='invalid_value', got {diag.code!r}"
        assert (
            "fan_in" in diag.message.lower()
        ), f"Expected 'fan_in' in message, got: {diag.message!r}"

    # -- line number in diagnostic --------------------------------------------

    def test_line_number_in_diagnostic(self) -> None:
        """Diagnostic carries the source line number from ``record.line``.

        _Validates: Requirement 6.3_
        """
        from neurocnl.nir_cnl.compiler import _resolve_tensor

        line_number = 7
        record = NIRNodeRecord(
            name="w1",
            primitive="Linear",
            params={"weight": ArraySpec(shape=(4, 4))},
            metadata={"weight_init": "bad_scheme"},
            line=line_number,
        )
        with pytest.raises(CompileError) as exc_info:
            _resolve_tensor(
                ArraySpec(shape=(4, 4)),
                expected_rank=2,
                primitive="Linear",
                arg_name="weight",
                line=line_number,
                record=record,
            )

        diag = exc_info.value.diagnostics[0]
        assert (
            diag.line == line_number
        ), f"Expected diagnostic line={line_number}, got {diag.line!r}"


# ---------------------------------------------------------------------------
# TestIntegrationSnnTorchActivity
# ---------------------------------------------------------------------------
