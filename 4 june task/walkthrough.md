# SNN Workflow Architecture Update

We have successfully restructured the NMTK architecture scaffolding and UI to reflect a realistic SNN training workflow: separating the software training sandbox from hardware deployment.

## What changed?

### 1. `neurocli` Scaffolding (Backend)
We modified the `neurocli` engine to support the new workflow:
*   **Deprecating Up-Front Hardware:** We shifted from `neuro new --target <hardware>` to `neuro new --trainer <framework> --data <type>`. The scaffolding now focuses purely on the training sandbox.
*   **Jupytext Notebooks:** The `nir_snntorch` template has been completely rewritten. It now outputs a `train.py` formatted with `# %%` markers, transforming it into a fully functional **Jupytext Notebook**. It includes dummy dataloading with `tonic` and a standard PyTorch BPTT surrogate-gradient training loop.
*   **New Deployment Command:** We added `neuro deploy` (e.g. `neuro deploy trained.nir --hardware akida`), moving hardware compilation to its rightful place *after* training is complete.

### 2. `nmtk_ui_core` Stepper (Frontend)
*   **SNN Workflow Widget:** We added the `SnnWorkflowStepper` widget, an out-of-the-box UI component that wraps `NmtkPipelineStepper`. It provides the exact 6-step pipeline you proposed: Select Data → Architecture → Sandbox → Train & Export → Select Hardware → Deploy.
*   **Pulse Animation:** It integrates with the stepper's `pulseTick` property so that when training epochs run, the "Train & Export" node visually heartbeats.

## Validation Results
*   **Linting & Types:** Passed `ruff` and `mypy` statically.
*   **CLI Tests:** Passed internal unit tests checking for the new `--trainer` argument and the correct rendering of `train.py`.
*   **UI Tests:** Passed standard Flutter static analysis and formatter.

> [!TIP]
> Try running `neuro new my_snn --trainer snntorch --data event` locally to explore the new Jupytext sandbox in VS Code!
