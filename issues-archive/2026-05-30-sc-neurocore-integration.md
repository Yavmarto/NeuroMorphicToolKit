# Add `sc-neurocore` Backend Support

This plan outlines the steps required to integrate `sc-neurocore` as a native backend for NeuroMorphicToolKit (NMTK).

By completing this integration, NMTK will gain:
1. An ultra-fast Rust-based simulation backend for inference.
2. A direct deployment path to FPGA hardware via `sc-neurocore`'s equation-to-Verilog compiler.

## Design Decisions

> [!TIP]
> **FPGA vs Simulation target distinction:** `sc-neurocore` provides both a simulation backend and a hardware (FPGA RTL) generation backend. As approved, we will surface both as distinct targets in CNL Studio so the user can clearly choose between "Run in Rust Simulation" vs "Export to FPGA".

> [!NOTE]
> **Installation Dependency:** As requested, `sc-neurocore` (and `snntorch`) will be added to the default `dependencies` array in `neurocnl/pyproject.toml`. This ensures it is installed by default for all users, eliminating the need for optional runtime checks or graceful failure messages.

## Proposed Changes

---

### neurocli

We will introduce a new scaffold template to allow users to generate a ready-to-run `sc-neurocore` project from the CLI.

#### [NEW] neurocli/neurocli/templates/nir_sc_neurocore/README.md.jinja
Template documentation for the new scaffolding.

#### [NEW] neurocli/neurocli/templates/nir_sc_neurocore/pyproject.toml.jinja
The python package definition, including `nir` and `sc-neurocore` as dependencies.

#### [NEW] neurocli/neurocli/templates/nir_sc_neurocore/src/main.py.jinja
The entry point script that loads the exported `model.nir` file and runs it through `sc-neurocore`'s NIR adapter.

---

### neurocnl (Backend / Runtime)

We will build an adapter to support running `sc-neurocore` simulations directly from the CNL backend (e.g. for Studio execution).

#### [MODIFY] neurocnl/pyproject.toml
Move `sc-neurocore` (and `snntorch`) into the main `dependencies` array to ensure it is installed by default across all deployments.

#### [NEW] neurocnl/neurocnl/runtime/sc_neurocore_simulator.py
A new simulator adapter implementing the CNL → NIR → Simulator contract. It will accept a compiled `nir.NIRGraph`, translate it (or pass it directly if natively supported) to `sc-neurocore`, run the timestep loop, and normalise spikes and voltages into the shared `SimulatorRunResult` schema.

#### [MODIFY] neurocnl/backend/app/schemas/simulators.py
Add `"sc_neurocore"` to the supported simulator enumeration types.

#### [MODIFY] neurocnl/backend/app/routers/simulators.py
Register the new `ScNeuroCoreSimulatorAdapter` so the API can route `/simulate` requests to it when requested.

---

### CNL Studio (Frontend)

We will update the Flutter UI to expose the new targets to the user.

#### [MODIFY] neurocnl/frontend/lib/screens/studio/deploy/deploy_target_catalog.dart
Add `SC-NeuroCore (Simulation)` and `SC-NeuroCore (FPGA RTL)` as available targets in the Deploy catalog.

#### [MODIFY] neurocnl/frontend/lib/models/template.dart
Register the `nir_sc_neurocore` template in the dart models so it can be selected in the Studio UI when starting a new export project.

#### [MODIFY] neurocnl/frontend/lib/widgets/simulator_panel.dart
Update the simulator picker dropdown to include `sc-neurocore` as an engine option.

---

## Verification Plan

### Automated Tests
- Create unit tests in `neurocnl/neurocnl/runtime/test_sc_neurocore_simulator.py` to verify that `ScNeuroCoreSimulatorAdapter` correctly handles a basic feed-forward NIR graph, executes without errors, and properly returns the spikes/voltages schema.
- Run `pytest` on the `neurocnl` backend to ensure no regressions.
- Run `dart test` on the Flutter frontend to ensure the new models and UI components do not break existing deploy target flows.

### Manual Verification
- Launch CNL Studio locally and verify that `sc-neurocore` appears in the Simulator Panel and Deploy Targets.
- Select `sc-neurocore` as the simulator engine and run a basic feedforward network simulation, verifying that the UI receives and plots the spikes correctly.
- Use `neurocli init my_project --template nir_sc_neurocore` to verify the scaffolding generates a valid project.
