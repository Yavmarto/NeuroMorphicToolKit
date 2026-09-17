# Running Your First SNN Benchmark

This guide will walk you through the process of running a standard Spiking Neural Network (SNN) benchmark using the NeuroBench platform.

## Prerequisites

- NeuroBench backend is running (typically at `http://localhost:8000`).
- NeuroBench Flutter frontend is open in your browser.
- You have an SNN model defined in a `.cnl` file.

## Step 1: Select a Benchmark

On the main NeuroBench screen, you will see a list of available benchmarks in the left sidebar. Common benchmarks include:

- **Grip Stability**: Evaluates prosthetic reflex stability using synthetic or recorded slip data.
- **Spike Classification**: Measures accuracy in classifying neural spike patterns.
- **Reaction Latency**: Benchmarks the time between an input stimulus and the network's response.

Click on a benchmark from the list to view its description and current configuration.

## Step 2: Configure Parameters (Optional)

Some benchmarks allow you to override default parameters such as:
- **Trials**: Number of times the simulation should be repeated.
- **Simulation Duration**: How long each trial runs (in milliseconds).
- **Noise Level**: The amount of synthetic noise to inject into the input signal.

## Step 3: Run the Benchmark

Once you have selected a benchmark:
1. Ensure your network specification (.cnl) is loaded.
2. Click the **Run Benchmark** button in the main panel.
3. A progress indicator will appear while the backend executes the simulation and evaluates the results against the benchmark's assertions.

## Step 4: Interpret Results

When the benchmark completes, the **Results Summary** card will update with the latest metrics:

- **Primary Metric**: The main performance indicator (e.g., Accuracy or Stopping Distance).
- **Secondary Metrics**: Additional data like Latency or Power Consumption.
- **Run History**: You can see a timeline of previous runs to track your progress.

### Understanding the Comparison

If you have saved a **Baseline**, NeuroBench will automatically show a diff:
- **Green**: Performance has improved compared to the baseline.
- **Red**: Performance has regressed.
- **Gray**: No significant change.

## Next Steps

- **Compare Hardware**: Use the "Compare Targets" feature to see how your network performs on different neuromorphic chips.
- **Robustness Sweep**: Test how your network handles neuron failures or input perturbations.
- **Generate Report**: Export your results as a PDF for sharing with your team.
