# 03: Robustness Analysis

Neuromorphic hardware is often deployed in noisy, edge environments. The `robustness_screen` evaluates how well a network handles degraded inputs or hardware faults.

## Perturbation and Resilience

### Applying Perturbations
Users can configure the test harness to inject noise into the benchmark dataset:
- **Jitter:** Temporal shifts in spike arrivals.
- **Dropouts:** Randomly dropping incoming spikes.
- **Noise:** Adding Gaussian noise to analog input sensors before spike encoding.

### The Curves
Once robustness tests are run, the results are visualized in specific charts:
1. **Perturbation Curve Chart (`perturbation_curve_chart`):**
   - Plots the intensity of the noise (x-axis) against the network's accuracy (y-axis). 
2. **Robustness Curve Chart (`robustness_curve_chart`):**
   - Compares the resilience of your network against the established Baseline. A good neuromorphic network should degrade *gracefully* compared to standard ANNs.

## Execution Flow for Agents
- **Agent Note:** When requested to "stress test" a model, agents must programmatically configure a robustness benchmark job with an array of perturbation magnitudes (e.g., `[0.0, 0.1, 0.2, 0.5]`), run the sequence, and evaluate the slope of the resulting `RobustnessCurve` object.

---
*Next:* Read `04_Report_Generation.md` to learn how to export benchmark results.
