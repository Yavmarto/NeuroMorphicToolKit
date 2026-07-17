# 0030: Dynamic Training Graph Executor

## Status
Superseded (reverted same-day; see Status Update below)

## Context
Currently, the `neurocnl` training and evaluation workflows utilize a static "Adapter" pattern (e.g., `snntorch_adapter.py`). While the frontend `NeuroStudio` canvas allows users to wire arbitrary training and evaluation nodes in a Directed Acyclic Graph (DAG), the backend ignores this topological wiring. Instead, the backend treats the DAG as a flat configuration dictionary and executes a hardcoded PyTorch BPTT (Backpropagation Through Time) loop. 

This hardcoding restricts the toolkit's scientific flexibility. It prevents the adoption of custom mathematical learning rules (e.g., Linearized Bregman Iterations), spike-domain DSP algorithms, and rigorous mathematical evaluation metrics (like the Alexiewicz norm) which require custom sequences of operations that diverge from standard deep learning loops.

## Decision
We will deprecate the static Training Adapter pattern and implement a **Dynamic Graph Executor**. 

1. **Graph Compilation**: The backend will compile both the `train` and `eval` `PipelinePhasesPayload` DAGs into strict `ExecutionSequence` plans using topological sorting (mirroring how the Model architecture is currently compiled).
2. **Abstract Executor**: We will introduce an `AbstractDynamicExecutor` to map dynamic execution nodes to specific NIR-supported framework tensor operations (e.g., SNNTorch, Lava, Norse).
3. **No Hardcoded Loops**: The `for epoch` loop will dynamically invoke nodes in the order they were wired in the UI. A custom optimizer node will intercept gradient calculations precisely where it is wired, bypassing standard framework behavior if necessary.

## Consequences
- **Positive**: Enables neuromorphic researchers to implement non-BPTT optimizers and novel mathematical bounds visually without modifying the core NMTK backend code.
- **Positive**: Brings training and evaluation behavior in line with the already-dynamic Model architecture compilation.
- **Negative**: Increases the complexity of the execution engine. Compiling and running a dynamic graph per epoch/step may introduce minor performance overhead in Python if not properly JIT-compiled.
- **Negative**: Deprecates existing adapter logic in `snntorch_adapter.py` and `sleep_pes_adapter.py`, requiring a migration of legacy prosthetic workflows to the new dynamic node format.

## Status Update (2026-07-16 audit)

This ADR's central decision — the `DynamicGraphCompiler` / `AbstractDynamicExecutor` / `SnnTorchExecutor` / `LavaExecutor` architecture — was implemented in the `neurocnl` submodule on 2026-07-13 (commits `6cad4560`→`b85aa611`), then fully deleted the same day by commit `676ebaf2` ("delete adapter-registry live-training engine (Part A)"). That commit's message states the logic was replaced by porting it into `notebook.py`'s codegen instead. None of `neurocnl/neurocnl/training/executors/`, `graph_compiler.py`, or `snntorch_adapter.py` exist in the repo today; `dag_schema.py`, `dag_topology.py`, `factory.py`, and `sleep_pes_adapter.py` remain under `neurocnl/neurocnl/training/` (alongside dataset-fixture and test helpers unrelated to this ADR).

Status should be read as **Superseded (in practice reverted)**, not Accepted. Readers looking for the live equivalent of this ADR's decision should check the codegen logic in `neurocnl/backend/app/routers/notebook.py`.
