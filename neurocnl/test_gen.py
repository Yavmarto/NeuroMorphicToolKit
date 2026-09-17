import nir

from backend.app.routers.notebook import (
    PipelineConfigPayload,
    PipelinePhasesPayload,
    _build_v2_notebook,
)

# Mock minimal graph
graph = nir.NIRGraph(nodes={}, edges=[])

cfg = PipelineConfigPayload(framework="snntorch_sim", dataset="tonic_nmnist")
# We'll also try with dataset=""
spec = "{}"
nb, _ = _build_v2_notebook(spec, graph, cfg, "timestamp", PipelinePhasesPayload(phases={}))
print("Notebook with global tonic_nmnist dataset:")
for c in nb["cells"]:
    if c["cell_type"] == "code":
        print("".join(c["source"]))
        print("---")
