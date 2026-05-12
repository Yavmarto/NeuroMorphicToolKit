# NMTK: Long-Horizon & Standalone Development Opportunities

This document identifies high-impact, long-horizon tasks that can be executed independently of the main NeuroMorphicToolKit (NMTK) repository. These tasks are designed to be **security-safe** (requiring no project secrets or proprietary data) and **architecturally decoupled** to allow for seamless re-integration.

---

## 1. The Neurohub Global Registry

**Nature:** Infrastructure / Community Service  
**Status in NMTK:** 0% (Conceptual Spec Ready)  
**Security Boundary:** Built entirely on the updated `neurohub_spec.md`. Requires no access to NMTK's internal backend logic or private data.  
**Re-integration Path:** NMTK's internal `Neurohub` module will act as a client. Supports sharing `.cnl` templates and full `.cnlspace` workspace sessions.

### Key Workstreams:
*   **Scalable Web Registry Backend:** A production-grade FastAPI service for artifact metadata, supporting models, datasets, and `.cnlspace` files.
*   **Community Portal (Next.js):** A standalone web frontend for model discovery and "Model Cards."
*   **Universal Artifact CLI (`neurohub-cli`):** A tool for publishing/pulling artifacts via `neurohub://` URIs.

---

## 2. Universal Sensory Encoding Library (NeuroSense-Lib)

**Nature:** Research / Software Library  
**Status in NMTK:** Neurosense Submodule (85%)  
**Security Boundary:** Purely algorithmic and mathematical. Based on public neuroscience papers regarding spike encoding (Rate, Temporal, TTFS). No access to proprietary sensor hardware or internal datasets required.  
**Re-integration Path:** This becomes a standard Python dependency for the `Neurosense` module, replacing fragmented internal encoding scripts.

### Key Workstreams:
*   **Multi-Modal Encoder Suite:** Implementing advanced encoders for Lidar, Radar, and bio-sensors (EMG/EEG).
*   **Hardware-Aware Quantization:** Algorithms that optimize spike density for 4-bit/8-bit hardware constraints (e.g., Akida).

---

## 3. NIR-Native Virtual Hardware (NIR-VM)

**Nature:** Software Engineering / Emulation  
**Status in NMTK:** Core Architecture (NIR-focused)  
**Security Boundary:** Based strictly on the public **Neuromorphic Intermediate Representation (NIR)** specification. Requires no access to physical Loihi/Akida chips or proprietary SDKs.  
**Re-integration Path:** Integrated as a "Virtual Backend" in the `Neurochip` and `Neurosim` modules, enabling users to "Run on Virtual Akida" without physical hardware.

### Key Workstreams:
*   **Bit-Accurate NIR Executor:** A standalone runtime that executes `.nir` graphs with cycle-accurate timing simulation.
*   **Telemetry Dashboard:** A visualizer for spike-train activity and power consumption estimates during virtual execution.

---

## 4. NeuroTrain: Optimization for NeuroStudio

**Nature:** Research / ML Engineering  
**Status in NMTK:** 0% (Conceptual Spec Ready)  
**Security Boundary:** Operates on public SNN frameworks (snnTorch, Norse, Lava) and the NIR specification. No access to NeuroStudio internal UI code needed.  
**Re-integration Path:** Integrated as a sequence of optimization passes within the `neurocnl` (NeuroStudio) compilation pipeline, alongside NeuroSim and NeuroChip.

### Key Workstreams:
*   **ANN-to-SNN Converter:** Converting standard models into NIR-compatible optimized SNNs.
*   **Quantization-Aware Fine-Tuning:** Hardware-specific weight optimization (Akida, Loihi, Xylo).
*   **Structural Optimization:** Pruning and topology merging for energy efficiency.

---

## 5. Standardized Neuromorphic Datasets

**Nature:** Data Science / Curation  
**Status in NMTK:** Distributed  
**Security Boundary:** Uses public datasets (ImageNet, LibriSpeech) and public encoding algorithms. No private data involved.  
**Re-integration Path:** Datasets are published to the Global Neurohub and become "One-Click Downloads" inside the NMTK UI.

### Key Workstreams:
*   **"Event-ification" Pipelines:** Massive-scale conversion of legacy datasets into high-quality event streams.
*   **Synthetic Data Generators:** Building physics-informed generators for robotic tactile and proprioceptive spike data.

---

## Summary of Security & Re-integration

| Task | Security Exposure | Primary Input | Integration Method |
| :--- | :--- | :--- | :--- |
| **Global Neurohub** | Low (Public Specs) | `neurohub_spec.md` | API Client in NMTK |
| **NeuroSense-Lib** | Zero (Math/Alg) | Neuroscience Papers | Python Package |
| **NIR-VM** | Zero (NIR Spec) | `nir` Specification | Virtual Backend Plugin |
| **NeuroTrain** | Zero (Frameworks) | Public SNN Frameworks | Compiler Optimization Pass |
| **Datasets** | Zero (Public Data) | ImageNet / LibriSpeech | Neurohub Registry URI |
