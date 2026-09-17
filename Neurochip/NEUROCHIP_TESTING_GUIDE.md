# Neurochip Module Testing Guide

This is a highly specific, step-by-step functional testing guide tailored exclusively for the `neurochip` module's internal logic, constraints, and neuromorphic domain features.

## Read This Before Choosing a Test

Different Neurochip tests validate different targets and different layers of
truth:

- `tests/integration/test_teensy_e2e.py` validates the **Teensy** cross-module
  pipeline. It does not validate PYNQ deployment.
- `neurochip/tests/test_pynq_backend.py` and
  `neurochip/tests/test_pynq_sitl_verify.py` validate the **PYNQ** backend
  lifecycle and verification behavior, usually through the simulator fallback.
- Real PYNQ deployment is only established when the board-hosted Neurochip
  service reports `/hardware/pynq/preflight` as `ok` and the deploy or run
  calls succeed against that board.

If you are deploying to a networked PYNQ Z2, use
`docs/neurochip/pynq_z2_deployment_guide.md` first. Do not use the Teensy E2E
test as your primary acceptance check.

## Module Information

*   **Name:** `neurochip`
*   **Purpose:** A Hardware Deployment & Compilation Toolkit for Spiking Neural Networks (SNNs) that handles target-specific hardware profiling, model quantization, constraint analysis, and deployment manifest generation.
*   **Key Inputs:** SNN models in Neuromorphic Intermediate Representation (NIR) format, Hardware Target selections (e.g., Intel Loihi 2, SpiNNaker, BrainScaleS, BrainChip Akida, Teensy 4.1), Quantization configurations (e.g., target bit-width), and Fault Sweep parameters.
*   **Expected Outputs:** Compiled SNN artifacts, `QuantizationResult`, `ConstraintReport`, `PowerEstimate`, `LatencyEstimate`, and comprehensive `BenchmarkResult` (including PowerMetrics, SpikeTrace, and CoreUtilization).

---

## Core Functional Walkthrough (The "Happy Path")

1.  **Model Import & Target Selection:**
    *   In the Neurochip UI, click "Import Model" and select a valid NIR-formatted SNN model from the `nmtk_workspace/models/` directory.
    *   Select a target hardware device from the dropdown (e.g., "Intel Loihi 2").
2.  **Quantization Configuration:**
    *   Navigate to the Quantization settings. Set a valid target bit-width supported by the device (e.g., 8-bit).
    *   Click "Run Quantization".
    *   *Expected Output:* The UI updates with a `QuantizationResult` widget displaying the achieved bit-width and confirming that the accuracy loss remains `<= 25.0%`.
3.  **Hardware Profiling & Constraint Analysis:**
    *   Click "Run Hardware Profiler".
    *   *Expected Output:* The dashboard populates a `BenchmarkResult` featuring:
        *   **PowerMetrics:** Total energy (pJ) and Power envelope (mW).
        *   **CoreUtilization:** Number of cores utilized (within the 1-128 range).
        *   **SpikeTrace:** Visual graphs of spike train activity.
        *   A `ConstraintReport` confirming the model successfully fits the hardware target's memory and neuron limitations.
4.  **Deployment Manifest Generation:**
    *   Click "Generate Deployment Manifest".
    *   *Expected Output:* A structured JSON manifest is created containing the compiled configuration, mapped network inputs, and the verified target firmware version.

---

## Data & State Validation

To mathematically and structurally verify the internal processing of the neuromorphic compilation backend:

*   **Memory Fit Invariant Calculation:** Check the generated `HardwareProfile` and `ConstraintReport`. Validate the backend's internal math: ensure that `neuron_capacity * 6 <= on_chip_memory_kb * 1024`. If this mathematical condition is not met, the structural state is invalid.
*   **Latency Monotonicity:** Inspect the generated `LatencyEstimate` JSON artifact. Verify structurally that the estimates follow strict monotonic ordering: `best_case_us <= typical_us <= worst_case_us`.
*   **Non-Negative Physical Constraints:** Within the `PowerEstimate` and `HardwareProfile` artifacts, ensure that variables simulating physical world limits (`power_envelope_mw`, `pj_per_spike_op`, and `total_energy_pj`) are strictly `>= 0`.
*   **Accuracy Bounds Checking:** Verify the `QuantizationResult` JSON. The `accuracy_loss` field must explicitly be a float value `<= 25.0`, proving the quantization algorithm did not degrade the SNN beyond acceptable thresholds.

---

## Module-Specific Edge Cases & Boundary Testing

1.  **Memory Fit Violation (Oversized SNN):**
    *   *Test:* Import an exceptionally large SNN with a neuron count that violates the hardware target's capacity equation (`neuron_capacity * 6 > on_chip_memory_kb * 1024`).
    *   *Validation:* The validation logic must trap this and return a specific `ConstraintReport` failure preventing deployment manifest generation.
2.  **Excessive Fault Injection Rate:**
    *   *Test:* In the fault tolerance testing interface, attempt to configure a fault injection rate greater than `0.3` (30%).
    *   *Validation:* The `FaultSweepResult` contract validation should immediately reject the input, as the maximum allowed fault injection rate across all test scenarios is fixed at `0.3`.
3.  **Invalid Hardware Target Firmware Version:**
    *   *Test:* Attempt to create a deployment manifest for "Intel Loihi 2" but manually inject or specify a legacy firmware version of `1.9.9`.
    *   *Validation:* The backend validator must block this. It enforces strict invariants where Loihi 2 requires firmware `>= 2.0.0` (similarly: SpiNNaker >= 2.0.0, BrainScaleS >= 2.0.0, Teensy 4.1 >= 1.0.0).
4.  **Hardware Core Count Boundary Exceedance:**
    *   *Test:* Configure a deployment profile requesting `129` cores or `0` cores for a multi-core target.
    *   *Validation:* The core constraint logic must catch this, returning a schema validation error before the Hardware Profiler HAL is even invoked, as cores are restricted to the `1-128` integer range.

---

## Inter-Module Handoff Preparation

To verify that the output generated by `neurochip` is correctly formatted and ready to be passed to the next logical step (e.g., simulation in Neurosim or physical flashing):

*   **Standardized NIR Export:** Verify that the exported SNN model strictly adheres to the Neuromorphic Intermediate Representation (NIR) standard. Open the output file to confirm it is a valid `.nir` or `.json` graph structure.
*   **Security & Path Verification:** Verify that the output artifacts are safely saved in the `nmtk_workspace/models/` directory. Check the backend logs to ensure filename sanitization (using `os.path.basename`) successfully stripped any relative path characters (e.g., `../`), preventing path traversal vulnerabilities during handoff.
*   **Manifest Completeness:** Validate the generated `DeploymentManifest` JSON against the schema expected by the firmware flashing module. It must contain the non-null `core_count`, specific `target_device` enum, and the validated `firmware_version` to successfully initiate a `FlashJob` or open a `SerialPort` connection.
