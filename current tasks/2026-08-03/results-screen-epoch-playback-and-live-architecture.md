# Results screen: epoch playback + tab overlap + dark buttons — 2026-08-03

Continuation of the plan started 2026-08-02 (`~/.claude/plans/there-have-been-great-lucky-hamster.md`).
On session start, parts A (dark buttons), C (stacked tab bars), and D.1/D.3
(loss/accuracy curve with epoch marker in the Dynamics tab) were already
implemented and uncommitted; backend per-epoch activity capture (B, steps
1-4) was done and tests green. The one piece still missing was the actual
point of the bug report: the epoch scrubber still wasn't wired into the
Grid/Raster view.

## What was finished this session

**B.5 — epoch scrubber → Grid/Raster wiring (frontend, the core fix):**
- `api_client.dart`: `getTrainingActivityNpy` now takes an optional `epoch`
  param and returns `ActivityFetchResult` (bytes + servedEpoch +
  availableEpochs) instead of raw bytes; 404s throw `ActivityFetchException`
  carrying the available-epochs list instead of a raw `ApiException`.
- `training.py`: success and 404 responses on `/training/jobs/{id}/activity.npy`
  now carry `X-Available-Epochs` (and `X-Served-Epoch` on success) headers,
  since the endpoint returns raw binary and can't attach JSON metadata.
- `results_step.dart` `_NetworkPlaybackPanel`: now takes the scrubber's real
  epoch number, snaps to the nearest epoch the backend actually captured
  (activity is only captured every ~5 epochs, see
  `_ACTIVITY_CAPTURE_CADENCE_EPOCHS` in `notebook.py`), refetches on
  `didUpdateWidget` only when the *nearest captured* epoch changes (not on
  every single-step drag), and shows "Showing captured epoch N" when the
  loaded snapshot differs from the exact scrubbed epoch — so the gap
  between scrub resolution and capture resolution is explicit, never silent.
- Regenerated mockito mocks (`dart run build_runner build`) to match the
  new `ApiClient` method signature.

## Explicitly not done (scoped out, not forgotten)

- **D.2** (per-layer activity sparkline trend next to the architecture
  diagram) and **D.4** (live auto-follow mode while a job is training) —
  the plan phrased these as proposals, not confirmed bugs; not implemented.
- **Widget test** for the scrubber→panel wiring (plan's verification
  section asked for one) — skipped. There's no existing widget-test
  harness for any Studio *step* screen (mocking canvas/training providers
  for a screen this size would be a new pattern, not a small addition), so
  this was left as a real gap rather than forced in. Manual verification
  wasn't done either — no completed training run was available in this
  session to click through the Results step live.
- The sidebar's own Dynamics-tab activity fetch (`_FinalMetricsSidebar`)
  intentionally still always loads the latest captured epoch — the plan's
  root-cause analysis only named the main `_NetworkPlaybackPanel` fetch as
  broken, so the sidebar's raster view wasn't touched to avoid scope creep.

## Verification done

- `PYTHONPATH=. pytest neurocnl/backend/tests/{test_kernel_runner,test_notebook_codegen,test_training_router}.py` — 103 passed, 7 skipped (torch import fails in this conda env, pre-existing/unrelated).
- `ruff check` on all touched backend files — clean.
- `mypy --strict` — hit a pre-existing environment problem (internal error
  in an unrelated `transformers` file, plus a missing `nir` stub) unrelated
  to these changes; not something this session introduced or could fix.
- `flutter analyze` on touched files — clean except one pre-existing
  unrelated `unused_local_variable` warning at `results_step.dart:767`.
- `dart format` — applied (only `api_client.dart` needed it).
- `flutter test` (full suite, ~1650 tests) — one pre-existing failure in
  `setup_step_local_import_test.dart` (`MissingPluginException` on
  `shared_preferences`, reproduces standalone with zero relation to any
  file touched here); everything else green, including a targeted rerun of
  `test/providers/` and `test/screens/studio_screen_test.dart` after the
  mock regeneration.

## Restart / where to look

Nothing left mid-edit; the working tree is a coherent, testable state for
parts A/B/C/D.1/D.3. To pick this back up: read the "explicitly not done"
section above, and to manually verify B.5 end-to-end, run
`flutter run -d macos` from `nmtk/neuro_toolkit`, connect to
`192.168.2.90`, and drag the Epoch scrubber on a completed run's Results
step while on the Grid or Raster tab.
