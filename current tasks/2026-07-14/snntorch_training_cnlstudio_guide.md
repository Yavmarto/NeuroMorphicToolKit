# CNLStudio Replication Guide: snnTorch Training

**Date:** 14 July 2026
**Target:** `paper/03_rnn/Braille_training_snntorch.ipynb`

This guide explains how to replicate a full end-to-end training of a Spiking RNN (for Braille gesture recognition) using the NeuroMorphicToolKit (NMTK) visual interface (CNLStudio). This is one of the simplest notebooks available in the repository that performs actual model training (Adam optimizer, surrogate gradients, backpropagation through time).

## Architecture Mapping
The snnTorch tutorial defines an RNN that classifies 7 letter categories from 12-channel tactile spike inputs over 256 timesteps.
```python
# Conceptual Architecture
Input (12) → Linear(12 → N_hidden, no bias)
           → RSynaptic(alpha_r, beta_r, recurrent=True, reset="subtract") [N_hidden]
           → Linear(N_hidden → 7, no bias)
           → Synaptic(alpha_out, beta_out, reset="subtract") [7]
           → Output (7)
```

### Parameter Conversions for CNLStudio:
*   Instead of manually setting parameters, you can use the built-in **Import Config...** button in the Export workspace panel to load the hyperparameters from `paper/03_rnn/data/parameters_noDelay_noBias_ref_subtract.json`. This JSON provides `N_hidden`, `alpha_r`, `beta_r`, `alpha_out`, `beta_out`, `lr`, `slope`, `reg_l1`, and `reg_l2`.
*   **Recurrent Nodes:** The `snn.RSynaptic` neuron is mapped to the `cnl.RSynaptic` node, which already includes the internal recurrent Linear layer (no separate recurrent edge needed).

---

## UI Replication Steps

### 1. Canvas: Model
Open the **Model** canvas in CNLStudio and construct the network:

1.  **Input Node:** Set `n_neurons = 12`.
2.  **Linear Node:** Set `in_features = 12`, `out_features = N_hidden` (from JSON), disable bias.
3.  **cnl.RSynaptic Node:** Set `alpha = alpha_r`, `beta = beta_r`, `reset_mechanism = "subtract"`, `use_bias = false`.
4.  **Linear Node:** Set `in_features = N_hidden`, `out_features = 7`, disable bias.
5.  **cnl.Synaptic Node:** Set `alpha = alpha_out`, `beta = beta_out`, `reset_mechanism = "subtract"`.
6.  **Output Node:** Set `n_neurons = 7`.

**Wire them sequentially:**
`Input` → `Linear` → `cnl.RSynaptic` → `Linear` → `cnl.Synaptic` → `Output`

### 2. Canvas: Training
Navigate to the **Training** canvas to set up the learning pipeline:

1.  **Data Loader (Train):** Add a node. Set `format = pt`, `dataset_path = paper/03_rnn/data/ds_train.pt`, `batch_size = 64`, `shuffle = true`.
2.  **State Reset Node:** Add to canvas (resets states at each batch start).
3.  **Forward Pass Node:** Set `num_steps = 256`.
4.  **CE Count Loss Node:** Add to canvas (equivalent to `SF.ce_count_loss()`).
5.  **l1SpikeReg Node:** Set `weight = reg_l1`, apply to `cnl.RSynaptic` layer.
6.  **l2SpikeReg Node:** Set `weight = reg_l2`, apply to `cnl.RSynaptic` layer.
7.  **Backward Pass Node:** Set algorithm = `fast_sigmoid`, `slope = slope` (from JSON).
8.  **Adam Optimizer Node:** Set `lr = lr` (from JSON), `betas = (0.9, 0.999)`.
9.  **Data Loader (Val):** Add a node. Set `format = pt`, `dataset_path = paper/03_rnn/data/ds_val.pt`, `batch_size = 64`, `shuffle = false`. Connect to a **Validation Loop** node.
10. **Connect Training Nodes:**
    *   `Data Loader (Train)` (`data`) → `Forward Pass` (`input`)
    *   `Data Loader (Train)` (`labels`) → `CE Loss` (`labels`)
    *   `State Reset` (`model` out) → `Forward Pass` (`model` in)
    *   `Forward Pass` (`spikes`) → `CE Loss` (`spikes`)
    *   `Forward Pass` (`model` out) → `Backward Pass` (`model` in)
    *   `CE Loss` (`loss`) → `Backward Pass` (`loss`)
    *   `Backward Pass` (`model` out) → `Optimizer` (`model` in)
11. **Configure Execution:** Set **Epochs = 500** in the header. Enable **Best Checkpoint Save**.
12. **Start:** Click **Start Training** and observe the live loss/accuracy curves.

### 3. Canvas: Eval
After training completes, navigate to the **Eval** canvas to test the model:

1.  **Data Loader (Test):** Set `format = pt`, `dataset_path = paper/03_rnn/data/ds_test.pt`, `batch_size = 64`, `shuffle = false`.
2.  **Load Checkpoint:** Load the best weights saved during training.
3.  **Accuracy Node:** Add to canvas.
4.  **Connect Eval Nodes:** (Similar to training, connect `Data Loader` to `Forward Pass`, and `spikes`/`labels` to `Accuracy`).
5.  Run the evaluation. Expected test accuracy is ~92%.

### 4. Results Step: Dynamics
Navigate to the **Results** step (UI Step 6) and open the **Dynamics** tab.
Select the **cnl.RSynaptic** hidden layer node to view its Spike Raster and inspect the recurrent spike activity patterns learned during training.
