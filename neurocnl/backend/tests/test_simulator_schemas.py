"""Tests for the shared simulator Pydantic schemas.

Verifies round-trip serialisation of all models and checks that error payloads
conform to the same structured diagnostic shape used by validate/generate/export.
"""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from backend.app.schemas.simulators import (
    SimulatorCapability,
    SimulatorNIRSummary,
    SimulatorRunRequest,
    SimulatorRunResult,
    SimulatorStatus,
    StimulusSpec,
    SupportLevel,
)

# ---------------------------------------------------------------------------
# StimulusSpec
# ---------------------------------------------------------------------------


def test_stimulus_spec_round_trip() -> None:
    spec = StimulusSpec(
        type="spike_train",
        population="input",
        spikes={"0": [0, 10, 20], "1": [5, 15, 25]},
    )
    data = spec.model_dump()
    assert data["type"] == "spike_train"
    assert data["population"] == "input"
    assert data["spikes"]["0"] == [0, 10, 20]

    rebuilt = StimulusSpec.model_validate(data)
    assert rebuilt == spec


def test_stimulus_spec_rejects_wrong_type() -> None:
    with pytest.raises(ValidationError):
        StimulusSpec.model_validate({"type": "rate_coded", "population": "x", "spikes": {}})


# ---------------------------------------------------------------------------
# SimulatorCapability
# ---------------------------------------------------------------------------


def test_simulator_capability_round_trip() -> None:
    cap = SimulatorCapability(
        backend_name="lava_sim",
        display_name="Lava simulator",
        available=True,
        supported_nir_nodes=["Input", "Output", "LIF", "Linear"],
        unsupported_nir_nodes=[],
        approximate_semantics=["Delay"],
        max_timesteps=1000,
        supports_spike_output=True,
        supports_voltage_trace=False,
    )
    data = cap.model_dump()
    assert data["backend_name"] == "lava_sim"
    assert data["available"] is True
    assert data["unavailable_reason"] is None

    rebuilt = SimulatorCapability.model_validate(data)
    assert rebuilt == cap


def test_simulator_capability_unavailable() -> None:
    cap = SimulatorCapability(
        backend_name="snntorch_sim",
        display_name="snnTorch simulator",
        available=False,
        unavailable_reason="snntorch not installed",
        supported_nir_nodes=["LIF"],
        unsupported_nir_nodes=[],
        approximate_semantics=[],
        max_timesteps=500,
        supports_spike_output=True,
        supports_voltage_trace=False,
        requires_optional_dependency="snntorch",
    )
    assert cap.available is False
    assert cap.unavailable_reason is not None
    assert cap.requires_optional_dependency == "snntorch"


# ---------------------------------------------------------------------------
# SimulatorRunRequest
# ---------------------------------------------------------------------------


def test_run_request_defaults() -> None:
    req = SimulatorRunRequest(spec="The input MUST contain 2 neurons", backend_name="lava_sim")
    assert req.timesteps == 100
    assert req.seed == 1
    assert req.stimulus is None


def test_run_request_with_stimulus() -> None:
    req = SimulatorRunRequest(
        spec="CNL text",
        backend_name="snntorch_sim",
        timesteps=50,
        seed=42,
        stimulus=StimulusSpec(
            type="spike_train",
            population="input",
            spikes={"0": [1, 2, 3]},
        ),
    )
    data = req.model_dump()
    assert data["stimulus"]["population"] == "input"
    assert data["timesteps"] == 50


def test_run_request_rejects_zero_timesteps() -> None:
    with pytest.raises(ValidationError):
        SimulatorRunRequest(spec="x", backend_name="lava_sim", timesteps=0)


def test_run_request_rejects_too_many_timesteps() -> None:
    with pytest.raises(ValidationError):
        SimulatorRunRequest(spec="x", backend_name="lava_sim", timesteps=99_999)


# ---------------------------------------------------------------------------
# SimulatorRunResult
# ---------------------------------------------------------------------------


def test_run_result_round_trip() -> None:
    result = SimulatorRunResult(
        backend_name="lava_sim",
        status=SimulatorStatus.completed,
        support_level=SupportLevel.exact,
        timesteps=100,
        duration_seconds=0.02,
        spikes={"output": {"0": [10, 20], "1": [15, 25]}},
        voltages={},
        warnings=[],
        nir_summary=SimulatorNIRSummary(node_count=4, edge_count=3, unsupported_nodes=[]),
        metadata={"seed": 1, "runtime_mode": "preflight"},
    )
    data = result.model_dump()
    assert data["status"] == "completed"
    assert data["support_level"] == "exact"
    assert data["spikes"]["output"]["0"] == [10, 20]
    assert data["nir_summary"]["node_count"] == 4

    rebuilt = SimulatorRunResult.model_validate(data)
    assert rebuilt.backend_name == "lava_sim"
    assert rebuilt.nir_summary.edge_count == 3


def test_run_result_missing_dep_status() -> None:
    result = SimulatorRunResult(
        backend_name="lava_sim",
        status=SimulatorStatus.missing_dependency,
        support_level=SupportLevel.unsupported,
        timesteps=0,
        duration_seconds=0.0,
        nir_summary=SimulatorNIRSummary(node_count=0, edge_count=0),
        metadata={},
    )
    assert result.status == SimulatorStatus.missing_dependency
    assert result.spikes == {}
    assert result.warnings == []


def test_run_result_approximate_support() -> None:
    result = SimulatorRunResult(
        backend_name="snntorch_sim",
        status=SimulatorStatus.completed,
        support_level=SupportLevel.approximate,
        timesteps=50,
        duration_seconds=0.01,
        warnings=["nir.Delay is approximate"],
        nir_summary=SimulatorNIRSummary(node_count=3, edge_count=2),
        metadata={},
    )
    data = result.model_dump()
    assert data["support_level"] == "approximate"
    assert "nir.Delay is approximate" in data["warnings"]
