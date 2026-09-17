from backend.app.routers.notebook import (
    DagNodePayload,
    PhaseDAGPayload,
    PipelineConfigPayload,
    _phase_dag_to_code,
)

cfg = PipelineConfigPayload(framework="snntorch_sim", dataset="tonic_nmnist")

# Case A: Evaluate graph with dataLoader node
nodes = [
    DagNodePayload(
        id="1",
        type="dataLoader",
        parameters={"format": "tonic_nmnist", "batch_size": 128, "time_window_ms": 1},
    ),
    DagNodePayload(id="2", type="forwardPass", parameters={}),
    DagNodePayload(id="3", type="accuracyMetric", parameters={}),
]
edges = [
    {"source": "1", "target": "2", "sourceHandle": "data", "targetHandle": "data"},
    {
        "source": "2",
        "target": "3",
        "sourceHandle": "spk_out",
        "targetHandle": "spk_out",
    },
]
phase = PhaseDAGPayload(nodes=nodes, edges=edges)

print("EVAL GRAPH WITH DATALOADER:")
print(_phase_dag_to_code(phase, cfg, "tonic_nmnist"))
