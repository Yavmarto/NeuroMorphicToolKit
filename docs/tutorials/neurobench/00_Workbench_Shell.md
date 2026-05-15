# 00: Workbench Shell

Neurobench is the evaluation and regression suite of the Neuromorphic Toolkit. Its primary user interface is the **Workbench Shell**.

## Core Layout

The `workbench_shell` provides the structural scaffold for the application.

1. **Global Navigation Bar:**
   - Usually positioned at the top or side, allowing users to switch between the major functional screens:
     - `Benchmarks`
     - `Robustness`
     - `Comparison`
     - `Regression Trends`
     - `Reports`
2. **Context Header:**
   - Displays the currently loaded network model (e.g., imported from CNLStudio) and the active hardware constraints.
3. **Main Content Area:**
   - Hosts the specific screen widget based on the active route.

## Target Audience
- **Humans:** Use the Workbench Shell to navigate between different evaluation domains (accuracy vs. power vs. robustness).
- **AI Agents:** Agents should recognize the shell as the root routing widget. To execute an automated evaluation pipeline, agents must programmatically navigate through these routes or trigger the underlying providers for each screen sequentially.

---
*Next:* Read `01_Benchmark_Execution.md` to learn how to run standard model tests.
