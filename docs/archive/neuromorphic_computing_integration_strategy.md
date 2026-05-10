# Neuromorphic Computing Integration Strategy

This document outlines the strategic implementation plan for incorporating the key findings from the "Neuromorphic Computing: Current Challenges and Attempted Solutions" research report into the NeuroMorphicToolKit (NMTK). The primary goal is to align NMTK's capabilities (CNL and NIR) with the industry's need for accessible, standardized, and hybrid neuromorphic development tools.

## User Review Required

> [!IMPORTANT]
> Please review this strategic roadmap. Implementing all these features represents a significant expansion of NMTK's scope. We need to prioritize which of these six initiatives we should tackle first.

## Execution Plan

The implementation order, rationale, and local-vs-Deerflow execution split for these six initiatives are documented in [neuromorphic_computing_six_initiatives_plan.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/neuromorphic_computing_six_initiatives_plan.md).
For the current NeuroCNL-specific status and prioritized next steps, see [neurocnl_status_and_priorities.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/neurocnl_status_and_priorities.md).

Recommended implementation order:

1. Native NeuroBench Integration
2. Standardized Event Data Pipelines
3. SNN Training Abstraction Layer
4. CNL High-Level Abstractions
5. Robust NIR Hardware Mapping
6. Hybrid Workload Support

## Open Questions

> [!QUESTION]
> 1.  **Prioritization:** Which of the following 6 proposed implementation areas is the highest priority for the current sprint or release cycle?
> 2.  **Existing Integrations:** Repo check: we are not starting fully fresh. There is already a training-adapter registry surface in `neurocnl`, direct NIR export/lowering, NeuroBench metric normalization, and NeuroSense replay/event helpers to build on.
> 3.  **Hybrid Processing:** Repo check: no explicit runtime orchestrator for hybrid CPU-neuromorphic execution graphs was found. This initiative is still design-stage.

## CNL Status

NeuroCNL-specific implementation status, evidence, and priority ordering now live in [neurocnl_status_and_priorities.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/neurocnl_status_and_priorities.md).

## Proposed Changes

The following are the strategic implementation pillars proposed for NMTK.

---

### 1. CNL High-Level Abstractions ("Keras for Neuromorphic")

**Goal:** Abstract the complexities of temporal dynamics and spike synchronization to lower the barrier to entry.

*   [ ] **Design a unified API:** Implement simple, high-level methods (e.g., `compile()`, `fit()`, `evaluate()`) in the Computational Network Language (CNL) that hide the time-step iterations and membrane potential state management from the user.
*   [ ] **Documentation & Tutorials:** Create "migration guides" tailored for developers coming from standard PyTorch or TensorFlow backgrounds.

---

### 2. SNN Training Abstraction Layer ("Bring Your Own Training")

**Goal:** Support diverse training methodologies without locking users into a single paradigm.

*   [x] **Registry groundwork:** `neurocnl.training_registry` already provides adapter selection, capability listing, mode validation, and fail-closed dispatch semantics.
*   [ ] **Abstract Backends:** Concrete adapters for underlying SNN training libraries (e.g., `snnTorch`, `SpikingJelly`) still need to be implemented.
*   [ ] **ANN-to-SNN Pipeline:** A dedicated module for standard ANN-to-SNN conversion workflows is still needed.

---

### 3. Robust NIR Hardware Mapping

**Goal:** Ensure the Neuromorphic Intermediate Representation (NIR) handles hardware heterogeneity automatically.

*   [x] **Current groundwork:** direct CNL → IR → NIR export, honest lowering summaries, and backend support planning already exist.
*   [x] **Current hardware checks:** Akida, PYNQ, and Teensy exportability/deployability constraints are already modeled.
*   [ ] **Compiler Passes:** Intelligent partitioning for large networks across multiple chips is still needed.
*   [ ] **Hardware-Specific Quantization:** Quantization-aware training or post-training quantization integration is still needed.

---

### 4. Native NeuroBench Integration

**Goal:** Provide trusted, standardized metrics for both algorithm accuracy and system efficiency.

*   [x] **Benchmarking Suite groundwork:** NeuroBench already has benchmark runners, result storage, and metric normalization for core benchmark flows.
*   [ ] **Efficiency Metrics:** A first-class CNL `evaluate()` surface with complete energy, latency, and memory reporting is still needed.

---

### 5. Standardized Event Data Pipelines

**Goal:** Streamline the ingestion and preprocessing of event-based sensor data.

*   [x] **Current groundwork:** event batching, dense spike-tensor conversion, and NeuroSense replay-artifact preparation already exist.
*   [ ] **DVS Data Loaders:** Standardized dataloaders for N-MNIST, DVS-Gesture, DDD17, and similar datasets are still needed.
*   [ ] **Encoding Strategies:** Dataset-oriented preprocessing beyond the current helpers still needs to be built out.

---

### 6. Hybrid Workload Support

**Goal:** Enable seamless execution of mixed conventional/neuromorphic models.

*   [ ] **Heterogeneous Execution Graphs:** Extend CNL to define computational graphs where specific blocks (e.g., feature extraction) are targeted for neuromorphic backends, while others (e.g., classification heads) target conventional CPUs/GPUs.
*   [ ] **Automatic Data Conversion:** Implement intermediate layers that automatically handle the conversion between continuous tensor data and discrete spike trains as data flows between heterogeneous blocks.

## Verification Plan

### Automated Tests
*   Unit tests for new high-level CNL APIs to ensure they correctly wrap underlying complex SNN logic.
*   Integration tests validating the abstraction adapters for different training backends (e.g., ensuring a model trains successfully regardless of whether `snnTorch` or a custom ANN-to-SNN converter is used).
*   Benchmarking tests running the integrated NeuroBench suite against a known baseline to verify metric accuracy.

### Manual Verification
*   Create a complete, end-to-end tutorial script (e.g., training on N-MNIST) using the new high-level APIs to ensure it is demonstrably easier than writing raw SNN code.
*   User testing (if possible) with developers familiar with PyTorch but not neuromorphic computing, to evaluate the "Keras-like" usability.
