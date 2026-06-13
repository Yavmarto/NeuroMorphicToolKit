# Active Tasks — June 13, 2026

Audited from all prior task docs, code verification, and ADR review (ADR-001, ADR-0017–ADR-0025).  
Old folders (June 2, June 8, June 9, June 12, root-level completed docs) removed — see Archive section.

---

## 🔴 IN PROGRESS

### Canvas Drawing Model
**File:** `2026-06-12-canvas-drawing-model-tasks.md`  
**Code:** `neurocnl/frontend/lib/models/canvas/`, `backend/app/routers/notebook.py`

Components 1, 2, 5 done. **Remaining:**
- [ ] Component 3 — Edge learning rule badges (`network_canvas.dart`, `property_panel.dart`)
- [ ] Component 4 partial — `export_screen.dart` new formats (service created, screen not updated)
- [ ] Component 6 — Dart tests (`test/models/pipeline_config_test.dart`)
- [ ] Python tests (`tests/test_notebook_generate_v2.py`)
- [ ] Verification: `flutter test` + `pytest tests/test_notebook_generate_v2.py`

---

### Material Icons → Zeta Icons Migration
**File:** `2026-05-26-material-icons-to-zeta-icons-migration.md`  
**Code:** 631 `Icons.*` refs across 112 files in 6 Flutter packages

Still live in code. Tier B curated mapping approved. Tier C = C1 (ZETA-MIGRATION-EXEMPT markers).  
Kiro specs: `.kiro/specs/material-to-zeta-icons-sweep/`, `.kiro/specs/material-to-zeta-button-sweep/`

- [ ] T-ICON-1 — Implement Kiro spec governance tests sized to current state
- [ ] T-ICON-2 — Sweep neurocnl/frontend (316 hits, 52 files) — largest surface
- [ ] T-ICON-3 — nmtk/neuro_toolkit (84 hits), Neurohub (64), Neurosense (60), remaining packages
- [ ] Mark unmappable icons with `// ZETA-MIGRATION-EXEMPT: <reason>`

---

## 🟡 NOT STARTED — VALID

### CML Studio Workspace Hub Integration
**File:** `2026-06-09-cml-studio-workspace-hub-plan.md`  
**Code:** NOT FOUND — no WorkspaceHub, CMLStudio in codebase

Full workflow: architecture → training → deployment → benchmark, Hub-backed workspace files.  
ADR-0020: Studio owns deployment target selection. ADR-0023: Neurohub = metadata/registry only.  
5 tasks defined with file lists, test plan, acceptance criteria. No blocking dependencies.

---

### Validation + Deploy Readiness Gate
**File:** `2026-05-27-validation-deploy-readiness.md`  
**Code:** ValidationPanel exists, no ValidationGate / deploy guard — NOT IMPLEMENTED

ADR-0024 mandates: all submissions to training/deploy/simulator gated on `validateStatus == success && validateResult.overall == true`.  
7 tasks with exit criteria defined. No done markers. **This is an ADR-mandated requirement.**

---

### NeuroCNL Sentence Picker NIR Alignment
**File:** `2026-05-22-neurocnl-sentence-picker-nir-alignment.md`  
**Code:** `cnl_editor.dart`, `cnl_sentence_builder_dialog.dart` exist — misalignment NOT fixed

Sentence picker generates legacy biological grammar rejected by NIR-native compiler.  
ADR-001 mandates direct CNL ↔ NIR translation; legacy grammar templates violate this.  
**This is an ADR-001 correctness issue**, not cosmetic.

---

### NIR Bundle Architecture (.nmtk format)
**File:** `2026-05-24-nir-bundle-architecture.md`  
**Code:** `.kiro/specs/nir-training-bundle/tasks.md` references it — no production code found

`.nir` (structural) + `.train` (learning) split in single `.nmtk` ZIP bundle.  
Phase 0–5 roadmap, 7 identified problems with tractable solutions.  
Aligns with ADR-001 (NIR-native path). Not yet prioritized.

---

### Akida / PYNQ Target Picker (Manage Targets)
**File:** `2026-06-02-akida-manage-targets-pynq-target-picker.md`  
**Code:** No TargetPicker/PynqTarget/AkidaTarget found

Status per June 2 MASTER_TASK_ORDER: AWAITING APPROVAL (Warp plan `29360f47-74f5-4290-ab39-392b387fe8e9`).  
ADR-0021: studio→neurochip handoff contract defined. ADR-0020: Studio owns target selection.

---

### MCP Service (Phases 2–4)
**File:** `2026-05-09-mcp-service-design.md`  
**Code:** `tools/nmtk_mcp_server/mcp_runtime.py` + `__init__.py` — Phase 1 exists

Phase 1 (resources, doctor, validate) shipped. Remaining:
- [ ] Phase 2 — Deployability check (partial per May status)
- [ ] Phase 3 — Simulation tool
- [ ] Phase 4 — Deploy tool

ADR-0023: NMTK is sole control plane — MCP is an orchestration layer over `suite_api`, consistent.

---

## ⚠️ DEPRECATED — DO NOT IMPLEMENT

### State Machine Migration Plan ~~(June 8)~~
**File was:** `June 8/state_machine_migration_plan.md` — **DELETED**

**Deprecated.** Plan asked for clarifying input, never received it, zero code written.  
**Clashes with:** ADR-0017 (ShellModuleAdapter/Riverpod is the chosen pattern), ADR-0019 (Flutter feature packages), and the frontend state audit (80 Riverpod providers, 519 consumer sites — Riverpod IS the state layer). Introducing a separate state machine framework now is architecture conflict.

---

### Layer Editor View ~~(May 24)~~
**File:** `2026-05-24-layer-editor-view.md` — **moved to archive**

Explicitly deferred since 2026-05-24 ("Priority T2, deferred until T1-8 stabilises").  
T1-8 still not fully stable. Canvas drawing model (above) now covers the structured authoring need more directly. Revisit after Canvas model is shipped.

---

## 📦 ARCHIVED — Completed or superseded

| Item | Reason |
|---|---|
| `shadcn-to-zeta-flutter-migration.md` | ✅ Complete — Zeta confirmed in code |
| `tech-debt-cleanup-material-deprecated.md` (T1–4) | ✅ Tasks 1–4 done 2026-05-24; T5–8 = icons migration (tracked above) |
| `June 2/MASTER_TASK_ORDER.md` | ✅ Plans A/B/C1/C2/D2/D3 shipped; D1 Task 3 + P0 #5 deferred pending hardware |
| `June 2/RELEASE_GAP_ANALYSIS.md` | ✅ Assessment complete, gaps actioned |
| `June 2/REMAINING_EXECUTION_PLAN.md` | ✅ Sprint complete |
| `June 2/frontend-state-management-review.md` | ✅ Assessment only, Riverpod confirmed as dominant pattern |
| `June 2/2026-05-fluff-cut-analysis.md` | ✅ Analysis complete, not a task |
| `Release readiness/TEENSY_RELEASE_READINESS.md` | ✅ Release-ready 2026-04-07 |
| `Release readiness/PYNQ_RELEASE_READINESS.md` | ✅ Release-ready (simulator-backed) |
| `Release readiness/AKIDA_RELEASE_READINESS.md` | ✅ Early-usable status documented |
| `nmtk-strategic-action-plan.md` | Strategic direction doc, no concrete tasks; checkboxes are guidance not implementation |
| `June 8/state_machine_migration_plan.md` | ⚠️ Deprecated — clashes with ADR-0017/ADR-0019/Riverpod |

---

## ADR Quick Reference (decisions that constrain active tasks)

| ADR | Constraint |
|---|---|
| ADR-001 | CNL ↔ NIR direct translation only; Nengo = optional execution backend |
| ADR-0017 | ShellModuleAdapter + Riverpod is the state/shell pattern |
| ADR-0018 | Single `suite_api` on port 9000; no new isolated backends without justification |
| ADR-0019 | Flutter feature packages under `nmtk/packages/{module}_feature/` |
| ADR-0020 | Studio is sole deployment target selector; Neurosim = visualization only |
| ADR-0021 | Studio→Neurochip handoff via versioned `import_network_handoff` query param |
| ADR-0023 | NMTK = sole control plane; Neurohub = metadata/registry only |
| ADR-0024 | **Train/deploy gated on `validateStatus == success`** — validation gate is mandated |
| ADR-0025 | Exactly 11 AGENTS.md files (1 root + 10 module); no duplicates |
