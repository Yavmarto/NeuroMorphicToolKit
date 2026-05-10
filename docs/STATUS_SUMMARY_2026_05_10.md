# NeuroMorphicToolKit Status Summary - May 10, 2026

This document summarizes the current git status and functional changes across the main repository and all submodules.

## Repository Status Overview
*   **Main Repo (`NeuroMorphicToolKit`)**: Several new documentation files and architecture plans have been added/staged.
*   **Submodules**: 5 out of 6 submodules have active changes (modified or untracked files).

---

## Module-by-Module Summary

### 1. NeuroStudio (`neurocnl`)
*   **What Changed**: 
    *   **Backend**: Significant updates to CNL (Computational Network Language) parsing, Intermediate Representation (IR) lowering, and NIR (Neuromorphic Intermediate Representation) export. Added timing validation and array support.
    *   **Frontend**: Improved synchronization between the text editor and the visual canvas. Updated property panels and component libraries.
*   **How to try in UI**: 
    *   Open **NeuroStudio** from the launcher.
    *   Test the **Network Canvas** by dragging components; verify that changes reflect in the **CNL Editor** sidebar.
    *   Try exporting a designed network to NIR via the Export menu.

### 2. Bench (`Neurobench`)
*   **What Changed**: 
    *   New automated **Markdown Report** generation for benchmark results.
    *   Added **Cross-Platform Validation** and **Metric Normalization** services.
    *   Updated the hardware benchmark runner for better reliability.
*   **How to try in UI**: 
    *   Navigate to the **Bench** module.
    *   Run a standard benchmark suite; once finished, look for the option to **Generate Markdown Report** to see the new structured output.

### 3. NeuroChip (`Neurochip`)
*   **What Changed**: 
    *   Refined the **Lava hardware integration** logic.
    *   Cleaned up old integration plans into an `archive/` directory.
*   **How to try in UI**: 
    *   Use the **NeuroChip** module to interface with Akida or Pynq hardware.
    *   The improvements are largely "under the hood" for better deployment stability.

### 4. NeuroSense (`Neurosense`)
*   **What Changed**: 
    *   Enhanced the **Event Encoder** service for converting sensory data to spikes.
    *   Updated support for **Prophesee** cameras and **Pynq** edge sensors.
*   **How to try in UI**: 
    *   Open **NeuroSense**.
    *   Load a vision or audio dataset and use the **Encoder** settings to preview spike-train generation.

### 5. Share (`Neurohub`)
*   **What Changed**: 
    *   Implemented a new **Model Zoo Manifest** service to manage shared SNN models.
*   **How to try in UI**: 
    *   Open the **Share** module (Neurohub).
    *   Browse the available models; the list is now driven by the new manifest service.

---

## How to Launch & Test Everything

To see all these changes in the unified interface, follow these steps:

1.  **Start the Backends (Docker)**:
    ```bash
    docker compose up --build
    ```
    *This will spin up the updated Python services for all modules.*

2.  **Run the Desktop Launcher**:
    ```bash
    cd nmtk/neuro_toolkit
    flutter run -d macos
    ```
    *This launches the main Flutter dashboard where you can navigate between the modules.*

3.  **Run Smoke Tests**:
    To verify that all backend endpoints are healthy after your changes:
    ```bash
    python3 scripts/backend_endpoint_smoke.py
    ```

> [!TIP]
> You can also run `bash scripts/demo_smoke_test.sh` for a quick end-to-end verification of the primary workflows across the toolkit.
