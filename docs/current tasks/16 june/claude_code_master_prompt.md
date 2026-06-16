# CNLStudio Reverse-Engineering Analysis Prompt

Please analyze the following six notebooks from the `paper` directory to determine their viability for reverse-engineering into the CNLStudio UI workflows.

**Target Notebooks:**

1. `paper/03_rnn/Braille_training_snntorch.ipynb`
2. `paper/03_rnn/snntorch_apply_subtract.ipynb`
3. `paper/02_cnn/snntorch_apply.ipynb`
4. `paper/01_lif/lif_snntorch.ipynb`
5. `paper/03_rnn/nengo_apply.ipynb`
6. `paper/03_rnn/plots.ipynb`

## Task 1: Reverse-Engineering Viability Analysis

For each notebook, analyze the Python/snnTorch/Nengo code and evaluate how easily it can be translated into CNLStudio's core canvasses (Model, Training, Eval, Hardware Deployment, and Monitoring).

- Identify how the code maps to the underlying `neurocnl` representations.
- Flag any missing features, edge cases, or potential technical blockers in CNLStudio that would prevent a 1:1 translation of the notebook's logic.

## Task 2: User Action Mapping (UI Guide)

For each notebook, provide a step-by-step guide detailing exactly what a user would need to do in the CNLStudio UI in each canvas to replicate the notebook's functionality. Map the code directly to UI actions.

*Example Mapping:* If the notebook uses `snn.RSynaptic(alpha=0.9, ...)` connected to an `nn.Linear` layer, instruct the user to "Open the Model Canvas, drag an RSynaptic node from the palette, set its alpha parameter to 0.9 in the properties panel, and draw a connection to a Linear node."

## Output Format

Produce a comprehensive markdown report containing your findings, structured by notebook. For each notebook, include:

1. **Notebook Purpose:** A brief summary of what the code accomplishes.
2. **Viability Analysis:** Can it be reverse engineered? Are there any blockers?
3. **UI Replication Guide:** A step-by-step walkthrough of what the user must click, drag, type, and configure in the CNLStudio canvasses to recreate the notebook.
