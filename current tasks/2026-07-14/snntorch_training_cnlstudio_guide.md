# CNLStudio Replication Guide: snnTorch Training

**Date:** 14 July 2026
**Target:** `paper/03_rnn/Braille_training_snntorch.ipynb`

This guide explains how to replicate a full end-to-end training of a Spiking RNN (for Braille gesture recognition) using the NeuroMorphicToolKit (NMTK) visual interface (CNLStudio). This is one of the simplest notebooks available in the repository that performs actual model training (Adam optimizer, surrogate gradients, backpropagation through time).

## Architecture Mapping
The snnTorch tutorial defines an RNN that classifies 7 letter categories from 12-channel tactile spike inputs over 256 timesteps.
```python
# Conceptual Architecture
Input (12) → Linear(12 → 40, no bias)
           → RSynaptic(alpha=0.75, beta=0.85, recurrent=True, reset="subtract") [40]
           → Linear(40 → 7, no bias)
           → Synaptic(alpha=0.45, beta=0.7, reset="subtract") [7]
           → Output (7)
```

### Parameter Conversions for CNLStudio:
*   The original code uses a JSON configuration file (`paper/03_rnn/data/parameters_noDelay_noBias_ref_subtract.json`). For the CNLStudio UI, you will enter these values manually. The values are: `N_hidden = 40`, `alpha_r = 0.75`, `beta_r = 0.85`, `alpha_out = 0.45`, `beta_out = 0.7`, `lr = 0.001`, `slope = 5`, `reg_l1 = 0.001`, and `reg_l2 = 0.000001`.
*   **Recurrent Nodes:** The `snn.RSynaptic` neuron is mapped to the `cnl.RSynaptic` node, which already includes the internal recurrent Linear layer (no separate recurrent edge needed).

---

## UI Replication Steps

### 1. Canvas: Model
Open the **Model** canvas in CNLStudio and construct the network:

1.  **Input Node:** Set `Size = 12`.
2.  **Linear Node:** Set `Cols = 12` and `Rows = 40` (Note: Linear node has no bias parameter in the UI).
3.  **cnl.RSynaptic Node:** Set `Neurons = 40`, `Alpha (syn decay) = 0.75`, `Beta (mem decay) = 0.85`, `Reset = "subtract"`, `Use Bias = false`.
4.  **Linear Node:** Set `Cols = 40` and `Rows = 7`.
5.  **cnl.Synaptic Node:** Set `Neurons = 7`, `Alpha (syn decay) = 0.45`, `Beta (mem decay) = 0.7`, `Reset = "subtract"`.
6.  **Output Node:** Set `Size = 7`.

**Wire them sequentially:**
`Input` → `Linear` → `cnl.RSynaptic` → `Linear` → `cnl.Synaptic` → `Output`

### 2. Canvas: Training
Navigate to the **Training** canvas to set up the learning pipeline:

1.  **Data Loader (Train):** Add a node. Set `Format = pt`, `Dataset Path = paper/03_rnn/data/ds_train.pt`, `Batch Size = 64`, `Shuffle = true`.
2.  **State Reset Node:** Add to canvas (resets states at each batch start).
3.  **Forward Pass Node:** Add to canvas (no parameters to set).
4.  **Time Loop Node:** Add to canvas and set `Time Steps = 256`.
5.  **CE Count Loss Node:** Add to canvas (equivalent to `SF.ce_count_loss()`).
6.  **l1SpikeReg Node:** Set `Regularization Weight = 0.001` and `Target Layer (blank = all hidden) = cnl.RSynaptic`.
7.  **l2SpikeReg Node:** Set `Regularization Weight = 0.000001` and `Target Layer (blank = all hidden) = cnl.RSynaptic`.
8.  **Surrogate Backward Node:** Set `Function = fast_sigmoid`, `Slope = 5`.
9.  **Adam Optimizer Node:** Set `Learning Rate = 0.001`.
10. **Data Loader (Val):** Add a node. Set `Format = pt`, `Dataset Path = paper/03_rnn/data/ds_val.pt`, `Batch Size = 64`, `Shuffle = false`. Connect to a **Validation Loop** node.
11. **Connect Training Nodes:**
    *   `Data Loader (Train)` (output: `data`) → `Forward Pass` (input: `input`)
    *   `Data Loader (Train)` (output: `labels`) → `CE Loss` (input: `labels`)
    *   `State Reset` (output: `model`) → `Forward Pass` (input: `model`)
    *   `Forward Pass` (output: `spikes`) → `Time Loop` (input: `spikes`)
    *   `Time Loop` (output: `spikes`) → `CE Loss` (input: `spikes`)
    *   `Time Loop` (output: `spikes`) → `l1SpikeReg` (input: `spikes`)
    *   `Time Loop` (output: `spikes`) → `l2SpikeReg` (input: `spikes`)
    *   `CE Loss` (output: `loss`) → `l1SpikeReg` (input: `loss_in`)
    *   `l1SpikeReg` (output: `loss`) → `l2SpikeReg` (input: `loss_in`)
    *   `l2SpikeReg` (output: `loss`) → `Surrogate Backward` (input: `loss`)
    *   `Surrogate Backward` (output: `gradients`) → `Optimizer` (input: `gradients`)
    *   `Optimizer` (output: `model`) → `Validation Loop` (input: `model`)
    *   `Data Loader (Val)` (output: `data`) → `Validation Loop` (input: `val_data`)
12. **Validation Loop Node:** Ensure `Epochs = 500` and `Save Best Checkpoint` is enabled in the property panel (configured in step 10).
13. **Start Training:** Proceed to **Step 5 (Jupyter Lab)** to generate and review the training code, then execute it, or go to **Step 6 (Results)** to run the training and observe the live loss/accuracy curves.

### 3. Canvas: Eval
After training completes, navigate to the **Eval** canvas to test the model:

1.  **Data Loader (Test):** Set `Format = pt`, `Dataset Path = paper/03_rnn/data/ds_test.pt`, `Batch Size = 64`, `Shuffle = false`, and enable `Load Best Checkpoint`.
2.  **State Reset Node:** Add to canvas.
3.  **Forward Pass Node:** Add to canvas.
4.  **Accuracy Node:** Add to canvas.
5.  **Connect Eval Nodes:**
    *   `Data Loader (Test)` (output: `data`) → `Forward Pass` (input: `input`)
    *   `Data Loader (Test)` (output: `labels`) → `Accuracy` (input: `labels`)
    *   `State Reset` (output: `model`) → `Forward Pass` (input: `model`)
    *   `Forward Pass` (output: `spikes`) → `Accuracy` (input: `spikes`)
6.  **Start Evaluation:** Proceed to **Step 5 (Jupyter Lab)** or **Step 6 (Results)** to execute the evaluation and observe the results (expected test accuracy is ~92%).

### 4. Results Step: Dynamics
Navigate to the **Results** step (UI Step 6) and open the **Dynamics** tab.
Select the **cnl.RSynaptic** hidden layer node to view its Spike Raster and inspect the recurrent spike activity patterns learned during training.
