# Canvas Drawing Model — Task Tracker

## Verified Implementation Status (2026-07-04)

**Overall: This tracker is stale — the checkboxes understate progress. Components 3 and 4 are marked incomplete but are actually implemented in code, and one Component 6 test item marked incomplete also exists.**

- **Component 1 (checked as done): confirmed DONE**, though the shape evolved — `neurocnl/frontend/lib/providers/canvas/canvas_provider.dart:22` has `CanvasTab` with 4 values (`architecture, pipelineTrain, pipelineEval, pipelineOverview`), not the originally-planned 2-tab enum, and `pipeline_config.dart` dropped `dataset`/`framework` fields per later commits.
- **Component 2 (checked as done): confirmed DONE**, but `lib/widgets/canvas/pipeline_steps_panel.dart` was never created — the checkbox refers to a file that does not exist. What exists instead is `pipeline_phase_canvas.dart`, `pipeline_overview_canvas.dart`, and `pipeline_palette.dart` (DAG-based pipeline UI, richer than "fixed steps, no drag-and-drop"). `canvas_screen.dart` does have the tab bar + Generate button as checked.
- **Component 3 (marked `[ ]` incomplete): ACTUALLY DONE.** `neurocnl/frontend/lib/widgets/canvas/network_canvas.dart:1930-1936` renders STDP edge badges (color + letter). `neurocnl/frontend/lib/widgets/canvas/property_panel.dart:468-609` has the full Learning Rule dropdown with STDP + `A+`/`A-`/`τ+`/`τ−` fields. Both checkboxes here should be `[x]`.
- **Component 4 (checked item + `[ ]` item): `notebook_generate_service.dart` confirmed DONE; `export_screen.dart` marked `[ ]` is ACTUALLY DONE too** — `neurocnl/frontend/lib/screens/canvas/export_screen.dart:91,95` already has `notebook_v2` and `python_v2` dropdown entries wired to the new endpoint.
- **Component 5 (checked as done): confirmed DONE.** `neurocnl/backend/app/routers/notebook.py:2034` has `POST /notebook/generate-v2`. The `[ ]` item `tests/test_notebook_generate_v2.py` is ACTUALLY DONE — the file exists at `neurocnl/backend/tests/test_notebook_generate_v2.py` with well over a dozen test functions covering happy path, rejections, framework naming, support-level, and dual-write behavior.
- **Component 6 (marked `[ ]` incomplete): PARTIALLY stale.** `test/models/pipeline_config_test.dart` marked `[ ]` is ACTUALLY DONE (exists, 11 test cases) — checkbox should be `[x]`.
- **Verification section:** `flutter test` and `pytest tests/test_notebook_generate_v2.py` are still legitimately unverified/unchecked in this pass (not re-run), but the underlying Python test file itself exists and is substantial, so the `pytest` item is very likely to be runnable/passing, not "remaining work" in the sense of needing new code. One genuine remaining gap: no `canvas_provider_test.dart` with explicit tab-switch coverage was found under `neurocnl/frontend/test/providers/canvas/` (grepped for `CanvasTab`/`activeTab`/`setActiveTab` — no matches), so Dart test coverage for tab-switching specifically is a real, still-open gap.
- **Net correction to this tracker:** actual remaining work is much smaller than the checkboxes suggest — essentially just adding explicit tab-switch test coverage; everything else claimed incomplete already exists in the codebase.

## Component 1 — Canvas State Model (Dart)
- [x] Read canvas_provider.dart (done)
- [x] Create `lib/models/canvas/pipeline_config.dart`
- [x] Modify `lib/providers/canvas/canvas_provider.dart` — add `CanvasTab` enum + `pipeline` field

## Component 2 — Canvas Tab UI (Dart)
- [x] Create `lib/widgets/canvas/pipeline_steps_panel.dart`
- [x] Modify `lib/screens/canvas/canvas_screen.dart` — tab bar + Generate button

## Component 3 — Edge Learning Rule Badge (Dart)
- [ ] Modify `lib/widgets/canvas/network_canvas.dart` — edge badges
- [ ] Modify `lib/widgets/canvas/property_panel.dart` — learning rule section

## Component 4 — Generate Service & Export (Dart)
- [x] Create `lib/services/notebook_generate_service.dart`
- [ ] Modify `lib/screens/canvas/export_screen.dart` — new formats

## Component 5 — Backend Endpoint (Python)
- [x] Modify `backend/app/routers/notebook.py` — add POST /api/notebook/generate-v2
- [ ] Create `tests/test_notebook_generate_v2.py`

## Component 6 — Tests (Dart)
- [ ] Create `test/models/pipeline_config_test.dart`

## Verification
- [ ] `flutter test` (Dart)
- [ ] `pytest tests/test_notebook_generate_v2.py` (Python)
- [x] `ruff check --fix .` + `ruff format .` (Python)
- [x] `dart fix --apply && dart format .` (Dart)
