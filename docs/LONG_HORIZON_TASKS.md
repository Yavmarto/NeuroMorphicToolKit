# NMTK: Long-Horizon Strategic Initiatives

This document identifies high-impact, long-horizon tasks that advance the core capabilities of the NeuroMorphicToolKit (NMTK) repository. These initiatives represent major architectural expansions and require deep integration across the monorepo's modules.

---

## 1. The Neurohub Global Registry

**Nature:** Infrastructure / Service  
**Status:** Conceptual Spec Ready (`neurohub_spec.md`)  
**Architectural Integration:** Developed within the NMTK monorepo, expanding the existing `Neurohub` module into a full-fledged backend service and frontend portal. Supports native integration for sharing `.cnl` templates and full `.cnlspace` workspace sessions directly from the NMTK UI.

### Key Workstreams:
*   **Scalable Web Registry Backend:** Implement a production-grade FastAPI service handling artifact metadata, models, datasets, and `.cnlspace` files.
*   **Community Portal (Next.js/Flutter):** Build out the web frontend for model discovery, incorporating "Model Cards" and community features.
*   **Universal Artifact CLI (`neurohub-cli`):** Extend the `neurocli` or create a dedicated tool for publishing/pulling artifacts via `neurohub://` URIs seamlessly within the development workflow.

---

## 2. Universal Sensory Encoding Library (NeuroSense-Lib)

**Nature:** Core Library / Research  
**Status:** Neurosense Submodule (85%)  
**Architectural Integration:** Consolidating fragmented internal encoding scripts into a robust, unified Python library within the `Neurosense` module. This library will serve as the standard dependency for all sensory transformations across NMTK.

### Key Workstreams:
*   **Multi-Modal Encoder Suite:** Implement and optimize advanced encoders for Lidar, Radar, and bio-sensors (EMG/EEG), leveraging the existing codebase context.
*   **Hardware-Aware Quantization:** Develop algorithms that optimize spike density for 4-bit/8-bit hardware constraints (e.g., Akida, Loihi), directly hooking into the `Neurochip` hardware profiles.

---

## 3. NIR-Native Virtual Hardware (NIR-VM)

**Nature:** Software Engineering / Emulation  
**Status:** Core Architecture (NIR-focused)  
**Architectural Integration:** Deeply embedded as a "Virtual Backend" within the `Neurochip` and `neurocnl` modules. This allows users to test and profile models natively within NMTK without requiring physical hardware deployment.

### Key Workstreams:
*   **Bit-Accurate NIR Executor:** Build a standalone runtime within the repository that executes `.nir` graphs with cycle-accurate timing simulation, validating against our existing hardware interfaces.
*   **Telemetry Dashboard:** Extend the `nmtk_ui_core` and `neurocnl` frontend to visualize spike-train activity and power consumption estimates during virtual execution.

---

## 4. NeuroTrain: Optimization for NeuroStudio

**Nature:** ML Engineering / Compilation Pipeline  
**Status:** Conceptual Spec Ready  
**Architectural Integration:** Integrated as a sequence of optimization passes directly within the `neurocnl` compilation pipeline. This bridges the gap between public SNN frameworks (snnTorch, Norse, Lava) and NMTK's hardware backends.

### Key Workstreams:
*   **ANN-to-SNN Converter:** Build native tooling for converting standard models into NIR-compatible optimized SNNs within the toolkit.
*   **Quantization-Aware Fine-Tuning:** Implement hardware-specific weight optimization utilizing NMTK's internal hardware configuration profiles (Akida, Loihi, Xylo).
*   **Structural Optimization:** Add pruning and topology merging algorithms for energy efficiency directly to the CNL materializer.

---

## 5. Standardized Neuromorphic Datasets

**Nature:** Data Engineering / Pipeline Automation  
**Status:** Distributed (Active Development in Neurobench)  
**Architectural Integration:** Tightly coupled with the `Neurobench` module for validation and the `Neurohub` module for hosting. Integrated directly into the NMTK UI for "One-Click Downloads" and seamless experiment tracking.

### Key Workstreams:
*   **"Event-ification" Pipelines:** Centralize and scale the conversion of legacy datasets into high-quality event streams using NMTK's internal processing utilities.
*   **Synthetic Data Generators:** Integrate physics-informed generators for robotic tactile and proprioceptive spike data into the `Neurobench` CLI and validation suites.

---

## Summary of Strategic Initiatives

| Task | Primary Module | Core Focus | Architectural Impact |
| :--- | :--- | :--- | :--- |
| **Global Neurohub** | `Neurohub` | Ecosystem scaling | Registry service & artifact sharing |
| **NeuroSense-Lib** | `Neurosense` | Sensory encoding | Unified library for signal-to-spike |
| **NIR-VM** | `Neurochip` / `neurocnl` | Hardware emulation | Cycle-accurate virtual execution |
| **NeuroTrain** | `neurocnl` | Model optimization | Built-in SNN training & compilation passes |
| **Datasets** | `Neurobench` | Benchmarking | Standardized data pipelines & hosting |
