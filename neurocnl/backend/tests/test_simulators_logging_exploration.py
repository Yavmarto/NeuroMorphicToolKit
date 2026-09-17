"""Bug condition exploration test — Lava failure paths produce structured log entries.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4**

This file was originally written against UNFIXED code to confirm the bug existed.
After the fix in task 3 was applied, the assertions have been updated to encode
the CORRECT post-fix behaviour. All four sub-cases now assert that the fix works.

Post-fix expected behaviour
----------------------------
- Sub-case A (missing-dep): ``captured_logs`` contains exactly one entry with
  ``level="warning"``, ``backend="lava_sim"``, ``reason="missing_dependency"``
- Sub-case B (LavaDispatchError): ``captured_logs`` contains exactly one entry
  with ``level="error"``, ``backend="lava_sim"``, ``exc_type="LavaDispatchError"``
- Sub-case C (unexpected exception): ``captured_logs`` contains exactly one entry
  with ``level="error"`` (from ``logger.exception``), ``backend="lava_sim"``,
  ``exc_type="RuntimeError"``
- Sub-case D (structural): Source of simulators.py now CONTAINS ``import structlog``
  and a ``logger =`` assignment

Counterexamples documented from original unfixed run
-----------------------------------------------------
- Sub-case A (missing-dep): ``_is_available=False, _lava_worker_url=None``
  → ``captured_logs == []`` (expected WARNING with backend="lava_sim" absent)
- Sub-case B (LavaDispatchError): ``LavaDispatchError("test dispatch error")`` raised
  → ``captured_logs == []`` (expected ERROR with backend="lava_sim" absent)
- Sub-case C (unexpected exception): ``RuntimeError("unexpected")`` raised
  → ``captured_logs == []`` (expected ERROR with backend="lava_sim" absent)
- Sub-case D (structural): no ``logger`` identifier in simulators.py
  → confirms absence of ``import structlog`` and module-level logger setup
"""

from __future__ import annotations

import inspect
from unittest.mock import patch

import structlog.testing
from fastapi.testclient import TestClient

from backend.app.main import app

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
_LAVA_PAYLOAD = {"spec": _VALID_SPEC, "backend_name": "lava_sim"}


# ---------------------------------------------------------------------------
# Sub-case A — Missing-dependency path
# ---------------------------------------------------------------------------


def test_subcaseA_missing_dependency_produces_warning_log_entry() -> None:
    """Confirms Req 2.4: missing-dep path writes a WARNING structured log entry.

    **Validates: Requirements 2.4**

    Patch _is_available → False and _lava_worker_url → None so the 503 branch
    is taken immediately.  The fix adds a logger.warning call immediately before
    the raise HTTPException so captured_logs contains exactly one entry with
    level="warning", backend="lava_sim", and reason="missing_dependency".

    Counterexample (original unfixed): _is_available=False, _lava_worker_url=None
      → captured_logs == []
    Post-fix: captured_logs contains one WARNING entry with backend="lava_sim"
    """
    client = TestClient(app, raise_server_exceptions=False)

    with (
        structlog.testing.capture_logs() as captured_logs,
        patch(
            "backend.app.routers.simulators._is_available",
            return_value=False,
        ),
        patch(
            "backend.app.routers.simulators.lava_worker_url",
            return_value=None,
        ),
    ):
        resp = client.post(
            _RUN_URL,
            json=_LAVA_PAYLOAD,
            headers={"X-Forwarded-For": "192.0.2.1"},
        )

    # The endpoint must return 503 (dependency missing).
    assert resp.status_code == 503, (
        f"Expected 503 from missing-dep path, got {resp.status_code}: {resp.text}"
    )

    # FIX VERIFIED: the WARNING entry with backend="lava_sim" is now present.
    lava_entries = [e for e in captured_logs if e.get("backend") == "lava_sim"]
    assert len(lava_entries) == 1, f"Expected exactly one lava_sim log entry, got: {lava_entries}"
    entry = lava_entries[0]
    assert entry.get("log_level") == "warning", (
        f"Expected log_level='warning', got {entry.get('log_level')!r}"
    )
    assert entry.get("reason") == "missing_dependency", (
        f"Expected reason='missing_dependency', got {entry.get('reason')!r}"
    )


# ---------------------------------------------------------------------------
# Sub-case B — LavaDispatchError path
# ---------------------------------------------------------------------------


def test_subcaseB_lava_dispatch_error_produces_error_log_entry() -> None:
    """Confirms Req 2.2: LavaDispatchError path writes an ERROR structured log entry.

    **Validates: Requirements 2.2**

    _is_available → True so the 503 branch is bypassed and LavaSimulatorAdapter
    is called.  The adapter is patched to raise LavaDispatchError.  The fix adds
    a logger.error call as the first statement in the except LavaDispatchError block,
    so captured_logs contains exactly one entry with level="error",
    backend="lava_sim", and exc_type="LavaDispatchError".

    Counterexample (original unfixed): LavaDispatchError("test dispatch error") raised
      → captured_logs == []
    Post-fix: captured_logs contains one ERROR entry with backend="lava_sim"
    """
    from neurocnl.runtime.lava_simulator import LavaDispatchError

    client = TestClient(app, raise_server_exceptions=False)

    with (
        structlog.testing.capture_logs() as captured_logs,
        patch(
            "backend.app.routers.simulators._is_available",
            return_value=True,
        ),
        patch(
            "neurocnl.runtime.lava_simulator.LavaSimulatorAdapter.run",
            side_effect=LavaDispatchError("test dispatch error"),
        ),
    ):
        resp = client.post(
            _RUN_URL,
            json=_LAVA_PAYLOAD,
            headers={"X-Forwarded-For": "192.0.2.2"},
        )

    # The endpoint must return 422 (dispatch failed).
    assert resp.status_code == 422, (
        f"Expected 422 from LavaDispatchError path, got {resp.status_code}: {resp.text}"
    )

    # FIX VERIFIED: the ERROR entry with backend="lava_sim" is now present.
    lava_entries = [e for e in captured_logs if e.get("backend") == "lava_sim"]
    # Filter to error-level only (the logger.info pre-dispatch entry may also be present)
    error_entries = [e for e in lava_entries if e.get("log_level") == "error"]
    assert len(error_entries) == 1, (
        f"Expected exactly one ERROR-level lava_sim log entry, got: {lava_entries}"
    )
    entry = error_entries[0]
    assert entry.get("exc_type") == "LavaDispatchError", (
        f"Expected exc_type='LavaDispatchError', got {entry.get('exc_type')!r}"
    )


# ---------------------------------------------------------------------------
# Sub-case C — Unexpected-exception path
# ---------------------------------------------------------------------------


def test_subcaseC_unexpected_exception_produces_error_log_entry() -> None:
    """Confirms Req 2.3: unexpected-exception path writes an ERROR structured log entry.

    **Validates: Requirements 2.3**

    _is_available → True; LavaSimulatorAdapter.run raises RuntimeError.
    The fix adds a bare except Exception clause with logger.exception, so
    captured_logs contains exactly one ERROR-level entry with backend="lava_sim"
    and exc_type="RuntimeError".

    Counterexample (original unfixed): RuntimeError("unexpected") raised
      → captured_logs == []
    Post-fix: captured_logs contains one ERROR entry with backend="lava_sim"
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
            side_effect=RuntimeError("unexpected"),
        ),
    ):
        # raise_server_exceptions=False so the 500 doesn't propagate to the test
        resp = client.post(
            _RUN_URL,
            json=_LAVA_PAYLOAD,
            headers={"X-Forwarded-For": "192.0.2.3"},
        )

    # After the fix: the bare except clause catches RuntimeError, logs it, and re-raises
    # which becomes a 500 from FastAPI's perspective.
    assert resp.status_code in {
        422,
        500,
    }, f"Unexpected status {resp.status_code}: {resp.text}"

    # FIX VERIFIED: the ERROR entry with backend="lava_sim" is now present.
    lava_entries = [e for e in captured_logs if e.get("backend") == "lava_sim"]
    # Filter to error-level only (the logger.info pre-dispatch entry may also be present)
    error_entries = [e for e in lava_entries if e.get("log_level") == "error"]
    assert len(error_entries) == 1, (
        f"Expected exactly one ERROR-level lava_sim log entry, got: {lava_entries}"
    )
    entry = error_entries[0]
    assert entry.get("exc_type") == "RuntimeError", (
        f"Expected exc_type='RuntimeError', got {entry.get('exc_type')!r}"
    )


# ---------------------------------------------------------------------------
# Sub-case D — Gateway-timeout / structural check
# ---------------------------------------------------------------------------


def test_subcaseD_logger_identifier_present_in_simulators_module() -> None:
    """Confirms Req 2.1: simulators.py now has a logger identifier — structural fix verified.

    **Validates: Requirements 2.1**

    Inspect the source of simulators.py and assert it NOW CONTAINS both
    ``import structlog`` and a ``logger =`` assignment.  This is a static check
    confirming the structural fix that addresses the gateway-timeout blind spot:
    with a logger instantiated and a logger.info call before LavaSimulatorAdapter.run(),
    at least one log entry lands in the backend logs before the long-running call begins.

    Counterexample (original unfixed): source of simulators.py contained no 'logger' token
      → confirms absence of import structlog and module-level logger setup
    Post-fix: both 'import structlog' and 'logger =' ARE present in simulators.py
    """
    import backend.app.routers.simulators as simulators_module

    source = inspect.getsource(simulators_module)

    # After the fix there IS an 'import structlog' line.
    assert "import structlog" in source, (
        "simulators.py is missing 'import structlog' — the fix was not applied correctly."
    )

    # After the fix there IS a 'logger =' identifier in the module.
    assert "logger =" in source, (
        "simulators.py is missing a 'logger =' assignment — the fix was not applied correctly."
    )
