from pathlib import Path

import nengo

from neurosim.app.schemas.preview import PreviewRequest
from neurosim.app.services.job_store import job_store
from neurosim.app.services.preview_runner import (
    ensure_nengo_runtime_cache,
    run_preview,
    run_preview_sync,
)
from neurosim.contracts.design_contracts import (
    CanvasGraph,
    CanvasNode,
    SimulationStatus,
)


def test_ensure_nengo_runtime_cache_recovers_from_missing_home(tmp_path: Path) -> None:
    missing_home = tmp_path / "missing-home"
    env = {"HOME": str(missing_home)}

    decoder_cache_dir = ensure_nengo_runtime_cache(env)

    runtime_home = Path(env["HOME"])
    cache_root = Path(env["XDG_CACHE_HOME"])
    assert runtime_home != missing_home
    assert runtime_home.is_dir()
    assert cache_root.is_dir()
    assert decoder_cache_dir == cache_root / "nengo" / "decoders"
    assert decoder_cache_dir.is_dir()
    assert nengo.rc.get("decoder_cache", "path") == str(decoder_cache_dir)
    assert nengo.rc.get("decoder_cache", "enabled") == "True"


def test_run_preview_async_flow() -> None:
    graph = CanvasGraph(
        nodes=[
            CanvasNode(
                id="n1",
                component_id="lif_population",
                parameters={"name": "P1", "n_neurons": 10},
                position=(0, 0),
            ),
        ],
        edges=[],
        metadata={},
    )
    request = PreviewRequest(graph=graph, duration_ms=100)

    # 1. Start job
    response = run_preview(request)
    assert response.status in [SimulationStatus.COMPLETED, SimulationStatus.QUEUED]
    job_id = response.job_id
    assert job_id is not None

    # If it completed synchronously
    if response.status == SimulationStatus.COMPLETED:
        assert response.results is not None
        assert "n1" in response.results
        assert "spikes" in response.results["n1"]
        assert "voltage" in response.results["n1"]
        assert len(response.results["n1"]["spikes"]) == 10
        assert response.playback is not None
        assert response.playback.nodes
        assert response.playback.summary.total_spikes >= 0
        # 10 neurons is well under the bulk-frame threshold.
        assert response.playback.bulk_spike_frame is None
    else:
        # 2. Run simulation (simulating background task)
        run_preview_sync(request, job_id)

        # 3. Check results
        job = job_store.get_job(job_id)
        assert job is not None
        if job.status == SimulationStatus.FAILED:
            print(f"Job failed with error: {job.error}")
        assert job.status == SimulationStatus.COMPLETED
        assert isinstance(job.results, dict)
        assert "n1" in job.results
        assert "spikes" in job.results["n1"]
        assert "voltage" in job.results["n1"]
        # We probed 10 neurons for spikes and 5 for voltage (from implementation)
        assert len(job.results["n1"]["spikes"]) == 10
        assert len(job.results["n1"]["voltage"][0]) == 5
        assert job.playback is not None
        assert job.playback.nodes
        assert job.playback.summary.total_spikes >= 0


def test_preview_reports_approximate_delay_and_threshold_annotations() -> None:
    graph = CanvasGraph(
        nodes=[
            CanvasNode(
                id="sensory",
                component_id="lif_population",
                parameters={"name": "sensory", "n_neurons": 10, "threshold": 1.5},
                position=(0, 0),
            ),
            CanvasNode(
                id="motor",
                component_id="lif_population",
                parameters={"name": "motor", "n_neurons": 10},
                position=(100, 0),
            ),
        ],
        edges=[
            {
                "id": "edge1",
                "source_node_id": "sensory",
                "source_port": "out",
                "target_node_id": "motor",
                "target_port": "in",
                "parameters": {"weight": 0.5, "delay": 0.01},
            },
        ],
        metadata={},
    )
    response = run_preview(PreviewRequest(graph=graph, duration_ms=100))

    assert response.status == SimulationStatus.COMPLETED
    assert response.backend_support is not None
    assert response.backend_support.verdict == "approximate"
    assert response.generator_fidelity is not None
    assert response.playback is not None
    assert response.playback.edge_events

    annotations = response.generator_fidelity.annotations
    assert any(
        annotation.concept == "axonal_delay" and annotation.fidelity == "approximate"
        for annotation in annotations
    )
    assert any(
        annotation.concept == "threshold" and annotation.fidelity == "approximate"
        for annotation in annotations
    )


def test_run_preview_populates_bulk_spike_frame_for_large_network() -> None:
    graph = CanvasGraph(
        nodes=[
            CanvasNode(
                id="pop_a",
                component_id="lif_population",
                parameters={"name": "pop_a", "n_neurons": 3000},
                position=(0, 0),
            ),
            CanvasNode(
                id="pop_b",
                component_id="lif_population",
                parameters={"name": "pop_b", "n_neurons": 3000},
                position=(100, 0),
            ),
        ],
        edges=[],
        metadata={},
    )
    response = run_preview(PreviewRequest(graph=graph, duration_ms=100))

    assert response.status == SimulationStatus.COMPLETED
    assert response.playback is not None
    bulk_frame = response.playback.bulk_spike_frame
    assert bulk_frame is not None
    assert set(bulk_frame.nodes.keys()) == {"pop_a", "pop_b"}
    assert bulk_frame.nodes["pop_a"].neuron_count == 3000
    assert bulk_frame.nodes["pop_b"].neuron_count == 3000
