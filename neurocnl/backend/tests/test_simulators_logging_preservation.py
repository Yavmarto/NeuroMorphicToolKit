"""Preservation property tests — non-buggy paths return identical results.

**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**

This file follows the observation-first methodology: each sub-case was first
run against UNFIXED code to record the baseline behaviour, then encoded as
assertions here.  All tests in this file MUST PASS on UNFIXED code — they
establish the regression baseline that task 3.7 re-checks after the fix.

Property: Preservation — Non-buggy inputs are unaffected
---------------------------------------------------------
For any dispatch attempt X where ``isBugCondition(X)`` is false (successful
Lava run, any SNNTorch input, any pre-dispatch pipeline failure), the fixed
``run_simulation`` SHALL produce exactly the same return value or exception —
including HTTP status code, response body, and exception type — as the original
``run_simulation``, preserving all existing behaviour.

Sub-cases
---------
A  Successful Lava run   → status=200, status="completed", correct spikes,
                           backend_name="lava_sim", zero ERROR-level log entries
B  SNNTorch success      → status=200, status="completed", correct voltages,
                           backend_name="snntorch_sim"
C  SNNTorch dispatch err → status=422, detail.error="snntorch_dispatch_failed"

Property-based tests
--------------------
PBT-1  Random SNNTorch-path payloads  → status_code ∈ {200, 503},
        zero structlog entries with backend="lava_sim"
PBT-2  Random LavaSimulatorResult spikes → status_code=200, spikes round-trip,
        zero ERROR-level structlog entries
"""

from __future__ import annotations

import itertools
from unittest.mock import patch

import structlog.testing
from fastapi.testclient import TestClient
from hypothesis import Verbosity, given, settings
from hypothesis import strategies as st

from backend.app.main import app

# ---------------------------------------------------------------------------
# Hypothesis "ci" profile (max_examples=200, derandomize=True)
# ---------------------------------------------------------------------------

settings.register_profile("ci", max_examples=200, verbosity=Verbosity.normal, derandomize=True)
settings.load_profile("ci")

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

# A minimal CNL spec that compiles correctly. NIR-native syntax — the legacy
# biological grammar ("The network MUST contain...") this file originally
# used was fully retired (the parser now rejects "MUST" as a forbidden
# keyword), so every request below 400'd before ever reaching the dispatch
# logic these tests exist to exercise.
_VALID_SPEC = "\n".join(
    [
        "Define a network named sim_test.",
        "Define an input port named input with shape (2,).",
        "Define a linear transformation named w_in with weight matrix shape (2, 2).",
        "Define a LIF neuron named pop_a "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define a linear transformation named w_out with weight matrix shape (2, 2).",
        "Define a LIF neuron named pop_b "
        "with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define an output port named output with shape (2,).",
        "input connects to w_in.",
        "w_in connects to pop_a.",
        "pop_a connects to w_out.",
        "w_out connects to pop_b.",
        "pop_b connects to output.",
    ]
)

_RUN_URL = "/api/simulators/run"

# A fixed valid LavaSimulatorResult-compatible object used in patching.
_LAVA_KNOWN_SPIKES: dict[str, dict[str, list[int]]] = {"output": {"0": [2, 5, 9], "1": [3, 7]}}

# Monotonically-increasing counter to generate a unique X-Forwarded-For IP
# for every test invocation, guaranteeing each call occupies its own rate-limit
# bucket regardless of how many examples Hypothesis generates.
_ip_counter = itertools.count(1)


def _next_ip() -> str:
    """Return a unique 10.x.x.x IP address for rate-limit isolation."""
    n = next(_ip_counter)
    a = (n >> 16) & 0xFF
    b = (n >> 8) & 0xFF
    c = n & 0xFF
    return f"10.{a}.{b}.{c}"


def _make_lava_result(spikes: dict[str, dict[str, list[int]]]) -> object:
    """Build a minimal LavaSimulatorResult-compatible object from a spikes dict."""
    return type(
        "LavaResult",
        (),
        {
            "spikes": spikes,
            "voltages": {},
            "execution_time_ms": 12.0,
            "runtime_mode": "in_process_lava_sim",
            "warnings": [],
        },
    )()


def _make_snn_result(
    spikes: dict[str, dict[str, list[int]]] | None = None,
    voltages: dict[str, dict[str, list[float]]] | None = None,
) -> object:
    """Build a minimal SnnTorchSimulatorResult-compatible object."""
    return type(
        "SnnResult",
        (),
        {
            "spikes": spikes or {"output": {"0": [1, 4], "1": [2]}},
            "voltages": voltages or {"output": {"0": [0.1, 0.5, 0.3], "1": [0.2, 0.4, 0.2]}},
            "execution_time_ms": 8.0,
            "runtime_mode": "in_process_snntorch_sim",
            "warnings": [],
        },
    )()


# ---------------------------------------------------------------------------
# Sub-case A — Successful Lava run
# ---------------------------------------------------------------------------


def test_subcaseA_successful_lava_run_preserved() -> None:
    """Req 3.1: successful Lava path returns SimulatorRunResult with known fields.

    **Validates: Requirements 3.1**

    Observation: patch _is_available → True, LavaSimulatorAdapter.run → known result.
    Baseline (unfixed code): status=200, status="completed", backend_name="lava_sim",
    spikes match patched result, zero ERROR-level structlog entries.
    """
    client = TestClient(app, raise_server_exceptions=False)

    with (
        structlog.testing.capture_logs() as captured_logs,
        patch(
            "backend.app.routers.simulators._is_available",
            return_value=True,
        ),
        patch(
            "neurocnl.runtime.lava_simulator.LavaSimulatorAdapter.run",
            return_value=_make_lava_result(_LAVA_KNOWN_SPIKES),
        ),
    ):
        resp = client.post(
            _RUN_URL,
            json={
                "spec": _VALID_SPEC,
                "backend_name": "lava_sim",
                "timesteps": 50,
                "seed": 1,
            },
            headers={"X-Forwarded-For": "10.2.0.1"},
        )

    assert resp.status_code == 200, (
        f"Expected 200 from successful Lava run, got {resp.status_code}: {resp.text}"
    )
    data = resp.json()
    assert data["status"] == "completed", f"Expected status='completed', got {data['status']!r}"
    assert data["backend_name"] == "lava_sim", (
        f"Expected backend_name='lava_sim', got {data['backend_name']!r}"
    )
    # Spikes must round-trip through the result
    assert data["spikes"] == _LAVA_KNOWN_SPIKES, (
        f"Spikes mismatch: expected {_LAVA_KNOWN_SPIKES}, got {data['spikes']}"
    )
    # Preservation: no ERROR-level lava_sim entries on the success path
    error_entries = [
        e for e in captured_logs if e.get("backend") == "lava_sim" and e.get("log_level") == "error"
    ]
    assert error_entries == [], (
        f"Unexpected ERROR-level lava_sim log entries on success path: {error_entries}"
    )


# ---------------------------------------------------------------------------
# Sub-case B — SNNTorch success
# ---------------------------------------------------------------------------


def test_subcaseB_snntorch_success_preserved() -> None:
    """Req 3.3: SNNTorch success path returns SimulatorRunResult with correct fields.

    **Validates: Requirements 3.3**

    Observation: patch SnnTorchSimulatorAdapter.run → known result.
    Baseline: status=200, status="completed", backend_name="snntorch_sim",
    voltages non-empty.
    """
    client = TestClient(app, raise_server_exceptions=False)

    snn_result = _make_snn_result()

    with (
        patch(
            "backend.app.routers.simulators._is_available",
            return_value=True,
        ),
        patch(
            "neurocnl.runtime.snntorch_simulator.SnnTorchSimulatorAdapter.run",
            return_value=snn_result,
        ),
    ):
        resp = client.post(
            _RUN_URL,
            json={
                "spec": _VALID_SPEC,
                "backend_name": "snntorch_sim",
                "timesteps": 50,
                "seed": 2,
            },
            headers={"X-Forwarded-For": "10.2.0.2"},
        )

    assert resp.status_code == 200, (
        f"Expected 200 from SNNTorch success, got {resp.status_code}: {resp.text}"
    )
    data = resp.json()
    assert data["status"] == "completed", f"Expected status='completed', got {data['status']!r}"
    assert data["backend_name"] == "snntorch_sim", (
        f"Expected backend_name='snntorch_sim', got {data['backend_name']!r}"
    )
    # voltages must be non-empty from the mocked result
    assert data["voltages"] != {}, "Expected non-empty voltages from SNNTorch result"


# ---------------------------------------------------------------------------
# Sub-case C — SNNTorch dispatch error
# ---------------------------------------------------------------------------


def test_subcaseC_snntorch_dispatch_error_preserved() -> None:
    """Req 3.2: SNNTorch dispatch error returns HTTP 422 with snntorch_dispatch_failed.

    **Validates: Requirements 3.2**

    Observation: patch SnnTorchSimulatorAdapter.run → raises SnnTorchDispatchError.
    Baseline: status=422, detail.error="snntorch_dispatch_failed".
    """
    from neurocnl.runtime.snntorch_simulator import SnnTorchDispatchError

    client = TestClient(app, raise_server_exceptions=False)

    with (
        patch(
            "backend.app.routers.simulators._is_available",
            return_value=True,
        ),
        patch(
            "neurocnl.runtime.snntorch_simulator.SnnTorchSimulatorAdapter.run",
            side_effect=SnnTorchDispatchError("snn fail"),
        ),
    ):
        resp = client.post(
            _RUN_URL,
            json={"spec": _VALID_SPEC, "backend_name": "snntorch_sim"},
            headers={"X-Forwarded-For": "10.2.0.3"},
        )

    assert resp.status_code == 422, (
        f"Expected 422 from SnnTorchDispatchError, got {resp.status_code}: {resp.text}"
    )
    detail = resp.json()["detail"]
    assert detail["error"] == "snntorch_dispatch_failed", (
        f"Expected error='snntorch_dispatch_failed', got {detail['error']!r}"
    )


# ---------------------------------------------------------------------------
# PBT-1: Random SNNTorch-path payloads produce no lava_sim log entries
# ---------------------------------------------------------------------------


@given(
    backend_name=st.just("snntorch_sim"),
    timesteps=st.integers(min_value=10, max_value=200),
    seed=st.integers(min_value=0, max_value=99999),
)
@settings(max_examples=200, derandomize=True)
def test_pbt1_snntorch_path_produces_no_lava_log_entries(
    backend_name: str,
    timesteps: int,
    seed: int,
) -> None:
    """Req 3.2, 3.3: Any SNNTorch-path payload produces zero lava_sim structlog entries.

    **Validates: Requirements 3.2, 3.3**

    Property: for any valid SNNTorch request, status_code ∈ {200, 503}
    (not 500) and no structlog entry has backend="lava_sim".
    """
    client = TestClient(app, raise_server_exceptions=False)
    snn_result = _make_snn_result()
    # Unique IP per example avoids the shared rate-limit bucket (10/min per IP).
    unique_ip = _next_ip()

    with (
        structlog.testing.capture_logs() as captured_logs,
        patch(
            "backend.app.routers.simulators._is_available",
            return_value=True,
        ),
        patch(
            "neurocnl.runtime.snntorch_simulator.SnnTorchSimulatorAdapter.run",
            return_value=snn_result,
        ),
    ):
        resp = client.post(
            _RUN_URL,
            json={
                "spec": _VALID_SPEC,
                "backend_name": backend_name,
                "timesteps": timesteps,
                "seed": seed,
            },
            headers={"X-Forwarded-For": unique_ip},
        )

    assert resp.status_code in {
        200,
        503,
    }, f"Expected 200 or 503, got {resp.status_code}: {resp.text}"
    lava_entries = [e for e in captured_logs if e.get("backend") == "lava_sim"]
    assert lava_entries == [], (
        f"Expected zero lava_sim log entries for SNNTorch path, but got: {lava_entries}"
    )


# ---------------------------------------------------------------------------
# PBT-2: Random LavaSimulatorResult spikes round-trip with no ERROR logs
# ---------------------------------------------------------------------------

# Strategy: generate a spikes dict with 1–3 neuron keys, each with 0–5 timesteps.
_spike_times_st = st.lists(
    st.integers(min_value=0, max_value=199),
    min_size=0,
    max_size=5,
    unique=True,
).map(sorted)

_neuron_spikes_st = st.dictionaries(
    keys=st.integers(min_value=0, max_value=3).map(str),
    values=_spike_times_st,
    min_size=1,
    max_size=4,
)

_population_spikes_st = st.dictionaries(
    keys=st.sampled_from(["output", "lif", "pop0"]),
    values=_neuron_spikes_st,
    min_size=1,
    max_size=2,
)


@given(spikes=_population_spikes_st)
@settings(max_examples=200, derandomize=True)
def test_pbt2_lava_success_spikes_roundtrip_no_error_logs(
    spikes: dict[str, dict[str, list[int]]],
) -> None:
    """Req 3.1: Random Lava spikes round-trip; zero ERROR-level structlog entries.

    **Validates: Requirements 3.1**

    Property: for any LavaSimulatorResult-compatible spikes dict, status_code=200,
    response spikes match the patched result, and no ERROR-level structlog entries
    are written.
    """
    client = TestClient(app, raise_server_exceptions=False)
    # Unique IP per example avoids the shared rate-limit bucket (10/min per IP).
    unique_ip = _next_ip()

    with (
        structlog.testing.capture_logs() as captured_logs,
        patch(
            "backend.app.routers.simulators._is_available",
            return_value=True,
        ),
        patch(
            "neurocnl.runtime.lava_simulator.LavaSimulatorAdapter.run",
            return_value=_make_lava_result(spikes),
        ),
    ):
        resp = client.post(
            _RUN_URL,
            json={
                "spec": _VALID_SPEC,
                "backend_name": "lava_sim",
                "timesteps": 50,
                "seed": 0,
            },
            headers={"X-Forwarded-For": unique_ip},
        )

    assert resp.status_code == 200, (
        f"Expected 200 from successful Lava run, got {resp.status_code}: {resp.text}"
    )
    data = resp.json()
    assert data["spikes"] == spikes, (
        f"Spikes round-trip failed: expected {spikes}, got {data['spikes']}"
    )
    error_entries = [e for e in captured_logs if e.get("log_level") == "error"]
    assert error_entries == [], (
        f"Unexpected ERROR-level log entries on successful Lava path: {error_entries}"
    )
