---
name: nmtk-ui-test
description: >
  Runs a UI acceptance test for the NeuroMorphicToolKit (NMTK) application
  by following a structured tutorial file step-by-step, capturing a screenshot
  after every defined action, and producing a Markdown test report.
  Invoke this skill once per tutorial file.
---

# NMTK UI Test Skill

## Purpose
Execute one NMTK tutorial file as a scripted UI test inside Open Cowork.
After every step:
1. Take a screenshot (`computer_screenshot`).
2. Record PASS / FAIL / SKIP based on what is visible.
3. Write a per-task Markdown report to `docs/tutorials/reports/`.

## Required Input Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `tutorial_path` | Absolute path to the `.md` tutorial file | `docs/tutorials/cnlstudio/01_Workspace_and_Templates.md` |
| `app_url_or_window` | Window title or URL of the running NMTK Flutter app | `NeuroMorphicToolKit` |
| `report_dir` | Directory to write the report into | `docs/tutorials/reports/` |

## Workflow

### Step 1 — Read the Tutorial
```
Read the file at {{tutorial_path}} in full.
Parse every numbered or bulleted action item as a test step.
Extract the module name and tutorial ID from the filename (e.g. `cnlstudio / 01`).
```

### Step 2 — Prepare Report File
```
Create the report file:
  {{report_dir}}/{{module}}_{{tutorial_id}}_report.md

Write the header:
  # UI Test Report — {{module}} / {{tutorial_id}}
  - Tutorial: {{tutorial_path}}
  - Tested: {{ISO_TIMESTAMP}}
  - App: {{app_url_or_window}}

  | # | Step Description | Status | Screenshot |
  |---|-----------------|--------|------------|
```

### Step 3 — Execute Each Step

For each test step parsed from the tutorial:

1. **Focus the app window** — bring `{{app_url_or_window}}` to foreground.
2. **Perform the action** described in the step (click, type, navigate).
3. **Wait 1 second** for animations/async updates.
4. **Take a screenshot** and save it to:
   `{{report_dir}}/screenshots/{{module}}_{{tutorial_id}}_step{{N}}.png`
5. **Evaluate** the screenshot against the expected outcome described in the tutorial:
   - `PASS` — expected UI element or state is visible.
   - `FAIL` — expected state is NOT visible or an error dialog appeared.
   - `SKIP` — step requires hardware (e.g., Teensy/PYNQ) not connected; note reason.
6. **Append a row** to the report table:
   ```
   | {{N}} | {{step_description}} | {{STATUS}} | ![step{{N}}](screenshots/{{filename}}) |
   ```

### Step 4 — Write Summary

After all steps are executed, append to the report:

```markdown
## Summary
- Total Steps: {{total}}
- Passed: {{pass_count}} ✅
- Failed: {{fail_count}} ❌
- Skipped: {{skip_count}} ⏭️

### Failed Steps Detail
(list each failed step with the screenshot path and observed vs. expected)

### Notes
(any environment notes, e.g. backend not running, hardware unavailable)
```

### Step 5 — Print Completion Message
```
Report written to: {{report_dir}}/{{module}}_{{tutorial_id}}_report.md
Screenshots saved to: {{report_dir}}/screenshots/
```

## Rules

- **Never skip taking a screenshot** — even for SKIP-status steps, capture the current state.
- **One skill invocation = one tutorial file.** To test all tutorials, invoke this skill once per file.
- **If the backend is not running**, note it in the report under "Notes" and mark dependent steps SKIP.
- **If the app window cannot be found**, abort and write a FATAL row at the top of the report.
- **Do not modify any source files** during the test run.
- Report files use relative paths for screenshots so they are portable.

## Screenshot Naming Convention

```
{{module}}_{{tutorial_id}}_step{{zero_padded_N}}.png
# e.g. cnlstudio_01_step03.png
```

## Example Invocation Prompt (paste into Open Cowork chat)

```
Use the nmtk-ui-test skill.
tutorial_path = "docs/tutorials/cnlstudio/01_Workspace_and_Templates.md"
app_url_or_window = "NeuroMorphicToolKit"
report_dir = "docs/tutorials/reports"
```

To run all tutorials in sequence, paste one prompt per tutorial or use the batch prompt below.

## Batch All-Tutorial Prompt

```
Use the nmtk-ui-test skill for each of the following tutorials in order.
Set app_url_or_window = "NeuroMorphicToolKit" and report_dir = "docs/tutorials/reports" for all.

1. docs/tutorials/cnlstudio/00_Introduction_and_Layout.md
2. docs/tutorials/cnlstudio/01_Workspace_and_Templates.md
3. docs/tutorials/cnlstudio/02_Authoring_Networks.md
4. docs/tutorials/cnlstudio/03_Analysis_and_Validation.md
5. docs/tutorials/cnlstudio/04_Simulation_and_Monitoring.md
6. docs/tutorials/cnlstudio/05_Hardware_Deployment.md
7. docs/tutorials/cnlstudio/06_Training_and_Learning.md
8. docs/tutorials/neurobench/00_Workbench_Shell.md
9. docs/tutorials/neurobench/01_Benchmark_Execution.md
10. docs/tutorials/neurobench/02_Comparison_and_Regression.md
11. docs/tutorials/neurobench/03_Robustness_Analysis.md
12. docs/tutorials/neurobench/04_Report_Generation.md
13. docs/tutorials/neurosense/00_Neurosense_Overview.md
14. docs/tutorials/neurosense/01_Device_Configuration.md
15. docs/tutorials/neurosense/02_Live_Signal_Monitoring.md
16. docs/tutorials/neurosense/03_Spike_Encoding_and_Pipelines.md
17. docs/tutorials/neurosense/04_Recording_and_Replay.md

After completing all tutorials, write a master summary report to:
docs/tutorials/reports/MASTER_REPORT.md
listing each tutorial's pass/fail/skip counts and linking to individual reports.
```
