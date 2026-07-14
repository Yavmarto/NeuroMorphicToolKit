# Computer Use Agent: Notebook Reproduction Guide

## Goal
Your task is to sequentially recreate each of the fully reproducible notebooks listed in `reproducible_notebooks.md` within the CNLStudio UI using your computer use capabilities. 

## Pre-requisites
- Ensure CNLStudio is open and focused on the desktop.
- Ensure you have access to the UI replication steps for each notebook (available in `current tasks/16 june/cnlstudio_notebook_analysis.md` and `cnlstudio_notebook_new_guides.md`).

## Execution Protocol

For **each notebook** in the `reproducible_notebooks.md` list, you must perform the following procedure:

1. **Follow the UI Replication Guide**:
   - Switch to the required Canvas (Model, Eval, Train, or Hardware Deployment) per the notebook's guide.
   - Add the necessary nodes, configure their parameters exactly as specified, and connect the ports.
   - Run the evaluation, training, or deployment step.

2. **Capture Screenshots with Explanations**:
   - **MANDATORY**: At every major step (e.g., finishing the Model Canvas, completing a Training run, viewing the Dynamics Tab in Results), you must take a screenshot.
   - Save the screenshot to the `agent-tests/screenshots/` directory (e.g., `agent-tests/screenshots/lif_snntorch_model_canvas.png`).
   - For each screenshot, write a brief explanation of what is shown and what action was just completed. Include these explanations in your final report.

3. **Verify Results**:
   - Check the **Results Step -> Dynamics Tab** or other relevant outputs (like accuracy metrics) to confirm the run matches the expected notebook outcome.

## Final Reporting

After you have attempted to recreate all listed notebooks, you must generate a comprehensive execution report.

Save the report to: `agent-tests/reports/notebook_reproduction_report.md`

### Report Format:
```markdown
# Notebook Reproduction Report

## Overall Summary
- Total notebooks attempted: [X/10]
- Fully successful: [X]
- Failed/Blocked: [X]

## Detailed Notebook Logs

### 1. [Notebook Name]
- **Status**: [SUCCESS / FAILED]
- **Execution Log**:
  - [Step 1 description] - Screenshot: `agent-tests/screenshots/...`
  - [Step 2 description] - Screenshot: `agent-tests/screenshots/...`
- **Bugs/Issues Encountered**: [Detail any UI bugs, missing nodes, or unexpected crashes]

... (Repeat for all notebooks) ...
```

## Failure Handling
If the CNLStudio application crashes or a notebook cannot be reproduced due to a UI bug:
1. Take a screenshot of the error or crashed state.
2. Note the exact failure point in the report.
3. Restart the application if necessary, and proceed to the next notebook. Do not get stuck in an infinite retry loop on a single broken notebook.
