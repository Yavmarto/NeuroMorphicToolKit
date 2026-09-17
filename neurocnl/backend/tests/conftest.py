"""Backend test configuration."""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from backend.app.main import app
from backend.tests.notebook_test_fixtures import VALID_SPEC

# Shared fixture spec, also defined locally in test_e2e_pipeline.py and
# test_deploy_endpoints.py — test_prosthetic_analysis.py imports it from here
# instead, and nothing ever defined it here, so every run of this test
# directory failed collection with `ImportError: cannot import name
# 'REFLEX_ARC_SPEC'` — which, same as the nengo plugin above, made
# dev_update.sh's pre-sync test gate always die before syncing anything.
REFLEX_ARC_SPEC = (
    Path(__file__).resolve().parent.parent / "app" / "templates" / "reflex_arc.cnl"
).read_text()


@pytest.fixture
def client() -> TestClient:
    # test_deploy_endpoints.py / test_e2e_pipeline.py / test_prosthetic_analysis.py
    # all take `client` as a test parameter, matching the fixture-based pattern
    # used by every sibling module (neurosim/neurobench/neurohub's own
    # conftest.py) — but nothing here ever defined it, so every test using it
    # errored at fixture setup with `fixture 'client' not found`, contributing
    # 41 of dev_update.sh's pre-sync test gate errors.
    return TestClient(app)


@pytest.fixture
def default_nb():
    """Notebook built from VALID_SPEC with default pipeline config and one eval node.

    Defined here (conftest) so test modules can request it by parameter name
    without importing it — importing a fixture into a test module and then
    requesting it as a parameter trips ruff's F811.
    """
    from backend.app.routers.notebook import _build_v2_notebook, compile_to_nir
    from backend.app.schemas.notebook import PipelineConfigPayload
    from backend.app.schemas.pipeline_dag import (
        DagNodePayload,
        PhaseDAGPayload,
        PipelinePhasesPayload,
    )

    graph = compile_to_nir(VALID_SPEC)
    phases = PipelinePhasesPayload(
        eval=PhaseDAGPayload(
            nodes=[DagNodePayload(id="e1", type="forwardPass", parameters={})],
            edges=[],
        )
    )
    nb, _ = _build_v2_notebook(
        VALID_SPEC,
        graph,
        PipelineConfigPayload(),
        "2026-01-01 00:00 UTC",
        pipeline_phases=phases,
    )
    return nb


def pytest_configure(config: pytest.Config) -> None:
    # The global pytest-nengo plugin parametrizes neuron types during collection
    # and breaks isolated backend API tests. Block it for this directory.
    #
    # set_blocked() takes the plugin's registered pytest11 entry-point NAME,
    # not its module name — `pip show -f nengo`'s entry_points group shows
    # `nengo = pytest_nengo` (name=nengo, value=pytest_nengo), so blocking
    # "pytest_nengo"/"pytest-nengo" was a silent no-op: the plugin stayed
    # loaded, and its `pytest_generate_tests` hook imported nengo's own test
    # suite (nengo/tests/test_neurons.py -> matplotlib), which crashes with a
    # circular-import ImportError in any environment where matplotlib isn't
    # fully importable — aborting collection for the entire `tests/` run.
    # Same fix applied to this directory's pytest.ini (`-p no:nengo`).
    config.pluginmanager.set_blocked("nengo")
