# 02: Comparison and Regression

When iterating on network architectures in CNLStudio, it is crucial to ensure that optimizations (like aggressive quantization or sparsity) do not fatally degrade performance.

## Comparison Screen

The `comparison_screen` allows direct A/B testing of two networks or two hardware targets.

### Metric Diff Table
- **Visual:** A detailed data table (`metric_diff_table`).
- **Content:** Compares Network A vs. Network B row-by-row across all tracked metrics (Accuracy, Energy, Memory Footprint).
- **Highlighting:** Positive changes are typically highlighted in green, while regressions (e.g., accuracy dropping by >2%) are highlighted in red or flagged.

### Target Comparison Grid
- **Visual:** A matrix layout (`target_comparison_grid`).
- **Usage:** Compares how *one* network performs across *multiple* hardware backends (e.g., Simulation vs. Teensy vs. PYNQ-Z2).

## Regression Trends Screen

The `regression_trends_screen` tracks a model's historical performance over multiple commits or design iterations.

### Run History Timeline & Trend Chart
- **Visual:** A timeline list (`run_history_timeline`) and a line graph (`trend_chart`).
- **Usage:** Observe long-term trends. Did adding the STDP learning rule slowly improve energy efficiency over the last 5 runs? Has accuracy steadily dropped since we moved to 4-bit weights?
- **Agent Note:** Agents tasked with "optimizing" a network should query the regression trend data to formulate reward functions or stop conditions when performance degrades past a threshold.

---
*Next:* Read `03_Robustness_Analysis.md` to learn how to test network resilience.
