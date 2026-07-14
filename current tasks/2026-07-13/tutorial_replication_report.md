# SNN Tutorial Replication Report for NeuroMorphicToolKit (NMTK)

This report analyzes the newly added subfolders within the `paper` directory and ranks their replication potential using the native features of the **NeuroMorphicToolKit (NMTK)** suite.

## Analysis of Added Repositories

Three new directories containing SNN tutorials were added to the `paper` folder:
1. `Spiking-Neural-Networks-Tutorials-main` (snnTorch tutorials)
2. `notebooks-main` (Norse tutorials)
3. `spikingjelly-master` (SpikingJelly framework and tutorials)

NMTK provides several modules that natively support the replication of these tutorials without requiring external setup:
*   **Notebooks (Jupyter):** Pre-configured kernels for snnTorch, Lava, and PyTorch.
*   **Neurosense:** Dedicated module for sensory processing and spike encoding.
*   **NeuroStudio / neurocnl:** Visual and specification-based SNN building with NIR (Neuromorphic Intermediate Representation) export.
*   **Neurobench:** Standardized benchmarking.

---

## Ranking & Replication Strategy

### 🥇 Rank 1: snnTorch Tutorials (`Spiking-Neural-Networks-Tutorials-main`)
**Replication Potential: Exceptional (Out-of-the-Box)**

*   **Why it ranks first:** NMTK explicitly ships with a pre-configured **snnTorch kernel** in its embedded Jupyter Notebooks module. You can open these `.ipynb` files and run them immediately with zero setup.
*   **Replication via NMTK Modules:**
    *   `tutorial_1_spikegen.ipynb` (Spike Encoding): Can be visually replicated and explored using the **Neurosense** module, which specializes in converting traditional data (vision, audio) into spike trains.
    *   `tutorial_2` through `tutorial_6` (LIF, FCN, CNN): These networks can be constructed visually in **NeuroStudio**, validated, and then exported via NIR. The existing `paper/01_lif/lif_snntorch.ipynb` shows that integration is already proven.

### 🥈 Rank 2: Norse Tutorials (`notebooks-main`)
**Replication Potential: Very High**

*   **Why it ranks second:** Norse is designed as "PyTorch + Spikes." Because NMTK's Notebooks module includes a pre-configured PyTorch kernel, running Norse is highly seamless. The `paper` directory already contains successful Norse integrations (`lif_norse.ipynb`).
*   **Replication via NMTK Modules:**
    *   Tutorials like `intro_norse.ipynb` and `single-neuron-experiments.ipynb` are excellent candidates for building within **NeuroStudio** using English specifications and exporting to NIR. 
    *   More complex examples like `mnist_classifiers.ipynb` can be executed within the Notebooks environment and subsequently evaluated using **Neurobench** to compare Norse's performance against snnTorch or Lava models.

### 🥉 Rank 3: SpikingJelly (`spikingjelly-master`)
**Replication Potential: High (Requires minor setup)**

*   **Why it ranks third:** SpikingJelly is an incredibly powerful framework, but unlike snnTorch and Lava, it is not explicitly listed as having a pre-configured kernel in NMTK. It runs on PyTorch, so it will work flawlessly in the Notebooks module once `pip install spikingjelly` is executed in the environment.
*   **Replication via NMTK Modules:**
    *   SpikingJelly excels at **ANN-to-SNN conversion** and deep spiking networks (ResNet, VGG). While these can run in NMTK Notebooks, visually replicating ANN-to-SNN conversion within NeuroStudio might require leveraging the `Neurohub` community registry for pre-trained models rather than building from scratch.
    *   These tutorials will be best utilized inside NMTK's Jupyter environment to build advanced models, which can then be profiled using **Neurobench**.

---

## Next Steps for NMTK Integration

To maximize the value of these newly added resources in NMTK, the recommended workflow is:
1.  **Launch the NMTK Desktop App** and open the embedded **Notebooks** module.
2.  Open `tutorial_1_spikegen.ipynb` from the snnTorch folder to test the pre-configured environment.
3.  Attempt to map the spike encoding techniques shown in the tutorial directly into the **Neurosense** UI to create a reusable NMTK pipeline.
