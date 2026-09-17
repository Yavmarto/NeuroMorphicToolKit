# NeuroCNL Module Functional Testing Guide

**Module Name:** `neurocnl`
**Purpose:** Translates plain-English specifications into verified Spiking Neural Networks (SNNs).
**Key Inputs:** Controlled Natural Language (CNL) plain-text specifications, User-defined parameters, Hardware target strings (e.g., "nengo", "loihi").
**Expected Outputs:** Compiled network topology, NIR preview or export artifacts, and validation results.

---

## 1. Core Functional Walkthrough (The "Happy Path")

This section describes how to execute the primary supported use case of the `neurocnl` module: compiling a valid CNL spec into topology and NIR preview artifacts.

**Pre-requisites:** The NMTK launcher is open, backends are running, and the `neurocnl` UI is active.

1. **Input the Specification:** In the provided text editor area, enter a valid biological SNN description. For example:
   ```text
   The sensory neuron MUST fire IF membrane potential exceeds 0.8
   The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.2
   ```
2. **Configure Pipeline Parameters:**
   - Set the **Hardware Target** to `nir` or leave it at the default supported target.
   - Keep any preview or export parameters at their defaults unless you are specifically testing a handoff path.
3. **Execute:** Click "Compile Preview" in Studio. This runs the supported `/api/generate` flow and renders compiled topology plus the generated NIR preview.
4. **Expected Visual/Data Outcomes:**
   - **Validation Report:** The UI should display a "Pass" status for Layer 1 (Physical) and Layer 2 (Structural) validation.
   - **Compiled Preview:** The preview panel should populate with node and edge counts, a topology listing, and a NIR text preview.
   - **Export Readiness:** Exporting with `format="nir"` should produce a downloadable NIR artifact for the same spec.

---

## 2. Data & State Validation

How to verify the internal processing (parsing, validation, generation) was structurally and mathematically correct:

1. **Parser Verification (`neurocnl/cnl/cnl_parser.py`):**
   - **Test:** Submit a sentence.
   - **Validation:** Inspect the backend logs or intermediate API payload. The raw text must be mapped to a `ParsedSentence` dictionary. For the sentence *"The sensory neuron MUST fire IF membrane potential exceeds 0.8"*, verify the dictionary contains:
     - `concept`: `"threshold_firing"`
     - `subject`: `"sensory neuron"`
     - `condition`: `"0.8"` (or `"exceeds 0.8"`)
     - `verb`: `"MUST"`
     - `negated`: `False`

2. **Network Generation Verification (`neurocnl/generation/nengo_generator.py`):**
   - **Test:** Provide a spec with specific population counts, e.g., *"The network MUST contain an excitatory relay population of 50 neurons"*.
   - **Validation:** Check the generated object graph (or exported NIR equivalent). Verify that the corresponding `nengo.Ensemble` (or `nir.LIF` node) was instantiated with `n_neurons=50`.

3. **Generated Preview Verification (`/api/generate`):**
   - **Test:** Run a compile preview.
   - **Validation:** Inspect the JSON payload returned by `/api/generate`. Verify the `network` payload contains the expected node and edge structure, and that `nir_code` is present and non-empty.

---

## 3. Module-Specific Edge Cases & Boundary Testing

These edge cases test the boundaries of the `neurocnl` validation engines (`Layer 1` and `Layer 2`).

1. **Edge Case 1: Contradictory Biological Invariants (Layer 1)**
   - **Test Action:** Input a spec with impossible physics parameters, such as *"The sensory neuron membrane potential MUST decay WITH time constant of -0.05 seconds"*.
   - **Expected Result:** The Pydantic validators (`LIFNeuronContract` / Layer 1) MUST intercept and strictly reject the compilation. The pipeline must return `overall_pass: False` with a specific error regarding a negative time constant, preventing network generation.

2. **Edge Case 2: Structural Topology Violations (Layer 2)**
   - **Test Action:** Input a spec that defines a connection without specifying the required target, or specifies a 0.0 synaptic weight.
   - **Expected Result:** The `layer2_validator.py` logic must intercept the graph generation, returning a `checks_failed` list containing the topology violation.

3. **Edge Case 3: Syntax Fallback / Unrecognized Concepts**
   - **Test Action:** Input gibberish or non-controlled English: *"Make a neuron that goes zap fast."*
   - **Expected Result:** The `cnl_parser.py` must raise a `ParseError`. The pipeline should catch this and return a graceful error message: *"No valid CNL sentences found."* instead of crashing the backend.

4. **Edge Case 4: STDP Learning Rule Parsing**
   - **Test Action:** Input a complex STDP rule: *"The connection from sensory neuron to motor neuron MUST maintain weight BETWEEN 0.1 AND 1.5"*.
   - **Expected Result:** Verify the parser correctly extracts `weight_min` as `0.1` and `weight_max` as `1.5` under the `stdp_learning` concept, and does not misclassify it as a simple `synaptic_weight` concept.

---

## 4. Inter-Module Handoff Preparation

Verify the `neurocnl` output is correctly formatted for downstream modules (e.g., Export to Neuromorphic Hardware or external Frameworks).

1. **Exporter Output Verification (`neurocnl/export/`):**
   - **Test Action:** Trigger an export to a target framework (e.g., PyNN or Lava).
   - **Validation:** The module should output a valid Python string or file payload. Verify that the file begins with the correct framework imports (e.g., `import pyNN.nest as pynn` or `from lava.proc.lif.process import LIF`) and does not contain syntax errors.

2. **Deprecated Simulation Contract:**
   - **Test Action:** Submit a request to `/api/simulate`.
   - **Validation:** The endpoint must return `410 Gone` with the machine-readable `nir_simulation_unsupported` error and guidance to use `/api/generate` or `/api/export`.

3. **Contract Adherence:**
   - **Test Action:** Evaluate the final JSON output of any successful run.
   - **Validation:** The payload must strictly adhere to the `PipelineResultContract` Pydantic schema (defined in `neurocnl/contracts/pipeline_contracts.py`), ensuring that `overall_pass`, `validation`, and `benchmarks` fields are consistently present and formatted correctly for UI consumption.
