"""VCR tests for Neurobench adapter — outgoing HTTP calls.

``BenchmarkRunner._run_hardware_target`` is the sole outgoing HTTP entry
point in the Neurobench backend.  It POSTs a JSON payload containing a
CNL spec and run parameters to either the NeuroSim API
(``http://neurosim-backend:8001/execute``) or the NeuroChip API
(``http://neurochip-backend:8002/execute``) using a synchronous
``httpx.Client``.

The cassettes under ``neurobench/`` record pre-authored responses
matching the expected benchmark metrics schema.  VCRpy intercepts the
httpx call via its httpcore stubs, so no live inter-service request
is made during the standard test run.

``app.config`` uses pydantic_settings which reads ALL environment variables
by default; some env vars present in the monorepo root environment collide
with the model's ``extra="forbid"`` policy.  We stub the module before
importing so that ``Settings()`` never executes in the root test context.
"""

from __future__ import annotations

import os
import pathlib
import sys
from unittest.mock import MagicMock

import pytest
import vcr as _vcr_module

# ---------------------------------------------------------------------------
# Stub app.config BEFORE any neurobench import runs Settings()
# ---------------------------------------------------------------------------

_mock_settings = MagicMock()
_mock_settings.neurosim_api_url = "http://neurosim-backend:8001/execute"
_mock_settings.neurochip_api_url = "http://neurochip-backend:8002/execute"
_mock_settings.hardware_timeout_seconds = 30.0

_mock_config_module = MagicMock()
_mock_config_module.settings = _mock_settings

# Only inject the stub if app.config has not yet been successfully imported
if "app.config" not in sys.modules:
    sys.modules["app.config"] = _mock_config_module

# ---------------------------------------------------------------------------
# Module-local VCR config (avoids PYTHONPATH collision with module conftest)
# ---------------------------------------------------------------------------

_REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
_CASSETTE_DIR = _REPO_ROOT / "tests" / "fixtures" / "vcr_cassettes" / "neurobench"

_nmtk_vcr = _vcr_module.VCR(
    record_mode=os.getenv("NMTK_VCR_RECORD", "none"),
    match_on=["method", "scheme", "host", "port", "path", "query"],
    filter_headers=["Authorization", "X-API-Key", "Cookie"],
    filter_query_parameters=["api_key", "token"],
)

_NEUROSIM_CASSETTE = str(_CASSETTE_DIR / "test_runner_neurosim_target.yaml")
_NEUROCHIP_CASSETTE = str(_CASSETTE_DIR / "test_runner_neurochip_target.yaml")

# Minimal valid CNL spec written to a temp file for each test
_MINIMAL_CNL = (
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0\n"
    "The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds\n"
    "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0\n"
)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


def test_hardware_runner_neurosim_target_cassette(tmp_path: pathlib.Path) -> None:
    """Pin the BenchmarkRunner response when targeting the NeuroSim API.

    The cassette records a POST to ``http://neurosim-backend:8001/execute``
    and returns ``{"assertions_passed": 5, "accuracy": 0.95, ...}``.
    Verifies that the runner correctly parses all six metric keys from the
    flat JSON response body.
    """
    # Write a minimal CNL spec that _run_hardware_target can open
    spec_file = tmp_path / "test.cnl"
    spec_file.write_text(_MINIMAL_CNL)

    from app.services.benchmark_runner import BenchmarkRunner

    runner = BenchmarkRunner()

    with _nmtk_vcr.use_cassette(_NEUROSIM_CASSETTE):
        result = runner._run_hardware_target(
            url="http://neurosim-backend:8001/execute",
            target_name="neurosim",
            spec_path=str(spec_file),
            params={"seed": 42},
        )

    assert result["assertions_passed"] == 5.0
    assert result["assertions_failed"] == 0.0
    assert result["latency_ms"] == 5.5
    assert result["energy_uj"] == 1.2
    assert result["accuracy"] == 0.95
    assert result["mujoco_steps"] == 100.0


def test_hardware_runner_neurochip_target_cassette(tmp_path: pathlib.Path) -> None:
    """Pin the BenchmarkRunner response when targeting the NeuroChip API.

    The cassette records a POST to ``http://neurochip-backend:8002/execute``
    and returns ``{"accuracy": 0.87, ...}``.
    """
    spec_file = tmp_path / "test.cnl"
    spec_file.write_text(_MINIMAL_CNL)

    from app.services.benchmark_runner import BenchmarkRunner

    runner = BenchmarkRunner()

    with _nmtk_vcr.use_cassette(_NEUROCHIP_CASSETTE):
        result = runner._run_hardware_target(
            url="http://neurochip-backend:8002/execute",
            target_name="neurochip",
            spec_path=str(spec_file),
            params={"seed": 7},
        )

    assert result["assertions_passed"] == 4.0
    assert result["assertions_failed"] == 1.0
    assert result["accuracy"] == 0.87
    assert result["latency_ms"] == 2.1


def test_hardware_runner_timeout_raises_without_cassette(tmp_path: pathlib.Path) -> None:
    """Confirm BenchmarkTimeoutError propagates correctly — no network call needed.

    Uses the VCR cassette in pass-through mode to allow the httpx call to
    reach VCRpy's CannotSendRequest guard and be re-raised as a connection
    error → BenchmarkExecutionError.
    """
    import httpx
    from unittest.mock import patch

    from app.exceptions import BenchmarkTimeoutError
    from app.services.benchmark_runner import BenchmarkRunner

    spec_file = tmp_path / "test.cnl"
    spec_file.write_text(_MINIMAL_CNL)

    runner = BenchmarkRunner()

    with patch("httpx.Client.post", side_effect=httpx.TimeoutException("timed out")):
        with pytest.raises(BenchmarkTimeoutError, match="timed out"):
            runner._run_hardware_target(
                url="http://neurosim-backend:8001/execute",
                target_name="neurosim",
                spec_path=str(spec_file),
                params={},
            )
