"""Tests for the Neurochip PYNQ SITL verification service and router endpoint.

All tests run without the ``pynq`` library — PYNQBackend falls back to
PynqSimulator automatically.
"""

from __future__ import annotations

from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from neurochip.app.main import app
from neurochip.app.services.pynq_backend import PYNQBackend
from neurochip.app.services.pynq_sitl_verifier import (
    SITLStepResult,
    SITLStimulusCase,
    SITLVerificationConfig,
    SITLVerificationReport,
    _build_default_cases,
    run_sitl_verification,
)

client = TestClient(app)


# ---------------------------------------------------------------------------
# Default cases
# ---------------------------------------------------------------------------


class TestDefaultCases:
    def test_five_default_cases(self):
        cases = _build_default_cases(2)
        assert len(cases) == 5

    def test_cases_are_whole_input_frames(self):
        """The engine consumes one word per input neuron per timestep.

        A fixed list of spike *indices*, as overlay-v1's defaults used, is
        either the wrong length or silently means something else.
        """
        for case in _build_default_cases(4):
            assert len(case.input_spikes) == 4 * case.timesteps

    def test_no_expected_output_by_default(self):
        """Default verification measures liveness and latency, not accuracy."""
        for case in _build_default_cases(2):
            assert case.expected_output_spikes is None


# ---------------------------------------------------------------------------
# run_sitl_verification — service unit tests
# ---------------------------------------------------------------------------


def _configured_backend(weights: list[float] | None = None) -> PYNQBackend:
    backend = PYNQBackend(bitstream_path="snn_overlay.bit")
    backend.load_overlay()
    backend.configure(
        weights=weights or [2.0, 0.5],
        config={},
        layers=[
            {
                "input_size": 1,
                "output_size": 2,
                "weight_offset": 0,
                "threshold": 1,
                "leak_shift": 0,
                "refractory": 0,
            }
        ],
    )
    return backend


class TestRunSITLVerification:
    def test_default_cases_all_pass_no_expected(self):
        backend = _configured_backend()
        report = run_sitl_verification(backend)

        assert isinstance(report, SITLVerificationReport)
        assert report.total_cases == 5
        assert report.passed_cases == 5
        assert report.passed is True

    def test_custom_cases_used(self):
        backend = _configured_backend()
        cases = [
            SITLStimulusCase(label="a", input_spikes=[0]),
            SITLStimulusCase(label="b", input_spikes=[1]),
        ]
        cfg = SITLVerificationConfig(stimulus_cases=cases)
        report = run_sitl_verification(backend, cfg)

        assert report.total_cases == 2
        assert len(report.steps) == 2

    def test_step_fields_populated(self):
        backend = _configured_backend()
        cases = [SITLStimulusCase(label="t", input_spikes=[0])]
        report = run_sitl_verification(backend, SITLVerificationConfig(stimulus_cases=cases))

        step = report.steps[0]
        assert isinstance(step, SITLStepResult)
        assert step.label == "t"
        assert isinstance(step.output_spikes, list)
        assert step.execution_time_us >= 0.0

    def test_timing_stats(self):
        backend = _configured_backend()
        report = run_sitl_verification(backend)

        assert report.mean_exec_us >= 0.0
        assert report.max_exec_us >= report.mean_exec_us

    def test_raises_when_not_configured(self):
        backend = PYNQBackend(bitstream_path="snn_overlay.bit")
        backend.load_overlay()
        # Not configured yet
        with pytest.raises(RuntimeError, match="configured"):
            run_sitl_verification(backend)

    def test_correct_expected_match(self):
        """A supra-threshold input frame fires; the expected frame matches."""
        backend = _configured_backend(weights=[2.0, 2.0])
        cases = [
            SITLStimulusCase(
                label="fire_0",
                # One word per input neuron; both outputs are driven.
                input_spikes=[1],
                expected_output_spikes=[1, 1],
            )
        ]
        report = run_sitl_verification(backend, SITLVerificationConfig(stimulus_cases=cases))
        assert report.steps[0].passed is True

    def test_wrong_expected_fails(self):
        """Expected output [99] while backend fires [0]; step must fail."""
        backend = _configured_backend(weights=[2.0])
        cases = [
            SITLStimulusCase(
                label="mismatch",
                input_spikes=[0],
                expected_output_spikes=[99],
            )
        ]
        report = run_sitl_verification(backend, SITLVerificationConfig(stimulus_cases=cases))
        assert report.steps[0].passed is False
        assert report.passed is False

    def test_summary_string(self):
        backend = _configured_backend()
        report = run_sitl_verification(backend)
        assert "PASS" in report.summary or "FAIL" in report.summary
        assert "cases" in report.summary

    def test_to_dict(self):
        backend = _configured_backend()
        report = run_sitl_verification(backend)
        d = report.to_dict()
        assert "passed" in d
        assert "steps" in d
        assert isinstance(d["steps"], list)


# ---------------------------------------------------------------------------
# /hardware/pynq/verify — router endpoint tests
# ---------------------------------------------------------------------------


class TestVerifyEndpoint:
    def test_verify_with_weights(self):
        response = client.post(
            "/hardware/pynq/verify",
            json={
                "weights": [2.0, 0.5],
                "layers": [
                    {
                        "input_size": 1,
                        "output_size": 2,
                        "weight_offset": 0,
                        "threshold": 1,
                        "leak_shift": 0,
                        "refractory": 0,
                    }
                ],
                "config": {},
            },
            headers={"X-API-Key": "test_key"},
        )
        assert response.status_code == 200
        body = response.json()
        assert "passed" in body
        assert "total_cases" in body
        assert body["total_cases"] == 5
        assert "steps" in body
        assert len(body["steps"]) == 5

    def test_verify_uses_existing_backend(self):
        # Deploy first
        client.post(
            "/hardware/pynq/deploy",
            json={
                "weights": [2.0],
                "layers": [
                    {
                        "input_size": 1,
                        "output_size": 1,
                        "weight_offset": 0,
                        "threshold": 1,
                        "leak_shift": 0,
                        "refractory": 0,
                    }
                ],
                "config": {},
            },
            headers={"X-API-Key": "test_key"},
        )
        response = client.post(
            "/hardware/pynq/verify",
            json={},
            headers={"X-API-Key": "test_key"},
        )
        assert response.status_code == 200
        assert response.json()["total_cases"] == 5

    def test_verify_without_deploy_or_weights_returns_400(self):
        with patch("neurochip.app.routers.pynq.backend_instance", None):
            response = client.post(
                "/hardware/pynq/verify",
                json={},
                headers={"X-API-Key": "test_key"},
            )
            assert response.status_code == 400
            assert "No backend deployed" in response.json()["detail"]

    def test_verify_with_custom_stimulus_cases(self):
        response = client.post(
            "/hardware/pynq/verify",
            json={
                "weights": [2.0],
                "layers": [
                    {
                        "input_size": 1,
                        "output_size": 1,
                        "weight_offset": 0,
                        "threshold": 1,
                        "leak_shift": 0,
                        "refractory": 0,
                    }
                ],
                "config": {},
                "stimulus_cases": [
                    # One input word per neuron per timestep.
                    {"label": "s1", "input_spikes": [1], "timesteps": 1},
                    {"label": "s2", "input_spikes": [1, 0], "timesteps": 2},
                ],
            },
            headers={"X-API-Key": "test_key"},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["total_cases"] == 2
        assert body["steps"][0]["label"] == "s1"
        assert body["steps"][1]["label"] == "s2"

    def test_verify_with_expected_output_pass(self):
        """weight=2.0 > threshold=1.0 → neuron 0 fires; expect [0] should pass."""
        response = client.post(
            "/hardware/pynq/verify",
            json={
                "weights": [2.0],
                "layers": [
                    {
                        "input_size": 1,
                        "output_size": 1,
                        "weight_offset": 0,
                        "threshold": 1,
                        "leak_shift": 0,
                        "refractory": 0,
                    }
                ],
                "config": {},
                "stimulus_cases": [
                    {
                        "label": "fire",
                        "input_spikes": [1],
                        "expected_output_spikes": [1],
                    }
                ],
            },
            headers={"X-API-Key": "test_key"},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["passed"] is True
        assert body["steps"][0]["passed"] is True

    def test_verify_with_expected_output_fail(self):
        """A sub-threshold weight does not fire, so expecting a spike fails."""
        response = client.post(
            "/hardware/pynq/verify",
            json={
                "weights": [0.0],
                "layers": [
                    {
                        "input_size": 1,
                        "output_size": 1,
                        "weight_offset": 0,
                        "threshold": 10,
                        "leak_shift": 0,
                        "refractory": 0,
                    }
                ],
                "config": {},
                "stimulus_cases": [
                    {
                        "label": "no_fire",
                        "input_spikes": [1],
                        "expected_output_spikes": [1],
                    }
                ],
            },
            headers={"X-API-Key": "test_key"},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["passed"] is False
        assert body["steps"][0]["passed"] is False

    def test_verify_response_has_timing(self):
        response = client.post(
            "/hardware/pynq/verify",
            json={
                "weights": [1.0],
                "layers": [
                    {
                        "input_size": 1,
                        "output_size": 1,
                        "weight_offset": 0,
                        "threshold": 1,
                        "leak_shift": 0,
                        "refractory": 0,
                    }
                ],
            },
            headers={"X-API-Key": "test_key"},
        )
        assert response.status_code == 200
        body = response.json()
        assert "mean_exec_us" in body
        assert "max_exec_us" in body
        assert body["max_exec_us"] >= body["mean_exec_us"]

    def test_verify_response_has_summary(self):
        response = client.post(
            "/hardware/pynq/verify",
            json={
                "weights": [1.0],
                "layers": [
                    {
                        "input_size": 1,
                        "output_size": 1,
                        "weight_offset": 0,
                        "threshold": 1,
                        "leak_shift": 0,
                        "refractory": 0,
                    }
                ],
            },
            headers={"X-API-Key": "test_key"},
        )
        assert response.status_code == 200
        summary = response.json()["summary"]
        assert isinstance(summary, str)
        assert len(summary) > 0
