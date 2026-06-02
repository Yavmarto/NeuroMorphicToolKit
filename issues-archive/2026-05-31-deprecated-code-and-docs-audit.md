# Deprecated Code & Docs Audit (2026-05-31)

**Purpose.** Suite-wide inventory of code and documentation that is explicitly
deprecated, marked legacy, superseded, or staged for removal. This is
analysis-only: nothing here deletes code or docs. Every entry cites a concrete
path (and line where useful) so an owner can act with confidence.

**Method.** Searched all module trees for `deprecated`, `DeprecationWarning`,
`@deprecated`, `legacy`, `obsolete`, `superseded`, and "to be removed", then
read each hit in context. Vendored artifacts (iOS/macOS `Pods`, `.mypy_cache`,
generated `*.mocks.dart`, `recent_commits.patch`, build output) are excluded as
noise. Feature names that merely contain "legacy" (e.g. `no_legacy_pills`
tests) are excluded unless they flag real retired behavior.

**How to read it.**
- **Runtime deprecation** — code path still callable but emits a warning / `410`
  / `Deprecation` header and points to a replacement.
- **Legacy compat** — kept only for backward compatibility; replacement exists.
- **Retired in-tree** — `deprecated/` folders holding archived issue files.
- **Doc deprecation** — documentation flagging a surface, pipeline, or doc tree
  as deprecated/superseded.

---

## Suite-wide patterns

- **`deprecated/` folders in every module (49 markdown files total).** Each
  module carries a `deprecated/issues-archive/` tree of retired POC issue files;
  `neurocnl/deprecated/` also holds a stray `TODO.md`. These are pure carrying
  cost — git already preserves history. Tracked as a "Cut (High confidence)"
  item in `docs/2026-05-fluff-cut-analysis.md`.
- **Nengo removed from the public NeuroCNL surface.** Multiple code paths and
  docs flag Nengo as legacy-only / unsupported after the CNL→NIR direct
  translation work (`docs/ADR-001-CNL-NIR-Direct-Translation.md`).
- **Material → Zeta migration in progress.** Direct Material widget/icon usage
  is being retired in favor of the Zeta design system; partial, with explicit
  TODO/exempt markers left in code.

---

## neurocnl

Runtime deprecations
- `neurocnl/neurocnl/pipeline.py:673` — `compile_to_nir()` emits
  `DeprecationWarning`; replacement is `neurocnl.compile.compile_to_nir()`
  (returns a `nir.NIRGraph`, structured `CompileError`).
- `neurocnl/neurocnl/export/sinabs_exporter.py:24` — exporting sinabs via an
  `nir.NIRGraph` is deprecated; pass a `NetworkIR` for direct conversion.
- `neurocnl/backend/app/services/sleep_runner.py:25` — `run_sleep_training()`
  is deprecated; delegates to `SleepPesAdapter` (see `neurocnl/CHANGELOG.md:24`).
- `neurocnl/backend/app/routers/simulate.py:17` — `POST /api/simulate` is a
  deprecated compatibility route that returns `410 Gone` on the NIR-only
  surface.

Legacy compat
- `neurocnl/neurocnl/export/nir_exporter.py:89` — `_legacy_nengo_to_nir_graph()`
  retained as the legacy Nengo→NIR path.
- `neurocnl/neurosim/app/services/components.py:40` — shim redirecting access for
  deprecated global variables to the new state object (duplicated copy of the
  Neurosim service, see Neurosim section).
- `neurocnl/frontend/lib/services/open_external_url_web.dart:1`,
  `neurocnl/frontend/lib/services/import_text_file_picker_web.dart:1`,
  `neurocnl/frontend/lib/services/platform_helper_web.dart:1` — files opt out of
  lint via `// ignore_for_file: deprecated_member_use` (dart:html web APIs).

Retired in-tree
- `neurocnl/deprecated/` — `TODO.md` plus `issues-archive/` (incl.
  `003-poc-deprecate-old-automation-workflows.md`).

Doc deprecations
- `neurocnl/docs/support_matrix.md:28` — Nengo is "unsupported — removed from
  product surface"; `generate`/`export`/`EXPORTERS` symbols deprecated.
- `neurocnl/docs/api/pipeline.md:11` and `neurocnl/docs/api_reference.md:42` —
  `/api/simulate` documented as deprecated, returns `410`.

---

## Neurochip

Runtime deprecations
- `Neurochip/neurochip/app/routers/akida.py:631` — `POST /verify` declared
  `deprecated=True`; sets `Deprecation: true` and `Link: rel="successor-version"`
  headers. Canonical replacements are `POST /api/neurochip/akida/map` and
  `GET /api/neurochip/akida/status`.

Legacy compat
- `Neurochip/neurochip/app/routers/akida.py:89` and `:353` — population/connection
  builder and deploy artifact path documented as the "legacy schema / legacy
  path".

Retired in-tree
- `Neurochip/deprecated/issues-archive/` — 7 files.

Doc deprecations
- `Neurochip/docs/neurochip/api_reference.md:103` — documents `/akida/verify` as a
  deprecated compatibility route pointing to `/map` and `/status`.

---

## Neurobench

Retired in-tree
- `Neurobench/deprecated/issues-archive/` — 7 files.

No active runtime deprecation markers found in Neurobench source beyond the
shared archived-issues pattern.

---

## Neuro-Dream-Hand

Runtime deprecations
- `Neuro-Dream-Hand/neurodreamhand/experiments/contracts.py:14` — module is a
  deprecated backward-compat stub; emits `DeprecationWarning`, import from
  `neurodreamhand.contracts` instead.
- `Neuro-Dream-Hand/neurodreamhand/hardware/contracts.py:22` — same pattern;
  re-exports moved to `neurodreamhand.contracts`.

Retired in-tree
- `Neuro-Dream-Hand/deprecated/issues-archive/` — 6 files (incl.
  `002-poc-consolidate-contracts-directory.md`, which motivated the stubs above).

---

## Neurosense

Retired in-tree
- `Neurosense/deprecated/issues-archive/` — 7 files.

No active runtime deprecation markers found in Neurosense source beyond the
shared archived-issues pattern.

---

## Neurosim

Legacy compat
- `Neurosim/neurosim/app/services/components.py:40` — shim redirecting deprecated
  global variables to the new state object. Note this file is duplicated at
  `neurocnl/neurosim/app/services/components.py:40`; the bundled `neurocnl/neurosim`
  copy of the simulator is itself flagged for consolidation in
  `docs/2026-05-fluff-cut-analysis.md`.

Retired in-tree
- `Neurosim/deprecated/issues-archive/` — 9 files (largest `deprecated/` folder
  in the suite).

---

## Neurohub

Legacy compat
- `Neurohub/neurohub/contracts/bundle_contracts.py:53`, `:88`, `:111`, `:114` —
  legacy path checks and a `bundle_hash` alias kept "to support legacy tests".
- `Neurohub/neurohub/app/services/auth_service.py:25` — `CryptContext(...,
  deprecated="auto")`; passlib config marking old hash schemes deprecated
  (intentional security posture, not a removal target).
- `Neurohub/frontend/analysis_options.yaml:18` — `deprecated_member_use: ignore`
  suppresses the analyzer warning suite-frontend-wide (masks future deprecations).

Retired in-tree
- `Neurohub/deprecated/issues-archive/` — 8 files.

Doc deprecations
- `Neurohub/neurohub_spec.md:181` — `SuiteHealthBar` marked **DEPRECATED**
  (orchestration-era, to be removed).
- `Neurohub/neurohub_spec.md:243` and `:284` — `health_checker.py` and
  `test_orchestration_properties.py` marked **TO BE REMOVED**.

---

## nmtk (launcher / control plane)

Legacy compat
- `nmtk/neuro_toolkit/lib/providers/module_provider.dart:8,48,55` (and downstream
  usages through `:555`) — `_legacyProcessManager` backward-compat layer kept
  alongside the newer control-service path.
- `nmtk/neuro_toolkit/lib/workspace/native_surface_registry.dart:3` — "Legacy
  shell adapter imports (kept for backward-compat with `/workspace?moduleId=`
  route)".
- `nmtk/neuro_toolkit/lib/routing/router.dart:23` — root redirect handling
  "legacy deep links".

Retired in-tree
- `nmtk/neuro_toolkit/issues-archive/002-poc-cleanup-deprecated-ci-workflows.md`
  (also mirrored at `nmtk/issues-archive/`).

---

## nmtk_ui_core (shared widget library)

Scheduled for removal
- `nmtk_ui_core/lib/nmtk_ui_core.dart:1` — `export 'app_theme.dart'; //
  TODO(T-DEBT): migrate test harnesses to NmtkZetaTheme, then delete`. The
  legacy `app_theme.dart` is retained only for test-harness compat pending the
  Zeta migration.
- `nmtk_ui_core/lib/app_theme.dart` — kept in the barrel per the T-DEBT task;
  `NmtkZetaTheme` is the replacement.

---

## neurocli

Retired in-tree
- `neurocli/issues-future/09-npy002-numpy-random.md` — archived/future issue file.

Doc/status note
- Flagged in `docs/2026-05-fluff-cut-analysis.md` as an aspirational stub that
  the strategic plan already plans to de-list as a peer module (manifest entry
  in `nmtk/neuro_toolkit/assets/modules.json`). Not a code deprecation, but the
  listing is slated for removal.

---

## Root docs & dev pipelines

Active deprecation/cleanup tasks
- `docs/current tasks/2026-05-24-tech-debt-cleanup-material-deprecated.md` —
  removes deprecated legacy Nengo symbols and Material widgets; Tasks 1–4 done,
  5–8 (138 Material button hits across 5 frontends) deferred.
- `docs/current tasks/2026-05-26-material-icons-to-zeta-icons-migration.md` —
  631 raw `Icons.*` references to migrate to `zeta_icons`; Tier C kept as
  Material with `// ZETA-MIGRATION-EXEMPT:` markers.
- `docs/2026-05-fluff-cut-analysis.md` — full value-vs-upkeep audit; recommends
  cutting the 49 `deprecated/` files and consolidating duplicated trees.

ADR / contract removals
- `docs/ADR-claude/0022-remove-legacy-import-network-fallback.md` — removes the
  legacy `import_network` query param (deprecation window closed 2026-04-28);
  only `import_network_handoff` is supported.

Superseded / duplicated doc trees
- `docs/issues-archive/003-poc-deprecate-gpt54-dev-pipeline.md` — `gpt5.4-dev-pipeline`
  superseded by `unified-dev-pipeline` (the gpt5.4 tree is already gone).
- `docs/issues - future/001-poc-consolidate-active-vs-archived-documentation.md`
  — calls out `Opus-dev-pipeline`, `Gemini-dev-pipeline`, and `unified-dev-pipeline`
  as overlapping generations needing status banners. `docs/Opus-dev-pipeline/`
  and `docs/Gemini-dev-pipeline/` still exist as older, superseded generations.
- `docs/archive/` — large body of dated status reports retained as history
  (not active guidance).

---

## Suggested follow-ups (not performed here)

- Decide cut vs. keep for the 49 `deprecated/issues-archive/` files (git holds
  the history).
- Finish the Material→Zeta widget/icon sweep so the `app_theme.dart` barrel
  export and `// ZETA-MIGRATION-EXEMPT:` markers can be removed.
- Consolidate the duplicated `neurocnl/neurosim` vs `Neurosim/neurosim` trees so
  the `components.py` deprecated-globals shim lives in one place.
- Add status banners to `docs/Opus-dev-pipeline/` and `docs/Gemini-dev-pipeline/`
  (per the open consolidation issue) or archive them.
- Remove `Neurohub`'s `SuiteHealthBar`, `health_checker.py`, and
  `test_orchestration_properties.py` once the orchestration-era surface is gone.
