# Refined SNN Training & Deployment Workflow

The goal of this plan is to align the NMTK tools (`neurocli`) and UI (`nmtk_ui_core`) with the realities of Neuromorphic engineering. It splits the workflow into distinct **Training** and **Deployment** phases, utilizes Jupyter notebooks for visual SNN debugging, and provides a clear 6-step pipeline UI to guide the user.

## User Review Required

> [!IMPORTANT]
> **CLI Breaking Changes:** This plan proposes replacing the current `neuro new --target <hardware>` with a separation of concerns: `neuro new --trainer snntorch` (for scaffolding training) and `neuro deploy --hardware akida` (for hardware deployment). Does this align with your vision for the CLI?

> [!IMPORTANT]
> **Jupytext vs Raw ipynb:** Do you prefer the CLI to generate a `.py` file annotated with `# %%` (Jupytext format) or a raw `.ipynb` file natively?

## Open Questions

- Should the `neuro deploy` command automatically trigger the `nmtk-backend` to run the inference, or just generate the deployment code/bundle?
- Do we want to include `Tonic` (neuromorphic datasets) by default in the new scaffolding dependencies?

## Proposed Changes

---

### `neurocli` (Backend & Scaffolding)

The CLI currently forces users to pick a hardware target upfront. We will split this into two distinct phases: Training Scaffolding and Hardware Deployment.

#### [MODIFY] `neurocli/neurocli/new.py`
- Modify the `new` command arguments. Deprecate `--target` (hardware) and introduce `--trainer` (e.g., `snntorch`, `norse`) and `--data` (e.g., `event`, `static`).

#### [NEW] `neurocli/neurocli/deploy.py`
- Create a new command `neuro deploy` that takes a populated `.nir` file (with trained weights) and a `--hardware` target (e.g., `akida`, `lava_sim`) to compile the final hardware package.

#### [MODIFY] `neurocli/neurocli/templates/nir_snntorch/src/main.py.jinja` -> `train.py.jinja`
- Rewrite the template to output a standard PyTorch training loop.
- Format the file with `# %%` markers so it functions as a **Jupytext Notebook**, allowing visual debugging of spikes and surrogate gradients out of the box.

---

### `nmtk_ui_core` (Frontend & Visual Pipeline)

We will implement the visual representation of this 6-step pipeline using the existing `NmtkPipelineStepper` infrastructure.

#### [NEW] `nmtk_ui_core/lib/widgets/snn_workflow_stepper.dart`
- Create a specialized `SnnWorkflowStepper` widget that wraps the generic `NmtkPipelineStepper`.
- It will define the following hardcoded pipeline steps:
  1. **Select Data**
  2. **Define Architecture** (CNL/NIR)
  3. **Training Sandbox** (Jupyter/Python)
  4. **Train & Export** (GPU)
  5. **Select Hardware**
  6. **Deploy**
- Wire up the `pulseTick` property so that when step 4 (Train & Export) is active, the chip visually "heartbeats" to indicate epochs passing.
- Export this widget in the `lib/nmtk_ui_core.dart` barrel file according to `AGENTS.md` constraints.

## Verification Plan

### Automated Tests
- Update `neurocli/tests/test_new.py` to assert the new CLI arguments (`--trainer`, `--data`) and ensure the Jupytext templates render without errors.
- Run `make verify` in `neurocli` to check `ruff`, `mypy`, and `pytest`.
- Run `flutter test` in `nmtk_ui_core` to verify the new widget builds cleanly.

### Manual Verification
- Run `neuro new my_snn --trainer snntorch --data event` locally.
- Open the resulting `train.py` in VS Code / Jupyter, run the cells, and verify that the surrogate gradient plotting works.
- Verify the UI Stepper correctly transitions through the 6 states visually in the consumer app test bench.
