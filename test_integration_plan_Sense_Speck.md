# Test Integration Plan: SynSense Speck

## Overview
This document delineates the testing integration plan for the **SynSense Speck** (and DYNAP-CNN line) using the `sinabs` and `rockpool` integration paradigms. This focuses on edge AI implementations, ensuring precise neuromorphic latency and translating low-level abstractions directly to PyTorch `torch.nn.Sequential` modules mapping to Speck constraints.

## Usable Tutorials & Examples to Test

### 1. Fallback Software Execution via NeuroBench
The `NeuroBench` benchmarking engine supports orchestrating targets towards the `SynSenseBenchmarkRunner`. Due to `Sinabs` robust support structure, you can run simulations entirely using CPU-based standard PyTorch if you lack a physical Speck development kit.

**Runner location:** `Neurobench/neurobench/app/runners/synsense_runner.py`

**What it tests**:
- Confirms the translation of basic graphs into standard `sinabs.network.Network` using `sinabs.layers.LIF` blocks.
- Tests metric mappings: verifying that precision matrices, energy/power readouts (`power_mw`), latency properties, and specific neuromorphic telemetry generated line up with the `BenchmarkResult` format specification.

**How to run API endpoints**:
If your NMTK server pipeline is active, you can send testing POST packets to the SynSense-specific API stub:
```bash
POST /bench/synsense/run
{
  "network_path": "<PATH_TO_NIR_OR_CNL>",
  "target": "simulation" # Could be "speck" or "dynapcnn" if natively connected.
}
```

### 2. Structural Testing of Sinabs Translator Node Map
The standalone translation nodes mapping NIR internal structures (`nir.NIRGraph`) into module lists appropriate for `sinabs` PyTorch layers can be conceptually validated.

**How to test I/O Conversion rules**:
Use existing `pytest` integrations aimed at verifying the translation dictionary specified within standard `nirtorch` mappings:
```bash
pytest neurocnl/neurocnl/export/test_exporters.py -k "sinabs"
```
By testing these, you emulate the conversion between NMTK's internal layer matrices (`LIF`, `Linear`, `Affine`) and SynSense hardware targets directly bridging the gap into native PyTorch.

## Official Documentation and External Tutorials

To ensure the NMTK Sinabs/Torch generation works properly and can act as a bridge to DYNAP-CNN/Speck, use these official SynSense pipelines:

- **Sinabs Documentation:** [sinabs.readthedocs.io/](https://sinabs.readthedocs.io/)
- **Official SynSense Website:** [sinabs.ai/](https://sinabs.ai/)
- **GitHub Repository & Hardware Examples:** [github.com/synsense/sinabs](https://github.com/synsense/sinabs). The documentation includes specific hardware tutorials (e.g., Quick start with N-MNIST, deploying models from NIR to Speck) which align perfectly with NMTK's internal NIR representation mapping test cases.
