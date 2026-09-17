# PYNQ Z2 — FINN Compilation Target Integration Plan

## 1. Compilation Strategy Options

### Option A — FINN Dataflow Compiler
- **Approach**: Convert the NeuroCNL SNN graph to a quantized PyTorch model. FINN would then map this to a streamlined dataflow graph and finally to an FPGA bitstream.
- **Pros**: Leverages AMD/Xilinx officially supported tools for high-performance ML workloads.
- **Cons**: FINN is primarily designed for feedforward Convolutional Neural Networks (CNNs). Mapping temporally-dependent, stateful LIF neurons and SNN topologies is a significant challenge, requiring either custom HLS node design or unrolling time into spatial dimensions (which quickly consumes resources).
- **Feasibility**: High effort and technical risk for arbitrary SNNs.

### Option B — Direct Memory-Mapped Overlay
- **Approach**: Generate a configuration file for a pre-built, fixed-architecture SNN overlay on the FPGA. The overlay contains a parameterized crossbar and LIF cores. Software mapping becomes a matter of routing weights and thresholds via Memory-Mapped IO (MMIO).
- **Pros**: Substantially lower barrier to entry. Avoids long Vivado/Vitis synthesis times during compilation. Simplifies the software stack.
- **Cons**: Less flexible. Network topologies are constrained by the fixed dimensions of the synthesized IP cores on the overlay.

### Recommendation
**Phase 1: Direct Memory-Mapped Overlay (Option B)**.
Given the resource constraints of the Zynq-7000 SoC on the PYNQ Z2 (limited LUTs and BRAM) and the impedance mismatch between FINN's CNN focus and SNN requirements, a direct MMIO overlay offers the most realistic and rapid path to a working compilation target.
Phase 2 could explore FINN integration once a stable quantisation pipeline is established.

---

## 2. NeuroCNL Internal Graph → FPGA Mapping

### LIF Neurons
- **Mapping**: Mapped to dedicated fixed-point LIF cores on the FPGA.
- **Constraints**: Voltage and decay dynamics must be represented using bit-shifts or low-precision arithmetic to save LUTs.

### Synaptic Weights and Quantisation
- **Quantisation**: Due to limited BRAM on the Zynq-7000, weights must be heavily quantized, typically to 4-bit or 8-bit integers (`int4` or `int8`).
- **Thresholds**: Neuron thresholds must also be quantized in tandem with the weights to preserve firing rates.

### Network Topology constraints
- Zynq-7000 limitations mean the overlay will likely support fixed block sizes (e.g., crossbars of 256x256 or 1024x1024).
- Only networks that can be mapped into these discrete blocks (with potential routing constraints between blocks) are synthesisable.
- Sparse connections will still consume dense memory space unless specialized sparse overlay architectures are used.

---

## 3. `pynq_exporter.py` Design

- **Interface**: Implements the standard exporter pattern `export_pynq(net: nengo.Network, **kwargs) -> str | dict`.
- **Functionality**:
  1. Traverses the Nengo network, extracting `Ensemble` and `Connection` properties.
  2. Invokes the quantisation pass to scale float weights to integer ranges.
  3. Maps the quantized network onto the logical constraints of the PYNQ Z2 overlay.
- **Output**: Generates a JSON configuration file or a Python dictionary representing the overlay map (weights, routing, thresholds), which will integrate with the PYNQ overlay loader (CHIP-004).

---

## 4. Quantisation Pass in NeuroCNL

- **Module**: Introduce a new module `neurocnl/transforms/quantise.py`.
- **Functionality**: Before export, this pass scales synaptic weight matrices into an N-bit integer range (e.g., `[-128, 127]` for `int8`). It must apply a corresponding scaling factor to the LIF threshold to maintain relative dynamics.
- **Reuse**: The existing `lava_exporter.py` performs a rudimentary scaling (`int(weight * 128)`). This logic will be extracted, formalized, and expanded into `quantise.py` so both Lava, Akida, and PYNQ can utilize a unified quantization transform.

---

## 5. Software Validation Path (Before Synthesis)

- **Equivalence Testing**: Before attempting hardware deployment, the quantized network must be validated in software.
- **Methodology**:
  1. A Nengo model is instantiated with the *quantized* integer weights and thresholds.
  2. The software simulator runs the quantized model alongside the original floating-point model using identical input stimuli.
  3. Spike raster plots or integrated spike counts are compared. A regression test will enforce that the functional output remains within a defined tolerance bounds (e.g., correlation coefficient > 0.9).

---

## 6. Dependencies

- `finn-base` or `finn` (if exploring Phase 2) will be added under optional extras `[pynq]`.
- Target board deployment will require `pynq>=2.7`.
