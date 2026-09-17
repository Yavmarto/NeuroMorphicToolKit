# SynSense Integration Plan for Neurobench

## Overview
This document outlines the plan for integrating SynSense hardware (DYNAP-CNN and Speck) into the Neurobench benchmarking workbench. The integration leverages `sinabs` and `rockpool` libraries for deploying Spiking Neural Networks (SNNs) to the hardware. SynSense hardware targets ultra-low-power edge inference, making energy efficiency a core benchmarking metric.

## 1. `SynSenseBenchmarkRunner` Interface
The integration will introduce a new runner class, `SynSenseBenchmarkRunner`, located in `neurobench/app/runners/synsense_runner.py`.
This runner will act as a wrapper around the `sinabs` and `rockpool` execution paths, orchestrating the deployment of networks to the hardware (or falling back to CPU simulation) and collecting the resulting metrics.

It will implement methods to:
- Detect the presence of SynSense hardware (Speck devkit, DYNAP-CNN devkit) or fallback to CPU.
- Initialize the target platform and load the network configuration (CNL or standard dataset path depending on the pipeline).
- Run inference across the specified benchmark dataset.
- Aggregate hardware statistics and simulation outputs to conform with the NeuroBench `BenchmarkResult` format.

## 2. Hardware Deployment Paths

### Sinabs (DYNAP-CNN & Speck)
The `sinabs` framework (`sinabs.backend.dynapcnn`) provides the `DynapcnnNetwork` interface to configure and deploy a network to a DYNAP-CNN chip or Speck module. The runner will:
- Load the base model using the standard `sinabs` API.
- Convert or compile the model for the hardware target using `DynapcnnNetwork`.
- Route inputs to the physical device and capture the output spike trains or readouts.

### Rockpool (Xylo / Speck)
The `rockpool` framework (`rockpool.devices.xylo`) provides interfaces like `XyloSamna` for mapping computation to SynSense chips.
- The `SynSenseBenchmarkRunner` will map the benchmark workload onto a `XyloSamna` instance.
- Synchronous or asynchronous execution will be triggered to evaluate the inputs.

## 3. CPU Simulation Fallback
To support CI environments and instances without physical hardware attached, both `sinabs` and `rockpool` natively support running the SNNs via standard PyTorch-based or numpy-based software simulation.
- The `SynSenseBenchmarkRunner` will provide a `target="simulation"` parameter (the default).
- When hardware is unavailable or `"simulation"` is requested, the runner will utilize the standard `sinabs.Network` or the `rockpool` computational graph without instantiating the hardware backend.

## 4. Benchmark Execution on SynSense Hardware
Neurobench's standard benchmark suite (e.g., spike classification, grip stability) will be runnable on SynSense hardware by:
- Loading the corresponding benchmark JSON definition via `BenchmarkLoader`.
- Providing the `cnl` spec or data path to the `SynSenseBenchmarkRunner`.
- Using an assertion engine adapted for SynSense outputs (matching expected timing and spike readouts).

## 5. Metric Schema Mapping
The hardware execution statistics provided by the toolchains will be translated into NeuroBench's `BenchmarkResult.metrics` format:
- **Power Draw (`power_mw`)**: Mapped from the estimated or measured dynamic power of the chip (converted to mW; Note: issue references uW, so it will be divided by 1000).
- **Inference Latency (`latency_ms`)**: Derived from the hardware execution time for single-batch passes.
- **Accuracy (`accuracy`)**: Calculated by evaluating the predicted output against the benchmark's ground truth.
- **Spike Sparsity (`spike_fidelity` / custom metric)**: Tracked by counting spikes per inference pass.

## 6. API Endpoints
To orchestrate SynSense specific benchmarks, a new router will be created in `neurobench/app/routers/synsense.py` with the following endpoints:
- `POST /bench/synsense/run`: Queues a benchmark run targeting a SynSense device. Payload includes network path, benchmark ID, and target (`speck`, `dynapcnn`, `simulation`). Returns a `run_id`.
- `GET /bench/synsense/results/{run_id}`: Polls the status and fetches the completed benchmark results in standard format.

## 7. Dependencies
The SynSense functionality will be optionally provided to minimize core dependencies.
The following will be added to `pyproject.toml` under a new `[synsense]` optional extra:
- `sinabs >= 2.0.0`
- `rockpool >= 2.8.0`
