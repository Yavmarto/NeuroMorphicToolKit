# UI Testing with Open Cowork — NMTK Guide

> **Target audience**: developers and QA agents using Open Cowork to validate the
> NeuroMorphicToolKit Flutter UI against the tutorials in `docs/tutorials/`.

---

## What is Open Cowork?

**Open Cowork** ([github.com/OpenCoworkAI/open-cowork](https://github.com/OpenCoworkAI/open-cowork))
is a free, open-source AI agent desktop app for macOS and Windows. It wraps Claude Code
(or other LLMs) into a GUI, adds a **Skills** system (reusable agent workflows), and supports
computer-use GUI control — meaning the AI can _see_ and _interact with_ your desktop apps.

The NMTK tutorials in `docs/tutorials/` already document the agent-facing UI contract
in their `Agent Note` callouts, making them ideal scripts for automated UI testing.

---

## Prerequisites

### 1. Install Open Cowork

```bash
brew tap OpenCoworkAI/tap
brew install --cask --no-quarantine open-cowork
```

Or download the `.dmg` from
[github.com/OpenCoworkAI/open-cowork/releases](https://github.com/OpenCoworkAI/open-cowork/releases).

### 2. Configure an API Key

In Open Cowork → Settings (⚙️ bottom-left):
- **API Key**: your Anthropic key (or OpenRouter key)
- **Model**: `claude-sonnet-4-5` (recommended for GUI understanding)
- **Base URL**: leave blank for Anthropic direct

### 3. Set Workspace to this Repo

In Open Cowork, select **Workspace = `/Users/yoshimartodihardjo/NeuroMorphicToolKit`**.

This makes the skill available because Open Cowork loads skills from:
```
<workspace>/.claude/skills/
```

The `nmtk-ui-test` skill is at:
```
.claude/skills/nmtk-ui-test/SKILL.md   ← this file defines the test workflow
```

### 4. Start the NMTK App

Make sure the Flutter desktop app is running:
```bash
cd nmtk_ui_core && flutter run -d macos
```

The app window title is `NeuroMorphicToolKit` — that's what the skill uses to
bring it into focus.

---

## Running a Single Tutorial Test

Paste this into the Open Cowork chat:

```
Use the nmtk-ui-test skill.
tutorial_path = "docs/tutorials/cnlstudio/01_Workspace_and_Templates.md"
app_url_or_window = "NeuroMorphicToolKit"
report_dir = "docs/tutorials/reports"
```

Open Cowork will:
1. Read the tutorial file.
2. Step through each action in the UI.
3. Take a **screenshot after every step**.
4. Write a Markdown report to `docs/tutorials/reports/cnlstudio_01_report.md`.

---

## Running All 17 Tutorials (Batch)

Paste the **Batch All-Tutorial Prompt** from
`.claude/skills/nmtk-ui-test/SKILL.md` into the Open Cowork chat.

This runs all tutorials sequentially and generates:
```
docs/tutorials/reports/
├── cnlstudio_00_report.md
├── cnlstudio_01_report.md
├── ...
├── neurobench_04_report.md
├── neurosense_04_report.md
├── MASTER_REPORT.md          ← summary linking all reports
└── screenshots/
    ├── cnlstudio_00_step01.png
    ├── cnlstudio_01_step01.png
    └── ...
```

---

## Report Format

Each report looks like:

```markdown
# UI Test Report — cnlstudio / 01
- Tutorial: docs/tutorials/cnlstudio/01_Workspace_and_Templates.md
- Tested: 2026-05-16T11:30:00+02:00
- App: NeuroMorphicToolKit

| # | Step Description | Status | Screenshot |
|---|-----------------|--------|------------|
| 1 | Open Workspace button visible in action bar | ✅ PASS | ![step01](screenshots/cnlstudio_01_step01.png) |
| 2 | File dialog opens on click | ✅ PASS | ![step02](screenshots/cnlstudio_01_step02.png) |
| 3 | Template Gallery icon clickable | ✅ PASS | ![step03](screenshots/cnlstudio_01_step03.png) |
...

## Summary
- Total Steps: 8
- Passed: 7 ✅
- Failed: 1 ❌
- Skipped: 0 ⏭️

### Failed Steps Detail
- Step 4: Template search bar not visible. Expected filter input in gallery dialog.
  Screenshot: screenshots/cnlstudio_01_step04.png
```

---

## SKIP vs FAIL

| Status | When | Example |
|--------|------|---------|
| ✅ PASS | UI matches expected state | Button is visible and responsive |
| ❌ FAIL | UI diverges from tutorial expectation | Panel missing, error dialog shown |
| ⏭️ SKIP | Step requires hardware not connected | Teensy/PYNQ deploy step when no board present |

---

## Tips

- **Enable Computer Use** in Open Cowork settings if you want the agent to click
  actual UI elements rather than just read and describe them.
- Run `make` (or `make dev`) first to ensure the backend is up on the correct port —
  many tutorial steps depend on a live backend connection.
- Screenshots are saved relative to the workspace so they render correctly in
  GitHub Markdown previews.
