# Task 3: Tier 1 High-Yield Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Execute the five Tier 1 "safe, high-yield" cuts from the fluff-cut-analysis — deleting deprecated/ folders, un-tracking committed DB/artifact files, removing vendored stubs, clearing root scratch dirs, and dropping Neuro-Dream-Hand output artifacts — without touching any code or contract-dependent surfaces.

**Architecture:** Five sequential atomic commits, each scoped to one cleanup category. All deletions confirmed safe by import analysis (no Python/Dart file imports from any path being deleted). `.gitignore` already covers `*.db` and `*.sqlite`; it needs two new entries for `server.log` and `simulation_report.json`.

**Tech Stack:** Git, Bash (no code compilation or tests required — all changes are pure file deletions + one `.gitignore` edit)

---

## Pre-flight

Before starting, verify you are in the repo root:

```bash
cd $HOME/NeuroMorphicToolKit
git status
```

Expected: a clean working tree (or at most unrelated uncommitted changes you should not touch).

---

## Task 1: Delete all `deprecated/` folders (49 files across 7 modules)

**Files:**
- Delete: `neurocnl/deprecated/`
- Delete: `Neurochip/deprecated/`
- Delete: `Neurobench/deprecated/`
- Delete: `Neuro-Dream-Hand/deprecated/`
- Delete: `Neurosense/deprecated/`
- Delete: `Neurohub/deprecated/`
- Delete: `Neurosim/deprecated/`

**Why safe:** Import analysis confirmed zero Python or Dart `import`/`from` statements reference any `deprecated/` path. Every folder contains only archived Markdown issue files. Git preserves history.

- [ ] **Step 1: Verify contents before deleting**

```bash
find neurocnl/deprecated Neurochip/deprecated Neurobench/deprecated \
     "Neuro-Dream-Hand/deprecated" Neurosense/deprecated \
     Neurohub/deprecated Neurosim/deprecated \
     -type f | sort
```

Expected: 49 `.md` files only — no `.py`, `.dart`, or `.json` files.

- [ ] **Step 2: Delete all deprecated/ folders**

```bash
git rm -r \
  neurocnl/deprecated \
  Neurochip/deprecated \
  Neurobench/deprecated \
  "Neuro-Dream-Hand/deprecated" \
  Neurosense/deprecated \
  Neurohub/deprecated \
  Neurosim/deprecated
```

Expected output: 49 lines of `rm 'MODULE/deprecated/...'`

- [ ] **Step 3: Verify the deletions are staged**

```bash
git status --short | grep "^D"
```

Expected: 49 deleted-file entries, all under the 7 deprecated/ paths.

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: delete all deprecated/ issue-archive folders (49 files)

Pure carrying cost — git already preserves history. No imports reference
these paths (confirmed by grep across all .py and .dart files)."
```

---

## Task 2: Un-track committed DB/artifact files + update `.gitignore`

**Files:**
- Modify: `.gitignore` (add 2 new patterns)
- Un-track (keep on disk, remove from git): all `*.db` / `*.sqlite` files currently tracked, `server.log`, `simulation_report.json`

**Why safe:** These are runtime-generated files. `.gitignore` already has `*.db` and `*.sqlite` entries but the files were committed before those rules existed. `server.log` and `simulation_report.json` are run artifacts with no source role.

**Important:** `git rm --cached` removes the file from git tracking but leaves it on disk (so the running app still has its DB). Do NOT use plain `git rm` here.

- [ ] **Step 1: Check which tracked files match the patterns**

```bash
git ls-files "*.db" "*.sqlite" server.log simulation_report.json
```

Expected: a list including at minimum `jobs.db`, `neurohub.db`, `projects.db`, `neurobench.sqlite`, `server.log`, `simulation_report.json` at the root, plus module-level DB files (e.g. `Neurohub/neurohub.db`, `Neurosim/jobs.db`, `Neurochip/neurochip/deployments.db`, `Neurobench/neurobench/neurobench.sqlite`, `neurocnl/*.db`).

- [ ] **Step 2: Un-track all DB/artifact files**

```bash
git rm --cached $(git ls-files "*.db" "*.sqlite") server.log simulation_report.json
```

Expected: one `rm '...'` line per file. Files remain on disk.

- [ ] **Step 3: Add missing patterns to `.gitignore`**

Open `.gitignore` and verify the following lines exist (add them if missing — do NOT duplicate existing `*.db` / `*.sqlite` entries):

```
server.log
simulation_report.json
```

Place them in the "Runtime artifacts" section (or at the end if no such section exists). The `*.db` and `*.sqlite` entries should already be present — do not add them again.

- [ ] **Step 4: Stage the .gitignore change**

```bash
git add .gitignore
```

- [ ] **Step 5: Confirm staging looks correct**

```bash
git status --short
```

Expected:
- `M  .gitignore` (modified, staged)
- One `D  path/to/file` line per un-tracked DB/artifact file

- [ ] **Step 6: Commit**

```bash
git commit -m "chore: un-track committed DB/artifact files, add gitignore entries

*.db and *.sqlite were already in .gitignore but files were committed
before the rule existed. server.log and simulation_report.json added.
Files kept on disk (git rm --cached) so running services are unaffected."
```

---

## Task 3: Remove vendored stub directories from Neurosense

**Files:**
- Delete: `Neurosense/neurobench/`
- Delete: `Neurosense/neurocnl/`

**Why safe:** Both are empty stub directories — no `__init__.py`, no Python source, no imports anywhere in the Neurosense module or its tests reference these paths (confirmed by grep).

- [ ] **Step 1: Confirm no imports reference these stubs**

```bash
grep -r "from neurobench\|import neurobench\|from neurocnl\|import neurocnl" \
     Neurosense/ --include="*.py"
```

Expected: **no output** (zero matches).

- [ ] **Step 2: Inspect the directories**

```bash
find Neurosense/neurobench Neurosense/neurocnl -type f | sort
```

Expected: only a `backend/` subdirectory with no Python files (pure placeholders).

- [ ] **Step 3: Delete the vendored stub dirs**

```bash
git rm -r Neurosense/neurobench Neurosense/neurocnl
```

- [ ] **Step 4: Verify staging**

```bash
git status --short | grep "^D.*Neurosense"
```

Expected: all deleted files are under `Neurosense/neurobench/` and `Neurosense/neurocnl/`.

- [ ] **Step 5: Commit**

```bash
git commit -m "chore(Neurosense): remove vendored neurobench/ and neurocnl/ stub dirs

Empty placeholder directories with no __init__.py and no imports.
Namespace collision with peer modules; confirmed safe to remove."
```

---

## Task 4: Archive root scratch directories (delete from repo)

**Files:**
- Delete: `.tmp_manual_ui/`
- Delete: `Auto agentic workflows (Jules)/`
- Delete: `UI - issues/`
- Delete: `pitches/`
- Delete: `workflow-errors/`

**Why safe:** These are scratch/notes directories with no product role. They do not contain Python modules, are not imported, and are not referenced by any build or launcher configuration. `tools/` is explicitly excluded — it contains `nmtk_mcp_server` (functional code). `UI-mistakes/` does not exist in the tree.

- [ ] **Step 1: Confirm no launcher or build config references these dirs**

```bash
grep -r "tmp_manual_ui\|agentic workflows\|UI - issues\|pitches\|workflow-errors" \
     nmtk/neuro_toolkit/assets/ scripts/ --include="*.json" --include="*.sh" --include="*.yaml"
```

Expected: **no output**.

- [ ] **Step 2: Delete the scratch directories**

```bash
git rm -r \
  ".tmp_manual_ui" \
  "Auto agentic workflows (Jules)" \
  "UI - issues" \
  "pitches" \
  "workflow-errors"
```

Expected: multiple `rm '...'` lines for each directory's contents.

- [ ] **Step 3: Verify no unintended deletions**

```bash
git status --short | grep "^D"
```

Scan the list — confirm all deleted paths start with one of the five scratch dir names above. Nothing under `docs/`, `scripts/`, `nmtk/`, or any module directory should appear.

- [ ] **Step 4: Commit**

```bash
git commit -m "chore: remove root-level scratch and notes directories

.tmp_manual_ui/, 'Auto agentic workflows (Jules)/', 'UI - issues/',
pitches/, and workflow-errors/ have no product role. Confirmed not
referenced by any launcher manifest, build script, or module import."
```

---

## Task 5: Remove Neuro-Dream-Hand output artifacts

**Files:**
- Delete: `Neuro-Dream-Hand/output/`

**Note:** `Neuro-Dream-Hand/site/` does not exist in the current tree (already removed or never committed), so only `output/` needs action.

**Why safe:** `output/` contains demo run outputs (generated artifacts, ~856K). It has no imports, is not referenced by the launcher manifest, and should live in a recordings/artifact store — not source.

- [ ] **Step 1: Confirm output/ contents are generated artifacts**

```bash
find "Neuro-Dream-Hand/output" -type f | head -20
```

Expected: data files (`.npy`, `.json`, `.csv`, images) — no `.py` or `.dart` source files.

- [ ] **Step 2: Delete output/**

```bash
git rm -r "Neuro-Dream-Hand/output"
```

- [ ] **Step 3: Commit**

```bash
git commit -m "chore(Neuro-Dream-Hand): remove committed output/ demo artifacts

Generated run outputs (~856K) committed alongside source. Belongs in
a recordings/artifact store, not the module tree."
```

---

## Verification

After all 5 commits, run a final sanity check:

```bash
# Confirm deprecated/ folders are gone
find . -type d -name "deprecated" -not -path "./.git/*"
# Expected: no output

# Confirm DB files are no longer tracked
git ls-files "*.db" "*.sqlite"
# Expected: no output

# Confirm Neurosense stubs gone
ls Neurosense/neurobench Neurosense/neurocnl 2>&1
# Expected: "No such file or directory" for both

# Confirm scratch dirs gone
ls ".tmp_manual_ui" "Auto agentic workflows (Jules)" "UI - issues" pitches workflow-errors 2>&1
# Expected: "No such file or directory" for all

# Confirm git log looks clean
git log --oneline -6
# Expected: 5 new chore commits at the top
```

---

## What is explicitly NOT done here (per task scope)

- `tools/` directory — kept (contains `nmtk_mcp_server`, functional code)
- Contract-dependent cuts (neurocnl stub converters, Neurochip sim-backed endpoints, neurocli de-listing, suite_api overlap) — saved for later
- Tier 2/3 cuts (Neurohub PM chrome reclassification, simulator consolidation, launcher setup screen merges) — not in scope
- `Neuro-Dream-Hand/site/` — does not exist, nothing to do
