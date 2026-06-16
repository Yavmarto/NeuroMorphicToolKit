import re

file_path = "/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/current tasks/16 june/cnlstudio_notebook_analysis.md"

with open(file_path, "r") as f:
    content = f.read()

# Summary table updates
content = content.replace(
    "| `03_rnn/snntorch_apply_subtract.ipynb` | Braille inference (subtract reset) | 🟡 MEDIUM-HIGH | ~~RSynaptic/Synaptic missing~~ ✅ Fixed — model fully buildable |",
    "| `03_rnn/snntorch_apply_subtract.ipynb` | Braille inference (subtract reset) | ✅ HIGH | ~~RSynaptic/Synaptic missing~~ ✅ Fixed — model fully buildable |"
)

# Notebook 1
content = content.replace(
    "| 1 | Model loaded from `lif_norse.nir` — CNLStudio may not yet support direct `.nir` file import into the Model canvas | Minor | Recreate the 2-node graph manually in Model canvas (takes ~30 seconds) |",
    "| 1 | ~~Model loaded from `lif_norse.nir` — CNLStudio may not yet support direct `.nir` file import into the Model canvas~~ | ~~Minor~~ | ✅ **Fixed** — \"Import NIR...\" option now available in the export/file menu. |"
)

content = re.sub(
    r"\*\*Canvas: Model\*\*\n\n1\. Open CNLStudio.*?\n7\. Save the model\. CNLStudio will represent this graph internally as a NIR graph identical to `lif_norse\.nir`\.",
    "**Canvas: Model**\n\n1. Open CNLStudio → navigate to the **Model Canvas**.\n2. Use the **Export / File Menu** → **Import NIR...** and select `lif_norse.nir`. The graph will be built automatically.",
    content,
    flags=re.DOTALL
)

# Notebook 2
content = content.replace(
    "**Verdict: 🟡 MEDIUM-HIGH — architecture fully replicable; dataset loading needs workaround**\n\nAll layer types are in the CNLStudio Model canvas palette. The CNN topology can be reconstructed node-by-node. The main friction is that `tonic` (a neuromorphic dataset library) is used for NMNIST — CNLStudio's data loading support for event-based datasets is unconfirmed.",
    "**Verdict: ✅ HIGH — fully replicable; tonic dataset loading and NIR import now supported**\n\nAll layer types are in the CNLStudio Model canvas palette. The CNN topology can be imported directly. The `tonic` (a neuromorphic dataset library) integration for NMNIST is also now supported natively."
)

content = content.replace(
    "| 1 | `tonic.datasets.NMNIST` + `tonic.transforms.ToFrame` — no native tonic integration in CNLStudio confirmed | Moderate | Pre-convert NMNIST to frame-based tensors offline (`tonic` → `.npy` files), then load via CNLStudio's standard Data Loader |",
    "| 1 | ~~`tonic.datasets.NMNIST` + `tonic.transforms.ToFrame` — no native tonic integration in CNLStudio confirmed~~ | ~~Moderate~~ | ✅ **Fixed** — Data Loader now supports `tonic_nmnist` format directly. |"
)

content = content.replace(
    "| 2 | Model loaded from `cnn_sinabs.nir` — must be reconstructed manually in Model canvas | Minor | Reconstruct layer-by-layer using the topology above (13 nodes, ~5 minutes) |",
    "| 2 | ~~Model loaded from `cnn_sinabs.nir` — must be reconstructed manually in Model canvas~~ | ~~Minor~~ | ✅ **Fixed** — \"Import NIR...\" option now available in the export/file menu. |"
)

content = re.sub(
    r"\*\*Canvas: Model\*\*\n\n1\. Open the \*\*Model Canvas\*\*.*?18\. Load pre-trained weights: use the \*\*Hardware Deployment Canvas → NIR Importer\*\* to load `cnn_sinabs\.nir` and sync weights into the Model canvas\.",
    "**Canvas: Model**\n\n1. Open the **Model Canvas**.\n2. Use the **Export / File Menu** → **Import NIR...** and select `cnn_sinabs.nir`. The entire CNN topology and pre-trained weights will be imported automatically.",
    content,
    flags=re.DOTALL
)

content = re.sub(
    r"\*\*Canvas: Eval\*\*\n\n19\. Navigate to the \*\*Eval Canvas\*\*.*?25\. Click \*\*Run Eval\*\*\. Expected result: ~97\.85%\.",
    "**Canvas: Eval**\n\n3. Navigate to the **Eval Canvas**.\n4. Add a **Data Loader** node. Set format to `tonic_nmnist`, `time_window_ms=1.0`. Set `batch_size=128`.\n5. Add a **State Reset** node.\n6. Add a **Forward Pass** node: `eval_mode=true`.\n7. Add an **Accuracy** node: `top_k=1`. The canvas will compute accuracy via spike count argmax across timesteps.\n8. Connect: **Data Loader → State Reset → Forward Pass → Accuracy**.\n9. Click **Run Eval**. Expected result: ~97.85%.",
    content,
    flags=re.DOTALL
)

content = re.sub(
    r"\*\*Canvas: Monitoring\*\*\n\n26\. Navigate to \*\*Monitoring\*\*.*?28\. Use the export button to save activity arrays if needed\.",
    "**Canvas: Monitoring**\n\n10. Navigate to **Monitoring**.\n11. Select the first **LIF** node in the graph. The **Spike Raster** panel will show layer-1 activity over time (equivalent to `act` saved in the notebook as `snnTorch_activity.npy`, shape `[T, B, 16, 16, 16]`).\n12. Use the export button to save activity arrays to `.npy` if needed.",
    content,
    flags=re.DOTALL
)

# Notebook 3
content = content.replace(
    "**Verdict: 🟡 MEDIUM-HIGH — model fully buildable; secondary blockers remain**",
    "**Verdict: ✅ HIGH — model fully buildable and training completely supported**"
)

content = content.replace(
    "| 3 | L1/L2 spike regularization (computed on hidden layer spike counts) — not confirmed as a Training canvas option | Moderate | Workaround: use only CE loss; regularization loss terms would be lost |",
    "| 3 | ~~L1/L2 spike regularization (computed on hidden layer spike counts) — not confirmed as a Training canvas option~~ | ~~Moderate~~ | ✅ **Fixed** — `l1SpikeReg` and `l2SpikeReg` nodes added to Training canvas palette. |"
)

content = content.replace(
    "| 6 | Surrogate gradient: `surrogate.fast_sigmoid(slope=N)` — the slope hyperparameter needs to be settable | Minor | Check Training canvas surrogate grad settings; slope is likely configurable |",
    "| 6 | ~~Surrogate gradient: `surrogate.fast_sigmoid(slope=N)` — the slope hyperparameter needs to be settable~~ | ~~Minor~~ | ✅ **Fixed** — `surrogateBackward` node now exposes `slope` field. |"
)

content = content.replace(
    "**Closest approximation if RSynaptic/Synaptic were added:**\n\nThe notebook would map cleanly to all 5 canvases. The full training pipeline (Adam + CE count loss + BPTT + L1/L2 reg + 500 epochs) is otherwise well-supported in CNLStudio's Training canvas.",
    "**Closest approximation:**\n\nThe notebook maps cleanly to all 5 canvases. The full training pipeline (Adam + CE count loss + BPTT + L1/L2 reg + 500 epochs) is well-supported in CNLStudio's Training canvas."
)

content = content.replace(
    "> Steps marked 🔴 are blocked by remaining secondary issues (L1/L2 reg in Training canvas). `cnl.RSynaptic` and `cnl.Synaptic` nodes are now available — steps previously marked 🔴 for those have been unblocked.\n\n**Canvas: Model**",
    "**Canvas: Model**"
)

content = content.replace(
    "14. 🔴 Add **L1 Spike Regularization** node: `weight=reg_l1`, applied to cnl.RSynaptic layer *(not yet available in Training canvas — P1 backlog item).*\n15. 🔴 Add **L2 Spike Regularization** node: `weight=reg_l2` *(may not be available; skip if absent)*.",
    "14. Add **l1SpikeReg** node: `weight=reg_l1`, applied to cnl.RSynaptic layer.\n15. Add **l2SpikeReg** node: `weight=reg_l2`, applied to cnl.RSynaptic layer."
)

# Notebook 4
content = content.replace(
    "**Verdict: 🟡 MEDIUM-HIGH — model now fully buildable; subtract-reset confirmed**",
    "**Verdict: ✅ HIGH — model now fully buildable; subtract-reset confirmed**"
)

content = content.replace(
    "> ⚠️ Steps marked 🔴 are blocked by missing neuron types.\n\n**Canvas: Model**",
    "**Canvas: Model**"
)

# Notebook 5
content = content.replace(
    "| 4 | `dt=1e-4` (Nengo simulation timestep) — this parameter must be configurable in the Nengo deployment target settings | Minor | Check Hardware Deployment canvas Nengo target options for a `dt` field |",
    "| 4 | ~~`dt=1e-4` (Nengo simulation timestep) — this parameter must be configurable in the Nengo deployment target settings~~ | ~~Minor~~ | ✅ **Fixed** — `nengo_dt` and `nengo_presentation_time` added to Nengo deployment target settings. |"
)

with open(file_path, "w") as f:
    f.write(content)

print("Document updated successfully.")
