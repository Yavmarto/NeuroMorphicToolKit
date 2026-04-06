# Test Integration Plan: PYNQ Z2

## Overview
This document outlines the test integration plan for the **PYNQ Z2** board. The strategy for NMTK is centered around compiling trained SNN weights and thresholds to a fixed-point precision level, taking the output configuration to deploy onto the FPGA's hardware fabric using direct Memory-Mapped IO (Option B overlay).

## Usable Tutorials & Examples to Test

### 1. Local SNN Quantisation Export Pipeline
A core deployment bottleneck is handling weight quantisation before loading bitstreams to FPGA blocks. The `Neuro-Dream-Hand` package includes an executable script to test scaling floating-point matrices to limited precision bit logic for the PYNQ overlay.

**Script Path**: `Neuro-Dream-Hand/scripts/step15_pynq_deployment.py`

**What it tests**:
- Translates existing weight `.npz` files through the quantization logic (integer representations up to 8-bits).
- Packages weights and metadata into a valid `pynq_config.json` that connects to the `.bit` overlay loaders via the `PYNQExporter`.

**How to run**:
```bash
python Neuro-Dream-Hand/scripts/step15_pynq_deployment.py --weights output/sleep_weights.npz --bits 8 --target-format finn
```

### 2. ZeroMQ Remote Co-Simulation (SITL)
If you have a PYNQ board running the NMTK server on its ARM Cortex-A9 cores, you can execute a Software-in-the-Loop test. This streams MuJoCo physics observations to the PYNQ board and reads back motor reflexes.

**Script Path**: `Neuro-Dream-Hand/scripts/step16_sitl_pynq.py`

**What it tests**:
- Confirms end-to-end network latency and the operational status of the embedded SNN controller on the PYNQ target without needing a physical robotic hand setup.
- Evaluates the PYNQ server's API and memory-mapped hardware exchange cycle natively.

**How to run**:
1. On the PYNQ board, start up the overlay interface backend: `python scripts/pynq_zmq_service.py`
2. On your host computer, pipe the physics environment to the board replacing the host IP:
```bash
python Neuro-Dream-Hand/scripts/step16_sitl_pynq.py --host <PYNQ_IP_ADDRESS> --port 5555 --render
```

## Official Documentation and External Tutorials

If you wish to test alternative synthesis strategies (like custom FINN architectures) alongside NMTK's PYNQ overlay setup, consult:

- **FINN Official Documentation:** [finn.readthedocs.io](https://finn.readthedocs.io/)
- **Xilinx FINN Repository:** [github.com/Xilinx/finn](https://github.com/Xilinx/finn) (Look inside the `notebooks/` folder for end-to-end examples of QNN/SNN mapping to PyTorch via Brevitas, then down to PYNQ bitstreams)
- **FINN Examples for PYNQ:** [github.com/Xilinx/finn-examples](https://github.com/Xilinx/finn-examples) provides verified, pre-built bitfiles and Jupyter notebook deployment sequences for the PYNQ-Z2 to serve as a baseline comparison.
