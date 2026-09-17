"""Tests for deployment_mode fidelity validation in nir_exporter."""

from __future__ import annotations

import pytest

from neurocnl.compile import CompileError
from neurocnl.export.nir_exporter import audit_deployment_mode
from neurocnl.ir import LearningRuleIR, NetworkIR


def test_online_learn_on_unsupported_backend_raises_compile_error() -> None:
    """audit_deployment_mode raises CompileError for online_learn on snntorch."""
    rule = LearningRuleIR(kind="stdp", deployment_mode="online_learn")
    ir = NetworkIR(learning_rules=[rule])

    with pytest.raises(CompileError) as exc_info:
        audit_deployment_mode(ir, "snntorch")

    assert "online_learn" in str(exc_info.value)
    assert exc_info.value.diagnostics
    diag = exc_info.value.diagnostics[0]
    assert diag.code == "unsupported_deployment_mode"
    assert diag.stage == "exportability"
