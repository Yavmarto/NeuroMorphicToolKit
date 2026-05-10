# Integration of Nengo-FPGA and Cognitive Architectures (SPA)

This document serves as the implementation plan for two major architectural expansions in the Neuromorphic Toolkit:
1. Integrating `nengo-fpga` into the Pynq Z2 end-to-end (e2e) pipeline.
2. Expanding the Computational Network Language (CNL) to support cognitive architectures and state machines via Nengo SPA.

## 1. Nengo-FPGA Pynq Pipeline

We have decided to relax the "standalone edge deployment" constraint in favor of using `nengo-fpga`, which will significantly speed up development velocity and stability. This means the Pynq board will be tethered to a host PC during execution to orchestrate the simulation.

### Implementation Steps

1. **New Exporter module**: Create `Neuro-Dream-Hand/neurodreamhand/hardware/nengo_fpga_exporter.py`.
   - This script will wrap target Nengo Ensembles in `nengo_fpga.FpgaPesEnsembleNetwork`.
   - It will manage the connection to the board over the network.
2. **Modify Deployment script**: Update `Neuro-Dream-Hand/scripts/step15_pynq_deployment.py`.
   - Add an argument flag `--use-nengo-fpga` to switch the deployment backend.
   - When enabled, instead of exporting quantized JSON (for FINN), it will invoke the `nengo_fpga_exporter.py` to prepare and run the network for tethered execution on the board.

---

## 2. Cognitive Architectures (NeuroCNL SPA)

To support state machines and cognitive architectures, we will map new CNL grammar constructs to Vector Symbolic Architectures (VSAs) using the standalone `nengo_spa` package. 

### Natural Language Grammar for CNL
To maintain the "natural" requirements-driven structure of CNL (e.g., *The sensory neuron MUST fire...*), we will introduce new semantic rules that read like behavioral specifications.

**Examples of the new proposed SPA syntax:**
*   `The Vision memory MUST store 64 dimensional concepts` (Creates a `nengo_spa.State` or `nengo_spa.Buffer` with D=64)
*   `The Motor memory MUST store 64 dimensional concepts`
*   `The connection from Vision memory to Motor memory MUST transmit concepts` (Creates a simple `nengo_spa.Cortical` routing)
*   `The Basal Ganglia MUST route concepts from Vision memory to Motor memory ONLY IF the State memory contains the "REACH" concept` (Creates a `nengo_spa.Action` with condition gating)

### Implementation Steps

1. **Schema Expansion**: Modify `neurocnl/backend/app/schemas/` to parse these new natural language sentences and map them to structural nodes (`spa_buffer`, `spa_routing`, `spa_conditional_action`).
2. **Nengo Translation**: Modify `neurocnl/backend/app/services/nengo_code_exporter.py`.
   - Add support for `import nengo_spa as spa`.
   - Translate the new schema nodes to `nengo_spa` constructs (e.g., `nengo_spa.State`, `nengo_spa.Actions`).
3. **Unit Testing**: Create `neurocnl/tests/test_spa_compiler.py` to verify that the natural language specifications translate to executable Nengo SPA Python scripts without errors.

---

## Verification Plan

### Automated Tests
1. **CNL to SPA Compilation:** Run pytest on `test_spa_compiler.py` to ensure the generated Python script is syntactically valid and executes without Nengo errors.
2. **Grammar Integrity:** Ensure existing CNL tests pass without regression after expanding the grammar schema.

### Manual Verification
1. **Nengo-FPGA Hardware Test:** Deploy a simple test network onto the physical Pynq Z2 board using the new `nengo-fpga` tethered script, verify that the bitstream loads, and confirm the host PC can successfully communicate with the board.
2. **SPA Simulation:** Compile a simple CNL cognitive state machine, run the resulting Nengo SPA model locally (without FPGA), and verify the semantic pointers correctly transition states using the Nengo GUI.
