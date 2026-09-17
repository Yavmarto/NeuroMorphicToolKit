# BrainChip Akida SDK Integration Plan

This document outlines the strategy for fully integrating BrainChip's Akida Python SDK into the Neurochip module. It replaces the current code-generation stub with functional API calls capable of defining, mapping, and executing spiking neural networks on Akida hardware (or a software emulator).

## 1. Replacing the Code-Generation Stub (`neurochip/app/services/akida_backend.py`)

The existing `neurochip/app/services/akida_generator.py` module generates static ZIP files and does not directly interact with the Akida hardware or framework. We will replace this stub by introducing a new module, `neurochip/app/services/akida_backend.py`. This new backend will interact directly with the Akida Python SDK.

The new backend will provide:
- Model translation logic (from `NetworkInput` JSON definitions to `akida.Model` objects).
- Deployment package generation to maintain backward compatibility for users wanting a `.fbz` model file.
- Direct inference functions (`map_and_run`).

## 2. Full Akida Deployment Pipeline

The Akida deployment pipeline inside Neurochip will follow these phases:

### A. Model Creation (`akida.Model`)
- We will construct an `akida.Model` programmatically using the Sequential API based on the `NetworkInput` payload.
- We will use native Akida layers such as `akida.InputData`, `akida.Convolutional` (or `Conv2D`), and `akida.FullyConnected` (or `Dense1D`).

### B. Quantization
- While standard deployment via Keras utilizes `quantizeml` to prepare the model, natively defined SNN structures with discrete weights provided in the `NetworkInput` can be initialized directly with appropriate weight bit-widths during layer instantiation (e.g. `weights_bits=1, 2, 4`).

### C. Mapping (`model.map()`)
- After compilation and initialization, the SNN model must be mapped onto a specific device (a target NP mesh).
- The call `model.map(device)` takes an `akida.Device` object and partitions the sequences of the model across Neural Processors (NPs).

### D. Execution (`model.run()`)
- With the model mapped, inference is performed using `outputs = model.run(inputs)` (or equivalent execution endpoint).

## 3. Handling CNN-to-SNN Pathway vs. Native SNN Inputs

### Native SNN Inputs (NeuroCNL)
When handling `NetworkInput` directly, `akida_backend.py` parses standard JSON descriptors of neurons (like LIF) and synapses. It maps these manually into corresponding Akida SNN layers.

### CNN-to-SNN Pathway
Users looking to deploy pre-trained Convolutional Neural Networks (developed in Keras) into Spiking models can utilize the `cnn2snn` toolkit provided by BrainChip.
- In future enhancements, an endpoint can accept Keras (`.h5`) weights.
- `cnn2snn.convert(model)` will transform the continuous-value Keras model into a spike-compatible format before mapping to the hardware.

## 4. Hardware Detection (`akida.devices()`) and Simulation Fallback

To support both edge hardware (e.g., PCIe/SoC devices) and local development environments without an accelerator, the backend will attempt hardware discovery and fall back to simulation gracefully.

```python
from akida import devices

available_devices = devices()

if available_devices:
    target_device = available_devices[0]  # Maps to the first physical Akida device
else:
    # Emulation fallback if hardware is missing
    from akida import AKD1000

    target_device = AKD1000()
```

## 5. Result Retrieval and Spike Output Deserialization

When `model.run(inputs)` (or similar mapping interface) returns, the raw outputs are provided as NumPy arrays containing discrete event representations (potentials or spike counts).

- The shape of the outputs will correspond to the output layer parameters (e.g., `(batch_size, classes)`).
- The Neurochip backend will serialize these numerical arrays back into standard JSON formats.
- Post-execution metadata (e.g., inference FPS, power consumption) can be extracted directly from `model.statistics` and attached to the API response.

## 6. API Endpoints Exposing Akida Execution

To interact with the new service, `neurochip/app/routers/akida.py` will be created with dedicated endpoints:

- `POST /api/neurochip/akida/deploy`
  - Replaces `/api/neurochip/export/akida`.
  - Takes `NetworkInput`, generates the SNN Sdk model, and returns a ZIP file containing the `DeploymentManifest` and the mapped `.fbz` model file.

- `POST /api/neurochip/akida/inference`
  - Accepts a network payload along with raw sample `inputs`.
  - Maps to the target (Hardware or Emulator).
  - Performs the spike computation and responds with predicted classes/potentials and telemetry (FPS/Power).

## 7. Dependency Setup
The integration depends on `akida>=2.0.0` which has been declared under the `[akida]` optional extra in the project `pyproject.toml`.
