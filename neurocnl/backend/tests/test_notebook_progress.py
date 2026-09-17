"""Tests verifying __nmtk_progress__ markers are injected into generated notebooks."""

from unittest.mock import MagicMock

from backend.app.routers.notebook import (
    NMTK_EMIT_CELL_SOURCE,
    DagNodePayload,
    PhaseDAGPayload,
    PipelineConfigPayload,
    PipelinePhasesPayload,
    _build_v2_notebook,
)


def _make_empty_graph() -> MagicMock:
    g = MagicMock()
    g.nodes = {}
    g.edges = {}
    return g


def _train_phases() -> PipelinePhasesPayload:
    """Minimal train-phase DAG — the training cell only exists when the
    Pipeline tab actually wired one up (see `_build_v2_notebook`'s
    `pipeline_phases.train.nodes` guard), so a progress-marker test needs a
    real phase, not an empty payload."""
    return PipelinePhasesPayload(
        train=PhaseDAGPayload(
            nodes=[
                DagNodePayload(id="loader", type="dataLoader", parameters={}),
                DagNodePayload(id="forward", type="forwardPass", parameters={}),
                DagNodePayload(id="loss", type="ceCountLoss", parameters={}),
                DagNodePayload(id="optimiser", type="adamOptimiser", parameters={}),
            ],
            edges=[],
        )
    )


def test_nmtk_emit_cell_source_contains_progress_marker():
    assert "__nmtk_progress__" in NMTK_EMIT_CELL_SOURCE
    assert "_nmtk_emit" in NMTK_EMIT_CELL_SOURCE


def test_build_v2_notebook_contains_nmtk_emit_helper():
    graph = _make_empty_graph()
    cfg = PipelineConfigPayload(framework="snntorch_sim", epochs=3)
    nb, _ = _build_v2_notebook(
        "network N:\n  input: 784\n  output: 10\n",
        graph,
        cfg,
        "2026-06-16 00:00 UTC",
        pipeline_phases=PipelinePhasesPayload(),
    )

    code_sources = [c["source"] for c in nb.get("cells", []) if c.get("cell_type") == "code"]
    assert any("_nmtk_emit" in s for s in code_sources), "_nmtk_emit helper not found"
    assert any("__nmtk_progress__" in s for s in code_sources), "progress marker not found"


def test_snntorch_training_cell_calls_nmtk_emit():
    graph = _make_empty_graph()
    cfg = PipelineConfigPayload(framework="snntorch_sim", epochs=5)
    nb, _ = _build_v2_notebook(
        "network N:\n  input: 784\n  output: 10\n",
        graph,
        cfg,
        "2026-06-16 00:00 UTC",
        pipeline_phases=_train_phases(),
    )

    code_sources = [c["source"] for c in nb.get("cells", []) if c.get("cell_type") == "code"]
    train_cells = [s for s in code_sources if "for epoch in range" in s]
    assert train_cells, "no training loop cell found"
    assert "_nmtk_emit" in train_cells[0], "_nmtk_emit not called in training loop"


def test_sinabs_notebook_does_not_offer_a_nonexistent_training_loop():
    graph = _make_empty_graph()
    cfg = PipelineConfigPayload(framework="sinabs", epochs=5)
    nb, _ = _build_v2_notebook(
        "network N:\n  input: 784\n  output: 10\n",
        graph,
        cfg,
        "2026-06-16 00:00 UTC",
        pipeline_phases=_train_phases(),
    )

    code_sources = [c["source"] for c in nb.get("cells", []) if c.get("cell_type") == "code"]
    all_sources = [c["source"] for c in nb.get("cells", [])]
    assert not any("for epoch in range" in source for source in code_sources)
    assert any("no Studio training adapter" in source for source in all_sources), (
        "Sinabs notebook must explain that it is inference/code-generation only"
    )
