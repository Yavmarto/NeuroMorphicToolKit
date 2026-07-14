# CNLStudio Replication Guide: snnTorch Tutorials

**Date:** 13 July 2026
**Target:** `Spiking-Neural-Networks-Tutorials-main/tutorial_3_feedforward_snn.ipynb`

This guide explains how to replicate the core Feedforward Spiking Neural Network (FCN) from snnTorch Tutorial 3 using the NeuroMorphicToolKit (NMTK) visual interface (CNLStudio).

## Architecture Mapping
The snnTorch tutorial defines a 3-layer fully-connected network (`784 → 1000 → 10`):
```python
fc1 = nn.Linear(784, 1000)
lif1 = snn.Leaky(beta=0.99)
fc2 = nn.Linear(1000, 10)
lif2 = snn.Leaky(beta=0.99)
```

### Parameter Conversions for CNLStudio:
*   **Linear Nodes:** snnTorch randomly initializes weights. In CNLStudio's UI simulator, the `Linear` node accepts a `weight_fill` scalar. We'll use a small value like `0.05` to ensure spikes propagate forward without saturating instantly.
*   **LIF Nodes:** The `snn.Leaky` neuron uses a `beta` (decay rate) of `0.99` and a default `threshold` of `1.0`. CNLStudio parameterizes LIF using biological constants. Assuming a discrete time-step $\Delta t = 0.01$, the relation is roughly $\beta \approx 1 - \frac{\Delta t}{\tau}$. Thus, $\tau = \frac{\Delta t}{1 - \beta} = \frac{0.01}{0.01} = 1.0$.
    *   `tau` = 1.0
    *   `threshold` = 1.0
    *   `r` = 1 (default)
    *   `v_leak` = 0 (default)

---

## UI Replication Steps

### 1. Canvas: Model
Open the **Model** canvas in CNLStudio and add the following nodes:

1.  **Input Node:** Set `n_neurons = 784`
2.  **Linear Node:** Set `rows = 784`, `cols = 1000`, `weight_fill = 0.05`
3.  **LIF Node:** Set `n_neurons = 1000`, `tau = 1.0`, `threshold = 1.0`, `r = 1`, `v_leak = 0`
4.  **Linear Node:** Set `rows = 1000`, `cols = 10`, `weight_fill = 0.05`
5.  **LIF Node:** Set `n_neurons = 10`, `tau = 1.0`, `threshold = 1.0`, `r = 1`, `v_leak = 0`
6.  **Output Node:** Set `n_neurons = 10`

**Wire them sequentially:**
`Input` → `Linear` → `LIF` → `Linear` → `LIF` → `Output`

### 2. Canvas: Train (Exporting to NIR)
To export this constructed model as a standard NIR graph:

1.  Open the **Train** canvas.
2.  Add a **NIR Exporter Node:** Set `filename = snntorch_fcn.nir`.
3.  Connect the `model` output port of a **Forward Pass** node into the `model` input port of the **NIR Exporter**.

*(Note: snnTorch Tutorial 3 does not include a training loop, so we only use the Train canvas to export the untrained graph architecture).*

### 3. Canvas: Eval
The snnTorch tutorial generates random rate-coded spikes: `spikegen.rate_conv(torch.rand((200, 784)))`. We can emulate this random noise injection in CNLStudio using a Spike Generator.

1.  **Spike Generator Node:** Set `type = poisson`, `n_neurons = 784`, `rate = 0.5` (representing average random rate).
2.  **State Reset Node:** Add to canvas (leave input port unconnected as it acts globally on the compiled model).
3.  **Forward Pass Node:** Set `eval_mode = true`.
4.  **Connect Eval Nodes:**
    *   `Spike Generator` (`spikes` out) → `Forward Pass` (`input` in)
    *   `State Reset` (`model` out) → `Forward Pass` (`model` in)

*(Optional)* If you wish to use the exact `torch.rand` stimulus from the notebook instead of the Spike Generator, you can export it to a `.pt` file using a Python script and replace the Spike Generator node with a **Data Loader** node (`format=pt`).

### 4. Results Step: Dynamics
Navigate to the **Results** step (UI Step 6) to run the simulation and open the **Dynamics** tab.
Select the final **LIF** node (the 10-neuron output layer). The Spike Raster panel here will mirror the `spikeplot.spike_count` and `splt.traces` visualizations shown at the end of snnTorch Tutorial 3, allowing you to observe which neurons fired.
