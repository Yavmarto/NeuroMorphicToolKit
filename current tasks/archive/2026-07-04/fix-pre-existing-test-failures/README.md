# Fix Pre-Existing Test Failures

Full `flutter test` in `neurocnl/frontend` had ~120 pre-existing `[E]` failures, unrelated to any single feature (confirmed via git-stash on baseline commit `dbb0944b`). Fixed via 7 root-cause clusters + cleanup. Plan: `/Users/yoshimartodihardjo/.claude/plans/make-an-implementation-plan-sleepy-valiant.md`.

## Result
`flutter test` green except the already-documented flaky `simulator_preflight_provider_test.dart` glados PBT reruns (out of scope, pre-existing flakiness unrelated to this work).

## Clusters fixed

- **A** — stale widget finders / post-frame-callback pump timing across `studio_screen_test.dart` and friends; removed stale `'pynq'` deploy-target catalog entry in `workspace_provider.dart`.
- **B** — rewrote `studio_sync_notifier_nir_test.dart` / `nir_editor_sync_preservation_test.dart` / `studio_sync_validation_preservation_test.dart` to match two already-shipped behavior changes (debounce method gutted to no-op, view-mode guard removed).
- **C** — added missing `TestWidgetsFlutterBinding.ensureInitialized()`.
- **D** — added `ref.mounted` guard in `sweep_provider.dart`'s `runSweep` (real lifecycle bug).
- **E** — fixed `autoDispose` race in `mirror_projection_validation_test.dart`'s stale-state-recovery test via `container.listen` keep-alives.
- **F** — real bug in `workspace_file.dart`: missing `explicitToJson`-equivalent manual `@JsonKey` serializers for `pipelineCache`/`nirArtifactCache`/`pipelineState`/`nirState`, breaking direct `fromJson(toJson())` round-trips (production code was masked by always going through `jsonEncode`/`jsonDecode`).
- **G** — six independent mechanical fixes:
  - `training_inspector_panel_test.dart`: missing `cnlSpec` param on test override (compile error), plus a second real issue found during verification — `hasSpec` is now derived from the active workspace file's content, not `specTextProvider`; the "no spec" test needed `workspaceState(content: '')`.
  - `studio_target_registry_service_test.dart`: stale port `8090` → `8091`.
  - `file_picker_native_file_backend_test.dart`: Linux DBus test guarded with `skip: !Platform.isLinux` (crashes on macOS host).
  - `platform_helper_stub_test.dart`: rewrote to match intentional `downloadFile` → always-fallback contract (confirmed via `git log -p`).
  - `pipeline_integration_test.dart`: the "Deploy" tab's content is gated on `trainingHistoryProvider` (populated via real SSE training), not on generate/simulate results, and the deploy panel is nested behind a "Deploy to Hardware" expand toggle. Test now seeds training history *after* navigating to the Deploy tab (required — `trainingHistoryProvider` is `autoDispose` and needs an active watcher) and taps the expand toggle before asserting.

## Follow-up left open
`simulator_preflight_provider_test.dart`'s glados PBT reruns remain flaky (unchanged, pre-existing, documented in the plan) — not addressed here.
