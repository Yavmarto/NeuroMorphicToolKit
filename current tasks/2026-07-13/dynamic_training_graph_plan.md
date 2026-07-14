# Dynamic Training Graph Executor for NMTK

## Motivation
Currently, both the Training and Eval visual canvases in NMTK create the illusion of sequential logic, but the backend uses them purely as configuration menus to populate hardcoded PyTorch loops (e.g., standard BPTT and static validation loops within `snntorch_adapter.py`).
To support Dr. Lunglmayr's highly specific mathematical training algorithms (like Linearized Bregman Iterations), custom evaluation metrics (like the Alexiewicz norm), and event-based DSP pipelines, we must upgrade the entire execution architecture.

This plan details how to refactor NMTK’s training adapter architecture into a true **Dynamic Graph Executor**. This will allow researchers to visually wire custom mathematical learning rules directly in the NeuroStudio canvas, and have the backend compile and execute the exact visual logic step-by-step. The architecture will abstract the execution to support all relevant frameworks capable of consuming NIR (Neuromorphic Intermediate Representation) models, specifically SNNTorch, Lava, and Norse.

## Implementation Steps

### 1. Training Graph Compiler (Backend Core)
Convert the loose `PipelinePhasesPayload` into a strict Execution DAG.

*   **File:** `neurocnl/neurocnl/training/graph_compiler.py`
*   **Role:** Implements `DynamicGraphCompiler`. Takes `PipelinePhasesPayload` (parsing both `train` and `eval` phase DAGs) and a `nir.NIRGraph` to generate an `ExecutionSequence` for both training and validation.
*   **Validation:** Topologically sorts the graph and validates execution order for both phases (e.g., Train: `ForwardPass` -> `Loss` -> `CustomGradient` -> `OptimizerStep`; Eval: `ForwardPass` -> `AlexiewiczMetric`).

### 2. Framework Execution Engines (NIR Backends)
Create a unified executor interface that maps DAG nodes to backend-specific tensor operations, replacing static loops.

*   **File:** `neurocnl/neurocnl/training/executors/base_executor.py`
    *   Defines `AbstractDynamicExecutor` with `execute_node()`, `forward()`, `compute_gradients()`, `apply_update()`.
*   **File:** `neurocnl/neurocnl/training/executors/snntorch_executor.py`
    *   Maps execution steps to SNNTorch/PyTorch tensors, natively supporting surrogate gradients.
*   **File:** `neurocnl/neurocnl/training/executors/lava_executor.py`
    *   Maps execution steps to Lava `Process` and `LearningRule` semantics for Intel Loihi compatibility.
*   **File:** `neurocnl/neurocnl/training_registry.py`
    *   Register the new dynamic executors (`snntorch_dynamic`, `lava_dynamic`).

### 3. Canvas Node Expansion (Frontend)
Add generic mathematical and optimization nodes to the UI.

*   **File:** `neurocnl/frontend/lib/models/canvas/pipeline_dag.dart`
    *   Add `PipelineDagNodeType` definitions: `lbiOptimizer` (Linearized Bregman Iterations), `customGradientStep`, `spikeDomainFilter`.
    *   Define strict I/O ports for these nodes.
*   **File:** `neurocnl/frontend/lib/widgets/canvas/pipeline_phase_canvas.dart`
    *   Add the visual UI components for the new dynamic training nodes so they can be placed on the canvas.

## Verification
*   Compile a standard BPTT loop using `snntorch_dynamic` to verify backward compatibility.
*   Compile a custom LBI loop targeting the PYNQ-Z2 hardware bridge, ensuring connection sparsity constraints are met before hardware handoff.
*   Verify that a dynamically compiled Eval loop correctly sequences multiple custom metric nodes (e.g., executing a standard MSE node followed immediately by a custom Alexiewicz bounds metric node) without relying on hardcoded `.eval()` evaluation sequences.
