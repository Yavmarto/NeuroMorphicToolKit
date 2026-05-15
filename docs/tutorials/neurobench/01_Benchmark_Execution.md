# 01: Benchmark Execution

The primary function of Neurobench is to evaluate models against standard datasets using standardized metrics.

## Benchmark Screen

The `benchmark_screen` is where execution begins.

### 1. Benchmark Catalog
- **Visual:** A grid or list of available tests (e.g., N-MNIST classification, Keyword Spotting, Optical Flow).
- **Usage:** Select the specific dataset and task your network was designed for. The catalog enforces the correct input/output shapes.

### 2. Baseline Selector
- **Visual:** A dropdown or list widget (`baseline_selector`).
- **Usage:** Choose a reference model (like a standard CNN or an unquantized float32 version of your network) to compare against. This establishes a baseline for accuracy and energy metrics.

### 3. Execution and Summary
- Once a benchmark is started, the system executes the model over the dataset.
- **Results Summary Card (`results_summary_card`):** Upon completion, this widget displays the top-line metrics:
  - Accuracy / Error Rate
  - Estimated Energy per inference
  - Latency / Throughput
  - MACs (Multiply-Accumulates) or Synaptic Operations (SynOps)

## Execution Flow for Agents
- **Agent Note:** Agents do not need to click UI elements. Instead, they should invoke the underlying benchmark provider, supplying the `model_id`, `dataset_id`, and `baseline_id`. Agents must wait for the asynchronous execution to yield a `ResultsSummary` object, which populates the summary card.

---
*Next:* Read `02_Comparison_and_Regression.md` to learn how to track model changes over time.
