import pathlib
import sys
import time
from collections.abc import Callable
from copy import deepcopy
from typing import Any

import pytest
from fastapi.testclient import TestClient

REPO_ROOT = pathlib.Path(__file__).resolve().parents[3]
CANONICAL_NEUROSIM_PARENT = str(REPO_ROOT / "neurocnl")
# Always ensure the canonical path is first — pytest may have inserted the mirror
# root (Neurosim/) at position 0 before conftest runs, pushing neurocnl/ back.
if CANONICAL_NEUROSIM_PARENT in sys.path:
    sys.path.remove(CANONICAL_NEUROSIM_PARENT)
sys.path.insert(0, CANONICAL_NEUROSIM_PARENT)
# Clear stale neurosim app/service cache from pytest's collection phase so the
# re-ordered path takes effect. Preserve neurosim.tests.* — those are the test
# package modules currently being loaded by pytest and must not be evicted.
for _key in list(sys.modules.keys()):
    if _key == "neurosim" or (
        _key.startswith("neurosim.") and not _key.startswith("neurosim.tests")
    ):
        sys.modules.pop(_key, None)

import neurosim  # noqa: E402
from neurosim.app.main import app  # noqa: E402

CANONICAL_NEUROSIM = REPO_ROOT / "neurocnl" / "neurosim"
assert pathlib.Path(neurosim.__file__).resolve().parent == CANONICAL_NEUROSIM, (
    f"Tests are importing neurosim from {neurosim.__file__!r} instead of {CANONICAL_NEUROSIM}"
)

CANONICAL_SHARED_NEUROCNL_GRAPH = {
    "nodes": [
        {
            "id": "exc_pop",
            "component_id": "lif_population",
            "parameters": {
                "name": "exc_pop",
                "n_neurons": 12,
                "tau_rc": 0.02,
                "tau_ref": 0.002,
            },
            "position": [0, 0],
        },
        {
            "id": "inh_pop",
            "component_id": "lif_population",
            "parameters": {
                "name": "inh_pop",
                "n_neurons": 8,
                "tau_rc": 0.02,
                "tau_ref": 0.002,
            },
            "position": [320, 0],
        },
    ],
    "edges": [
        {
            "id": "exc_to_inh",
            "source_node_id": "exc_pop",
            "source_port": "out",
            "target_node_id": "inh_pop",
            "target_port": "in",
            "parameters": {"weight": 0.5, "delay": 0.005},
        }
    ],
    "metadata": {},
}


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)


@pytest.fixture
def canonical_graph() -> dict[str, Any]:
    return deepcopy(CANONICAL_SHARED_NEUROCNL_GRAPH)


@pytest.fixture
def wait_for_preview_completion(client: TestClient) -> Callable[[str], dict[str, Any]]:
    def _wait(job_id: str, *, max_attempts: int = 30, interval_s: float = 0.1) -> dict[str, Any]:
        last_payload: dict[str, Any] | None = None
        for _ in range(max_attempts):
            response = client.get(f"/api/neurosim/simulations/{job_id}")
            assert response.status_code == 200
            last_payload = response.json()
            if last_payload["status"] not in {"queued", "running"}:
                return last_payload
            time.sleep(interval_s)

        pytest.fail(f"Preview job {job_id} did not complete in time: {last_payload}")

    return _wait


@pytest.fixture
def wait_for_sweep_completion(client: TestClient) -> Callable[[str], dict[str, Any]]:
    def _wait(job_id: str, *, max_attempts: int = 30, interval_s: float = 0.1) -> dict[str, Any]:
        last_payload: dict[str, Any] | None = None
        for _ in range(max_attempts):
            response = client.get(f"/api/neurosim/sweep/{job_id}")
            assert response.status_code == 200
            last_payload = response.json()
            if last_payload["status"] not in {"queued", "running"}:
                return last_payload
            time.sleep(interval_s)

        pytest.fail(f"Sweep job {job_id} did not complete in time: {last_payload}")

    return _wait
