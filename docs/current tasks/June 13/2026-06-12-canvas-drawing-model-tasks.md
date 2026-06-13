# Canvas Drawing Model — Task Tracker

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
