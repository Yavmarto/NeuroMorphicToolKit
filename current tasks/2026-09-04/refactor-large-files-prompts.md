# Refactor prompts for files over 1000 lines

Source list: `current tasks/2026-08-25/files_over_1000_lines.txt` (regenerated
2026-09-04, 19 files verified still over 1000 lines via `wc -l`). Grouping
rationale is in this session's chat; groups below were checked against actual
imports, not just filenames — coupling notes say which is which.

Read `AGENTS.md` and `CODING_STYLE_GUIDE.md` (and any module-level
`AGENTS.md`) before starting any of these. Each prompt is self-contained and
can be run in a separate session/agent. Do not start a prompt's work until
the previous one in the same file cluster is committed, since several touch
the same package.

---

## Prompt 1 — Flutter client deployment service (confirmed cluster, 2 files, 4637 lines)

```
Refactor two oversized files in the NMTK Flutter launcher app into smaller,
single-responsibility files. Read `nmtk/AGENTS.md` and
`CODING_STYLE_GUIDE.md` first.

Files:
- nmtk/neuro_toolkit/lib/services/deployment/client_deployment_service.dart (2339 lines)
- nmtk/neuro_toolkit/test/services/client_deployment_service_test.dart (2298 lines)

Production file — `ClientDeploymentService` is a god-class implementing
`DeploymentService` that already composes collaborators via constructor DI
(`SshDeploymentService`, `LocalDeploymentService`, `KubernetesDeploymentService`,
`AdministratorSessionManager`, `DeploymentPersistence`). Continue that same
composition pattern — do NOT use `part`/`part of` files, and do not split a
single class's body across files.

Extract these cohesive pieces into new files under
`nmtk/neuro_toolkit/lib/services/deployment/`, each as its own class injected
into `ClientDeploymentService`'s constructor (with a sensible default like the
existing collaborators):

1. `deployment_asset_bundle.dart` — move `DeploymentAssetBundle` and
   `_DeploymentBundleIntegrityException` out verbatim (lines ~25-111); they
   have no dependency on `ClientDeploymentService` state.
2. `remote_server_provisioner.dart` — the brand-new-host bootstrap flow:
   `setupRemoteServer`, `bootstrapRemoteUser`, `_runRemoteSetup`,
   `_remoteSetupFailureDetails`, `_bootstrapRemoteUser`, `_canonicalIpv4`.
3. `remote_deployment_runner.dart` — SSH execution against an already-known
   target: `_startRemoteDeployment`, `_pollRemoteJob`, `_ensureRemoteEngine`,
   `_remoteDeployDir`, `_uploadAssets`, `_verifyRemoteAssets`,
   `_uploadAssetsForRepair`, `_runChecked`, `_runRemoteCommand`.
4. `deployment_health_checker.dart` — readiness/diagnosis:
   `diagnoseTarget`, `diagnoseHost`, `repairTarget`, `_waitForHealth`,
   `_isApiReady`, `_verifyRemoteApis`, `_clientReachabilityFailure`.
5. Fold `_runLocalDeployment`/`_runKubernetesDeployment`/`_materializeAssets`/
   `_runLocalChecked` logic into the existing `LocalDeploymentService` and
   `KubernetesDeploymentService` classes instead of a new file, since those
   collaborators already exist for exactly this purpose.

Leave `ClientDeploymentService` itself as a thin orchestrator: `load`,
`deploy`, `linkExistingTarget`, `fetchJob`, `cancelJob`, `retryJob`,
`retryJupyter`, `reinstallTarget`, `forgetHostKey`, plus small glue
(`_updateJob`, `_persistCurrentJob`, `_emit`, `_setActiveOperation`,
`_appendTerminalOutput`, `_newId`, `_newAdminToken`) that every collaborator
needs — pull the job-progress glue into one small `_JobProgressReporter`
helper if that reads cleaner.

Test file — it's currently one flat `main()` with 50 `test()` calls (no
`group()`s) and three shared fakes (`_MemorySecretStorage`,
`_ManifestAssetBundle`, `_BlockingSshDeploymentService`). Mirror the
production split:
- Move the three shared fakes into a new
  `nmtk/neuro_toolkit/test/services/deployment/client_deployment_test_fakes.dart`
  and import it from every new test file.
- Split the 50 tests by which collaborator/feature they exercise (remote
  bootstrap + Podman fallback, remote deployment/asset upload, asset bundle
  checksum verification, health/doctor HTTP checks, job persistence/redaction)
  into files named to match, e.g.
  `client_deployment_service_bootstrap_test.dart`,
  `client_deployment_service_remote_deploy_test.dart`,
  `client_deployment_service_bundle_test.dart`,
  `client_deployment_service_health_test.dart`.
- Every test must keep calling through the real `ClientDeploymentService`
  public API (not the extracted collaborators directly) unless a test is
  specifically about the extracted class's own logic — check what each test
  currently asserts before deciding where it goes.

Constraints:
- No behavior changes. Every existing test must still exist and pass,
  unmodified in assertions (only moved/regrouped).
- Run `flutter test nmtk/neuro_toolkit/test/services/` (from
  `nmtk/neuro_toolkit`) after each extraction step and keep it green.
- Run `flutter analyze` on `nmtk/neuro_toolkit` when done.
- Delete the old two files once their contents are fully migrated; don't
  leave re-export shims.
- Follow CODING_STYLE_GUIDE.md for the new files' doc comments and naming.
```

---

## Prompt 2 — neurocnl notebook codegen cluster (confirmed cluster, 4 files, 7721 lines)

Verified: both test files `import` from `backend.app.routers.notebook`, and
`notebook.py` explicitly re-exports `dataset_cache` symbols with a comment
saying tests patch them through that re-export. Splitting the router without
touching the tests and the cache module in the same pass will break imports.

```
Refactor a tightly coupled cluster of oversized files in the neurocnl backend
into smaller, single-responsibility files. Read neurocnl's root AGENTS.md
and CODING_STYLE_GUIDE.md first. Work inside the neurocnl submodule.

Files (all in the same import cluster — do this as one pass):
- neurocnl/backend/app/routers/notebook.py (1341 lines)
- neurocnl/backend/tests/test_notebook_generate_v2.py (3685 lines)
- neurocnl/backend/tests/test_notebook_codegen.py (1544 lines)
- neurocnl/backend/app/services/dataset_cache.py (1155 lines)

Context: `notebook.py` re-exports schema and service symbols "for
compatibility" (see the `# noqa: F401 — re-exported` comments near the top of
the file) specifically so the two test files and `dataset_cache`'s internal
callers can import them from one place. Before moving anything, grep the
whole repo for `from backend.app.routers.notebook import` and
`from backend.app.services.dataset_cache import` to find every consumer —
not just the two test files already known — so nothing breaks silently.

Steps:
1. Read `notebook.py` fully and map its actual responsibilities (it's a
   FastAPI router — likely mixes route handlers, request/response shaping,
   and notebook-assembly/codegen logic in one file). Propose a split along
   those lines: keep route handlers thin in `notebook.py`, move codegen/
   assembly logic into a new `backend/app/services/notebook_assembly.py` (or
   similarly named module if one already exists — check first) with its own
   tests.
2. Read `dataset_cache.py` and determine why it's 1155 lines — likely
   caching logic plus dataset-artifact helpers that could split into
   `dataset_cache.py` (cache mechanics) and a separate artifacts/lookup
   module. Check `neurocnl/backend/app/services/dataset_catalog.py` (already
   imported by notebook.py) for overlap before inventing a new module name.
3. Split `test_notebook_generate_v2.py` and `test_notebook_codegen.py` by
   the same lines the production code splits along, so each test file
   exercises one production module. Extract any shared fixtures (there is
   likely a large fixture/setup section given the size) into a shared
   `tests/notebook_test_fixtures.py` or use an existing `conftest.py`.
4. Update every re-export in `notebook.py` to point at the new locations
   instead of deleting them outright, unless a full grep confirms nothing
   outside this cluster still imports from the old path — if something else
   does, keep a real re-export (not a duplicate implementation).

Constraints:
- No behavior changes; run `pytest neurocnl/backend/tests/test_notebook_generate_v2.py
  neurocnl/backend/tests/test_notebook_codegen.py` (adjust paths after the
  split) after every step and keep it green.
- Run `ruff check` and `mypy` (per neurocnl's CODING_STYLE_GUIDE.md strict
  typing rules) on all new/changed files.
- Don't leave dead re-export shims once you've confirmed nothing external
  depends on them.
```

---

## Prompt 3 — nmtk launcher_control test suite (confirmed cluster, 5 files, 7759 lines)

Verified: all five files import `from base import LauncherControlServiceTestBase`
(a shared test base class) and four of five also `import
nmtk.launcher_control.server as launcher_server` directly — same
integration-test pattern as the Flutter deployment test file in Prompt 1.

```
Refactor the nmtk launcher_control integration test suite. Read
nmtk/AGENTS.md and CODING_STYLE_GUIDE.md first.

Files (same shared-fixture cluster — do this as one pass):
- tests/launcher_control/test_launcher_deployment.py (2219 lines)
- tests/launcher_control/test_launcher_bundle_akida_provisioning.py (1822 lines)
- tests/launcher_control/test_launcher_hardware_settings.py (1492 lines)
- tests/launcher_control/test_launcher_lifecycle_doctor_cli.py (1152 lines)
- tests/launcher_control/test_launcher_pynq_provisioning.py (1074 lines)

Context: `tests/launcher_control/base.py` already holds
`LauncherControlServiceTestBase` and is imported by all five files — this is
the existing shared-fixture pattern to extend, not replace.

Steps:
1. Read `tests/launcher_control/base.py` first to see what it already
   provides (server bootstrap, temp dirs, mock overlay staging, etc.) versus
   what each of the 5 files re-implements locally — the per-file duplication
   is the likely source of bloat.
2. For each file, identify whether its size comes from (a) genuinely broad
   test coverage of one feature, or (b) repeated boilerplate that belongs in
   `base.py` or a new shared helper module
   (`tests/launcher_control/fixtures.py`). Move (b) into shared helpers first
   — this alone may bring several files under 1000 lines without any test
   getting split across files.
3. For files still over 1000 lines after deduplication, split by sub-feature
   within the same domain, e.g. `test_launcher_bundle_akida_provisioning.py`
   likely separates into bundle-staging tests vs. Akida-provisioning tests;
   `test_launcher_hardware_settings.py` likely separates by hardware type.
   Name new files so the split is obvious:
   `test_launcher_<domain>_<subarea>.py`.
4. Keep every file importing `LauncherControlServiceTestBase` from `base.py`
   — do not duplicate the base class.

Constraints:
- No behavior changes; run `pytest tests/launcher_control/` after each step
  and keep it green (these are integration tests that spin up
  `launcher_server` — expect them to be slower than unit tests).
- Run `ruff check` and `mypy` on all new/changed files.
- If two files turn out to test the exact same code path from different
  angles, note it in the PR description rather than silently merging or
  deleting either — that's a coverage decision, not a pure refactor.
```

---

## Prompt 4 — neurocnl nir_cnl front-end (same subsystem, not import-coupled, 2 files, 2183 lines)

Verified: no direct import between these two, but both sit in the CNL
parse→compile pipeline (the test targets `neurocnl.nir_cnl.compiler`, which
consumes `parser.py`'s output). Group for shared context, not because one
change forces the other.

```
Refactor two oversized files in neurocnl's CNL front-end. Read neurocnl's
AGENTS.md and CODING_STYLE_GUIDE.md first. These two files are not
import-coupled to each other, but both belong to the nir_cnl parse→compile
pipeline (compiler.py, already under 1000 lines, sits between them) — do
them in the same session so the split stays consistent with that pipeline's
existing module boundaries (diagnostics.py, errors.py, grammar_tables.py,
ir_types.py, token_cursor.py, tokenizer.py, validator.py already exist
alongside parser.py — check each for a natural home before creating new
files).

Files:
- neurocnl/neurocnl/nir_cnl/parser.py (1146 lines)
- neurocnl/neurocnl/tests/nir_native_cnl/test_compiler_weight_init.py (1037 lines)

Steps:
1. Read `parser.py` and classify its top-level functions/classes against the
   sibling modules already in `nir_cnl/` (tokenizer, grammar_tables,
   ir_types, validator, token_cursor, diagnostics, errors). If parser.py
   contains logic that duplicates or overlaps one of those, move it there
   instead of creating a new file. Only create a new module (e.g.
   `parser_directives.py` or similar, named for what's actually inside) for
   genuinely distinct logic that doesn't fit an existing sibling.
2. Read `test_compiler_weight_init.py` and check whether its size comes from
   one long parametrized suite (split by weight-init strategy under test) or
   several unrelated concerns bolted together (split by concern, one file
   per concern, prefixed `test_compiler_weight_init_<concern>.py`).

Constraints:
- No behavior changes; run
  `pytest neurocnl/neurocnl/tests/nir_native_cnl/` and the parser's own test
  suite after each step and keep it green.
- Run `ruff check` and `mypy` on all new/changed files.
```

---

## Prompt 5 — neurocnl NIR interop (independent, do as two separate small refactors)

Verified: these two have zero shared imports — one is about NIR↔external
simulator converters, the other about NIR↔canvas graph serialization for the
studio UI backend. They only look related because both touch "NIR". Do them
as two independent prompts, not one combined pass.

```
Refactor neurocnl/neurocnl/runtime/test_nir_support.py (1124 lines)
independently of any other file in this backlog. Read neurocnl's AGENTS.md
and CODING_STYLE_GUIDE.md first.

This file tests `neurocnl.runtime.nir_support` plus the converter classes
`Brian2IO`, `LavaIO`, `PyNNIO`, `SinabsIO`. Read it and split by converter
under test — one test file per simulator backend
(`test_nir_support_brian2.py`, `test_nir_support_lava.py`,
`test_nir_support_pynn.py`, `test_nir_support_sinabs.py`), plus a shared
`test_nir_support_shared.py` (or a fixtures module) for anything common to
all four (e.g. shared NIR graph builders via `make_nir_graph`).

No behavior changes; run the full file's test path before and after each
split and keep it green. Run `ruff check` and `mypy`.
```

```
Refactor neurocnl/backend/tests/test_nir_graph_serializer.py (1005 lines)
independently of any other file in this backlog. Read neurocnl's AGENTS.md
and CODING_STYLE_GUIDE.md first.

This file tests `backend.app.services.nir_graph_serializer` (NIR ↔ canvas
graph translation for the studio UI) using `neurocnl.runtime.cnl_nodes` node
types and `neurosim.contracts.design_contracts.CanvasGraph`. It's only 5 lines
over the threshold — first check whether it's actually one coherent test
suite that just happens to be verbose (in which case leave it alone, this is
the lowest-priority file in the whole backlog) or whether it has an obvious
seam (e.g. NIR-to-canvas vs. canvas-to-NIR direction) worth splitting on.

No behavior changes if you do split it; run its test path before and after
and keep it green.
```

---

## Prompt 6 — standalone files (no coupling found; refactor independently, lowest priority)

```
Each of the following files was checked for coupling with the rest of the
"files over 1000 lines" backlog and found to have none — refactor each
independently, in any order, whenever convenient:

1. neurocnl/neurocnl/planner.py (1038 lines) — read neurocnl's AGENTS.md
   and CODING_STYLE_GUIDE.md. This is IR/topology planning logic
   (imports neurocnl.ir, neurocnl.network_facts, neurocnl.backends). Split
   by planning phase if one exists (e.g. topology analysis vs.
   backend-capability matching vs. the public planner API) — read the file
   first to find the seam rather than guessing.

2. Neurochip/neurochip/app/services/akida_model_jobs.py (1212 lines) — read
   Neurochip's AGENTS.md and CODING_STYLE_GUIDE.md. Despite sharing a
   directory with PYNQ backend files, this has zero import overlap with
   test_pynq_backend.py — it's Akida-specific (job queue/model management,
   given the `threading`, `uuid`, `zipfile`, `zlib` imports). Read it and
   split by concern (e.g. job lifecycle/state machine vs. model artifact
   packaging/hashing) if a seam exists.

3. Neurochip/neurochip/tests/test_pynq_backend.py (1137 lines) — read
   Neurochip's AGENTS.md and CODING_STYLE_GUIDE.md. Tests `PYNQBackend`,
   `PynqSimulator`, `PynqState`, `pynq_worker`, `pynq_errors`,
   `pynq_overlay_assets`, and a runtime artifact contract — that's at least
   4-5 distinct collaborators under one test file. Split by collaborator,
   e.g. `test_pynq_backend_core.py`, `test_pynq_backend_worker.py`,
   `test_pynq_backend_simulator.py`, sharing common fixtures via
   `tests/conftest.py` or a small local fixtures module if one doesn't
   already exist.

4. nmtk/neuro_toolkit/lib/screens/backend_setup.dart (1492 lines) — read
   nmtk/AGENTS.md and CODING_STYLE_GUIDE.md. This is a Dart UI screen. It
   imports the `DeploymentService` interface (not the concrete
   `ClientDeploymentService` from Prompt 1), so it's in the same feature
   area as Prompt 1 but not force-coupled to it — do Prompt 1 first since UI
   screens tend to follow service-layer shape, but this can be its own PR.
   Read the file and split by widget/section (it's almost certainly one
   large `StatefulWidget`/build method with several logical steps —
   connection form, credential entry, progress display, health repair UI) —
   extract each step into its own widget file under
   `nmtk/neuro_toolkit/lib/screens/backend_setup/`, following whatever
   pattern nearby screens already use for step-widget extraction (check
   `nmtk/neuro_toolkit/lib/screens/` for precedent before inventing a new
   pattern).

Constraints for all four: no behavior changes, run the relevant test suite
(pytest for the Python files, `flutter test` for the Dart file, plus
`flutter analyze` / `ruff check` + `mypy`) before and after, and don't
extract anything speculative — if a file turns out to be one genuinely
cohesive concern that's just long, say so and leave it, rather than forcing
an arbitrary split.
```
