# Client Deployment Service Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the 2353-line god-class `ClientDeploymentService` and its 2352-line test file into single-responsibility, constructor-injected collaborators, with zero behavior change.

**Architecture:** Extract four new collaborators (`DeploymentAssetBundle` loader, `RemoteServerProvisioner`, `RemoteDeploymentRunner`, `DeploymentHealthChecker`), fold local/k8s deploy logic into the existing `LocalDeploymentService`/`KubernetesDeploymentService`, and introduce one small `JobRegistry` that owns the shared mutable job/target/request state so the new collaborators and `ClientDeploymentService` can all read/write it without duplicating maps. Mirror the split in the test file: one shared-fakes file + five feature-scoped test files.

**Tech Stack:** Flutter/Dart, `flutter_test`, `dartssh2`, `http`.

**Spec:** User-provided task description (this session) — see "Original spec" quoted in full at the bottom of this file for traceability.

## Design decisions not covered by the original spec (review before executing)

The spec named ~40 methods to move but the actual file has more load-bearing pieces wedged between them. Defaults chosen below follow the existing codebase idiom (callback params, like `_bootstrapRemoteUser`'s `onPhase`/`onOperation`/`onTerminalOutput`) and YAGNI (no new class unless the maps genuinely need one home). Flag any of these you want changed before I start moving code:

1. **`JobRegistry` (new, small class in `client_deployment_service.dart`, not its own file):** owns `_jobs`, `_pendingTargets`, `_pendingRequests`, `_runningJobs`, `_operationHeartbeatTimers`, `_terminalPersistenceTimers`, `_persistence`/`_store`, and the glue methods `_updateJob`, `_persistCurrentJob`, `_emit`, `_setActiveOperation`, `_appendTerminalOutput`. Necessary because `RemoteServerProvisioner`, `RemoteDeploymentRunner`, and `DeploymentHealthChecker` all need to read/write the same job/target maps and call the same persistence — passing five maps as loose parameters into every collaborator method would be worse than one small owned-state object. `ClientDeploymentService` holds one `JobRegistry` field and delegates to it; it is not injected via constructor (it's pure internal state, not a swappable strategy like the SSH/local/k8s collaborators).
2. **`preflight`, `_deploy`, `_runDeployment`, `_failureSummaryForPhase`, `_failedPreflight`, `_portIsListed`, `_isDesktop`** (not named in the spec): these are pure dispatch/orchestration — they decide *which* collaborator to call (remote vs. local vs. k8s) but contain no domain logic themselves. They stay in `ClientDeploymentService` as orchestration glue, consistent with the spec's "thin orchestrator" framing.
3. **`_connect`** (thin 2-line wrapper around `_ssh.connect(request:, persistence:)`): not extracted into a shared helper class. Each new collaborator that needs it (`RemoteServerProvisioner`, `RemoteDeploymentRunner`, `DeploymentHealthChecker`) takes `SshDeploymentService ssh` as a constructor param (same DI pattern as `ClientDeploymentService` itself) and calls `ssh.connect(...)` directly. A dedicated class for a one-line wrapper is unwarranted.
4. **`_loadDeploymentBundle` and `_exactAssetBytes`:** fold into `deployment_asset_bundle.dart` as `DeploymentAssetBundle.load(AssetBundle assets)` (static factory, replaces the `_assets` field read with a parameter) and a `bytesFor(String fileName)` instance method (replaces the standalone byte-slicing helper with an encapsulated accessor other collaborators call instead of reaching for raw bytes themselves).
5. **`_updateSelectedAkidaRuntime`, `_waitForResponse`, `_startAndVerifyNeuroStudio`, `_shortHash`:** fold into whichever new file owns their only caller (`_verifyRemoteApis` → `deployment_health_checker.dart`; `_shortHash` → `remote_deployment_runner.dart`, its only caller `_startRemoteDeployment`'s new home).
6. **Test file `remote_deploy` bucket is empty in the current suite** (0 of 51 tests exercise SSH upload/execute against an already-known target — `_BlockingSshDeploymentService` only ever blocks the connection, never completes it). Per "every existing test must still exist... only moved/regrouped" I will **not** invent new tests to populate `client_deployment_service_remote_deploy_test.dart`. The file will not be created; this is called out as a pre-existing coverage gap, not fixed here (out of scope — flagging per your standing instruction to surface out-of-scope fixes rather than silently doing or skipping them).
7. **Job persistence/redaction gets its own 5th test file**, `client_deployment_service_persistence_test.dart` (spec's bullet 1 lists this as a 5th category; bullet 2's example filenames only showed 4 — the two bullets are consistent once you count categories, not just the examples given).
8. Test count is **51**, not 50 as stated in the task (verified by grep) — cosmetic, doesn't change the plan.

## Global Constraints

- No behavior changes. Every existing test keeps its exact current assertions — only file location and grouping change.
- Run `flutter test nmtk/neuro_toolkit/test/services/` (from `nmtk/neuro_toolkit`) after each extraction task and keep it green before moving to the next task.
- Run `flutter analyze` on `nmtk/neuro_toolkit` after the final task.
- Do not use `part`/`part of`. Do not split a single class's body across files.
- Delete `client_deployment_service_test.dart` and replace `client_deployment_service.dart`'s contents in place (same filename stays, now much shorter) once migration is complete — no re-export shims.
- Follow `CODING_STYLE_GUIDE.md` for new files' doc comments and naming.
- Because this is a verbatim-move refactor (not new logic), tasks below reference exact current line ranges as the source of truth instead of reproducing thousands of lines of existing code inline — re-read the live file at execution time since line numbers shift after each move.

---

### Task 0: Read style guides

**Files:** Read only — `nmtk/AGENTS.md`, `CODING_STYLE_GUIDE.md` (repo root).

- [ ] **Step 1:** Read `nmtk/AGENTS.md` and `CODING_STYLE_GUIDE.md` in full before writing any new file, per the task's own initialization instruction. Note doc-comment style, naming conventions, and import ordering conventions to apply to every new file below.

---

### Task 1: Extract `DeploymentAssetBundle` into its own file

**Files:**
- Create: `nmtk/neuro_toolkit/lib/services/deployment/deployment_asset_bundle.dart`
- Modify: `nmtk/neuro_toolkit/lib/services/deployment/client_deployment_service.dart` (remove moved code, add import, replace call sites)

**Interfaces:**
- Produces: `class DeploymentAssetBundle` (moved verbatim, current lines ~31-111) with two additions:
  - `static Future<DeploymentAssetBundle> load(AssetBundle assets)` — moved from `ClientDeploymentService._loadDeploymentBundle` (current lines ~1684-1735), signature changed to take `assets` as a parameter instead of reading `_assets`; carries the manifest-loading/integrity-check logic and the `_assetFiles`/`_releaseImageTag`/`_bundleIntegrityRecovery` constants (current lines ~139-156) that only this logic uses.
  - `List<int> bytesFor(String fileName)` — instance method replacing the standalone `_exactAssetBytes` helper (current lines ~1737-1738); encapsulates byte-slicing so callers in `remote_deployment_runner.dart` and `LocalDeploymentService` never touch raw `ByteData` offsets themselves.
  - `class _DeploymentBundleIntegrityException` (moved verbatim, current lines ~25-29) — stays file-private to `deployment_asset_bundle.dart`.

- [ ] **Step 1:** Read the current file to confirm exact line ranges for `_DeploymentBundleIntegrityException`, `DeploymentAssetBundle`, `_loadDeploymentBundle`, `_exactAssetBytes`, and the four related static consts (`_assetFiles`, `_releaseImageTag`, `_bundleIntegrityRecovery`) — line numbers from research may have drifted.
- [ ] **Step 2:** Create `deployment_asset_bundle.dart` with the moved classes/consts plus the two new methods described above. Add only the imports it actually needs (`dart:convert`, `dart:typed_data`, `package:crypto/crypto.dart`, `package:flutter/services.dart` for `AssetBundle`, `path` if used for file joins).
- [ ] **Step 3:** In `client_deployment_service.dart`, delete the moved code, add `import 'deployment_asset_bundle.dart';`, and replace every call site of `_loadDeploymentBundle(...)` with `DeploymentAssetBundle.load(_assets)` and every raw-byte-slice call with `bundle.bytesFor(fileName)`. Call sites to update: `setupRemoteServer`, `_deploy`, `repairTarget`, `_uploadAssets`, `_uploadAssetsForRepair`, `_materializeAssets`.
- [ ] **Step 4:** Run `flutter test nmtk/neuro_toolkit/test/services/` from `nmtk/neuro_toolkit`. Fix any compile errors (likely: missing import, a helper that turns out to need a field this move didn't carry over).
- [ ] **Step 5:** Confirm all tests pass, especially bundle-related tests (#37, #38, #41, #42 — corrupted/omitted/unexpected manifest, offset `ByteData`, checksum verify/report).

---

### Task 2: Introduce `JobRegistry` inside `client_deployment_service.dart`

Do this before extracting the remote/health collaborators, since they all depend on it.

**Files:**
- Modify: `nmtk/neuro_toolkit/lib/services/deployment/client_deployment_service.dart`

**Interfaces:**
- Produces: `class JobRegistry` (private-to-package is fine, but keep it in the same file as `ClientDeploymentService` since it's internal state, not a swappable collaborator) with:
  - Fields (moved from `ClientDeploymentService`, current lines ~168-179): `_jobs`, `_runningJobs`, `_pendingTargets`, `_pendingRequests`, `_operationHeartbeatTimers`, `_terminalPersistenceTimers`, `_persistence`, plus the `DeploymentPersistenceFactory` it was constructed with.
  - `Future<DeploymentPersistence> get store` (moved `_store` getter, current lines ~178-179).
  - `Future<DeploymentJob> updateJob(DeploymentJob job)` (moved `_updateJob`, current lines ~2316-2327).
  - `Future<void> persistCurrentJob(String jobId)` (moved `_persistCurrentJob`, current lines ~2329-2334).
  - `Future<void> emit(DeploymentJob original, DeploymentPhase phase, double percent, String label)` (moved `_emit`, current lines ~2239-2257).
  - `Future<void> setActiveOperation(String jobId, DeploymentActiveOperation? operation)` (moved `_setActiveOperation`, current lines ~2282-2314).
  - `Future<void> appendTerminalOutput(String jobId, String line)` (moved `_appendTerminalOutput`, current lines ~2259-2280).
  - Read accessors for the maps (`jobs`, `pendingTargets`, `pendingRequests`, `runningJobs`) so `ClientDeploymentService`'s remaining methods (`load`, `fetchJob`, `cancelJob`, `retryJob`, `retryJupyter`, `reinstallTarget`, `forgetHostKey`, `linkExistingTarget`) can keep reading/writing them through the registry instead of directly.

- [ ] **Step 1:** Add the `JobRegistry` class in the same file, moving the listed fields/methods into it verbatim (adjusting `this._jobs` etc. references to the registry's own fields).
- [ ] **Step 2:** Give `ClientDeploymentService` a single `final JobRegistry _registry` field, constructed in its constructor from the existing `assets`/`persistenceFactory` params. Replace every direct reference to the moved fields/methods inside `ClientDeploymentService`'s remaining methods with `_registry.jobs`, `_registry.updateJob(...)`, etc.
- [ ] **Step 3:** Run `flutter test nmtk/neuro_toolkit/test/services/`. This step is pure internal refactor (no new files yet) — every test must still pass unchanged.
- [ ] **Step 4:** Fix any missed call site until green.

---

### Task 3: Extract `RemoteServerProvisioner`

**Files:**
- Create: `nmtk/neuro_toolkit/lib/services/deployment/remote_server_provisioner.dart`
- Modify: `client_deployment_service.dart`

**Interfaces:**
- Consumes: `JobRegistry` (from Task 2), `SshDeploymentService` (existing), `DeploymentAssetBundle` (from Task 1), `AdministratorSessionManager` (existing, constructed here — currently a field of `ClientDeploymentService`; move ownership to this class since only bootstrap methods use it).
- Produces: `class RemoteServerProvisioner` with constructor `RemoteServerProvisioner({SshDeploymentService ssh = const SshDeploymentService(), AdministratorSessionManager? adminSessions})`, and methods (moved verbatim from current lines, adjusting field references to constructor params / `JobRegistry` params passed per-call):
  - `Future<DeploymentJob> setupRemoteServer(RemoteServerSetupRequest request, {required JobRegistry registry, required DeploymentAssetBundle Function() loadBundle})` (moved `setupRemoteServer`, ~405-468)
  - `Future<RemoteUserBootstrapResult> bootstrapRemoteUser({...same params...})` (moved `bootstrapRemoteUser` ~384-402, delegates to `_bootstrapRemoteUser`)
  - `Future<void> _runRemoteSetup(...)` (moved ~470-562)
  - `Future<DeploymentFailureDetails> _remoteSetupFailureDetails(...)` (moved ~564-617) — note this calls `_isApiReady`, which lives in the health checker (Task 5). Take `Future<bool> Function(DeploymentTarget) isApiReady` as a constructor or method param to avoid a circular file dependency.
  - `Future<RemoteUserBootstrapResult> _bootstrapRemoteUser(...)` (moved ~619-691)
  - `static String? canonicalIpv4(String value)` (moved `_canonicalIpv4` ~693-704, made public since `ClientDeploymentService` no longer has a private method of the same name to call)
- CDS keeps thin `@override` delegates: `setupRemoteServer` and `bootstrapRemoteUser` become one-liners calling `_provisioner.setupRemoteServer(...)` / `_provisioner.bootstrapRemoteUser(...)`.

- [ ] **Step 1:** Re-read the live file for exact current line numbers (they will have shifted after Tasks 1-2).
- [ ] **Step 2:** Create `remote_server_provisioner.dart`, moving the six methods above verbatim, threading `JobRegistry` and the `isApiReady` callback through as parameters where the original code called `_jobs`/`_pendingTargets`/`_store`/`_isApiReady` directly.
- [ ] **Step 3:** Add `RemoteServerProvisioner remote = const RemoteServerProvisioner()` — wait, this class holds `AdministratorSessionManager` state, so it cannot be `const`; use a non-const default `RemoteServerProvisioner()` — to `ClientDeploymentService`'s constructor params, store as `_provisioner`, wire in the thin delegating overrides.
- [ ] **Step 4:** Run `flutter test nmtk/neuro_toolkit/test/services/`. Fix compile/behavior breaks.
- [ ] **Step 5:** Confirm bootstrap-heavy tests pass (the ~32-33 tests in the "bootstrap" bucket from the research map, plus #36).

---

### Task 4: Extract `RemoteDeploymentRunner`

**Files:**
- Create: `nmtk/neuro_toolkit/lib/services/deployment/remote_deployment_runner.dart`
- Modify: `client_deployment_service.dart`

**Interfaces:**
- Consumes: `SshDeploymentService`, `JobRegistry`, `DeploymentAssetBundle`.
- Produces: `class RemoteDeploymentRunner` with constructor `RemoteDeploymentRunner({SshDeploymentService ssh = const SshDeploymentService()})` and methods moved verbatim (adjust field refs to params): `_startRemoteDeployment` (~1267-1355, becomes e.g. `startRemoteDeployment`), `_pollRemoteJob` (~1357-1438, → `pollRemoteJob`), `_ensureRemoteEngine` (~1534-1589), `_remoteDeployDir` (~1591-1611, → `remoteDeployDir`, also used by `cancelJob`/`retryJupyter`/`repairTarget` in CDS — expose as public), `_uploadAssets` (~1613-1676), `_verifyRemoteAssets` (~1740-1768), `_uploadAssetsForRepair` (~1149-1178, → `uploadAssetsForRepair`, also called from `repairTarget`), `_runChecked` (~2122-2144, → `runChecked`, also called from `repairTarget`/`retryJupyter`), `_runRemoteCommand` (~2146-2212), plus `_shortHash` (~1770-1771) and `_connect` usage inlined as `ssh.connect(request: request, persistence: persistence)`.

- [ ] **Step 1:** Re-read the live file for current line numbers.
- [ ] **Step 2:** Create `remote_deployment_runner.dart` with the methods above, making `remoteDeployDir`, `uploadAssetsForRepair`, and `runChecked` public (non-underscore) since `ClientDeploymentService.repairTarget`/`retryJupyter`/`cancelJob` call them too.
- [ ] **Step 3:** Add `RemoteDeploymentRunner runner = const RemoteDeploymentRunner()` to `ClientDeploymentService`'s constructor, store as `_runner`. Update every call site (`_runDeployment`'s remote branch, `_pollRemoteJob` callers in `fetchJob`, `cancelJob`, `retryJupyter`, `repairTarget`) to call `_runner.xxx(...)`.
- [ ] **Step 4:** Run `flutter test nmtk/neuro_toolkit/test/services/`.
- [ ] **Step 5:** Fix breakage. No dedicated existing tests target this collaborator directly (see design decision #6) — verify indirectly via whichever tests exercise `fetchJob`/`cancelJob`/`repairTarget`/`retryJupyter`.

---

### Task 5: Extract `DeploymentHealthChecker`

**Files:**
- Create: `nmtk/neuro_toolkit/lib/services/deployment/deployment_health_checker.dart`
- Modify: `client_deployment_service.dart`

**Interfaces:**
- Consumes: `http.Client`, `JobRegistry`, `RemoteDeploymentRunner` (for `repairTarget`'s remote-repair path — takes it as a constructor/method param, not a new SSH client).
- Produces: `class DeploymentHealthChecker` with constructor `DeploymentHealthChecker({http.Client? httpClient})` and methods moved verbatim: `diagnoseTarget` (~946-953), `diagnoseHost` (~955-1098), `repairTarget` (~1100-1147), `_waitForHealth` (~2031-2033), `_isApiReady` (~2023-2029, → `isApiReady`, made public since `RemoteServerProvisioner._remoteSetupFailureDetails` needs it per Task 3's callback param), `_verifyRemoteApis` (~1786-1880, → `verifyRemoteApis`, also called from `load`, `_runLocalDeployment`), `_clientReachabilityFailure` (~2096-2120, → `clientReachabilityFailure`, also called from `load`), `_updateSelectedAkidaRuntime` (~1882-2021), `_waitForResponse` (~2035-2053), `_startAndVerifyNeuroStudio` (~2055-2094).

- [ ] **Step 1:** Re-read the live file for current line numbers.
- [ ] **Step 2:** Create `deployment_health_checker.dart` with the methods above, making `isApiReady`, `verifyRemoteApis`, `clientReachabilityFailure` public.
- [ ] **Step 3:** Add `DeploymentHealthChecker health = const DeploymentHealthChecker()` — again not `const`-constructible if it holds an `http.Client`; use non-const default — to `ClientDeploymentService`'s constructor, store as `_health`. Wire `_provisioner` (Task 3) with `isApiReady: _health.isApiReady` via whatever param shape Task 3 settled on. Replace `ClientDeploymentService.diagnoseTarget`/`diagnoseHost`/`repairTarget` with thin delegates to `_health`. Update `load` and `_runLocalDeployment` to call `_health.verifyRemoteApis`/`_health.clientReachabilityFailure`.
- [ ] **Step 4:** Run `flutter test nmtk/neuro_toolkit/test/services/`.
- [ ] **Step 5:** Confirm health-bucket tests pass (#45, #46, #47, #48, #49, #50).

---

### Task 6: Fold local/k8s deploy logic into existing collaborators

**Files:**
- Modify: `nmtk/neuro_toolkit/lib/services/deployment/local_deployment_service.dart`
- Modify: `nmtk/neuro_toolkit/lib/services/deployment/kubernetes_deployment.dart`
- Modify: `client_deployment_service.dart`

**Interfaces:**
- `LocalDeploymentService` gains: `_runLocalDeployment` (~1440-1496, → e.g. `deploy(DeploymentRequest request, {required DeploymentAssetBundle Function() loadBundle, required Future<bool> Function(DeploymentTarget) verifyHealth, ...})`), `_materializeAssets` (~1773-1784, → `materializeAssets`, needs `AssetBundle`/`DeploymentAssetBundle` injected — give `LocalDeploymentService` an optional `AssetBundle? assets` constructor param), `_runLocalChecked` (~2214-2237, → `runChecked`). Existing `run(...)` primitive stays as the low-level exec method these call into.
- `KubernetesDeploymentService` gains: `_runKubernetesDeployment` (~1498-1528) folded into its existing `deploy(...)` call path, or kept as a thin wrapper `deployAndPersist(DeploymentRequest request, {required KubernetesProgress onProgress, required Future<void> Function(DeploymentTarget) saveTarget})` if the target-persistence write can't cleanly move (it currently does `(await _store).saveTarget(...)` — pass a `saveTarget` callback rather than injecting `DeploymentPersistence` directly, keeping this collaborator free of persistence-layer knowledge beyond what it's handed).

- [ ] **Step 1:** Re-read the live file for current line numbers of `_runLocalDeployment`, `_runKubernetesDeployment`, `_materializeAssets`, `_runLocalChecked`, and re-read `local_deployment_service.dart`/`kubernetes_deployment.dart` in full.
- [ ] **Step 2:** Move the four methods' logic into the two existing files per the interfaces above, adjusting field references (`_jobs`, `_registry.emit`, `_health.verifyRemoteApis`, `_kubernetes` no longer self-referential) to parameters.
- [ ] **Step 3:** Update `client_deployment_service.dart`'s `_runDeployment` dispatcher to call `_local.deploy(...)` / `_kubernetes.deployAndPersist(...)` instead of the removed private methods. Delete the four now-empty method bodies from `client_deployment_service.dart`.
- [ ] **Step 4:** Run `flutter test nmtk/neuro_toolkit/test/services/`.
- [ ] **Step 5:** Also run the local/k8s deployment service's own existing test files if any exist (`grep -rl LocalDeploymentService nmtk/neuro_toolkit/test/` / same for `KubernetesDeploymentService`) to make sure folding didn't break their direct unit tests.

---

### Task 7: Slim `ClientDeploymentService` down and verify full public surface

**Files:**
- Modify: `client_deployment_service.dart`

- [ ] **Step 1:** Confirm the file now contains only: constructor + fields (`_assets`, `_httpClient` if still needed, `_kubernetes`, `_ssh`, `_local`, `_provisioner`, `_runner`, `_health`, `_registry`), `load`, `preflight`, `deploy`/`_deploy`/`_runDeployment`/`_failureSummaryForPhase`, `linkExistingTarget`, `fetchJob`, `cancelJob`, `retryJob`, `retryJupyter`, `reinstallTarget`, `forgetHostKey`, thin delegating overrides for `setupRemoteServer`/`bootstrapRemoteUser`/`diagnoseTarget`/`diagnoseHost`/`repairTarget`, `_failedPreflight`, `_portIsListed`, `_isDesktop`, `_newId`, `_newAdminToken`, and the `JobRegistry` class from Task 2.
- [ ] **Step 2:** Run `flutter test nmtk/neuro_toolkit/test/services/` — full green run, all 51 original tests (still in the old single test file at this point).
- [ ] **Step 3:** Run `flutter analyze` on `nmtk/neuro_toolkit`. Fix any new lint warnings (unused imports, missing doc comments per `CODING_STYLE_GUIDE.md`) introduced by the split.

---

### Task 8: Create the shared test fakes file

**Files:**
- Create: `nmtk/neuro_toolkit/test/services/deployment/client_deployment_test_fakes.dart`

- [ ] **Step 1:** Move `_MemorySecretStorage` (current lines ~19-34), `_ManifestAssetBundle` (~36-106), `_BlockingSshDeploymentService` (~108-118) into the new file verbatim, with whatever imports they need (`dart:async`, `dart:convert`, `dart:typed_data`, `package:crypto/crypto.dart`, `package:flutter/services.dart`, `package:flutter_test/flutter_test.dart`, `package:dartssh2/dartssh2.dart`, project imports for `DeploymentPersistence`/`SshDeploymentService`/model types).
- [ ] **Step 2:** Since these classes are currently private (leading underscore) but need to be imported by five other test files, remove the leading underscore: rename to `MemorySecretStorage`, `ManifestAssetBundle`, `BlockingSshDeploymentService`.
- [ ] **Step 3:** In the still-intact `client_deployment_service_test.dart`, replace the three class definitions with `import 'deployment/client_deployment_test_fakes.dart';` and rename every use site (`_MemorySecretStorage` → `MemorySecretStorage`, etc.) so the existing file still compiles and passes as a sanity check before the bigger split.
- [ ] **Step 4:** Run `flutter test nmtk/neuro_toolkit/test/services/client_deployment_service_test.dart`. Must still pass, unchanged assertions.

---

### Task 9: Split the test file into bootstrap / bundle / health / persistence files

**Files:**
- Create: `nmtk/neuro_toolkit/test/services/client_deployment_service_bootstrap_test.dart`
- Create: `nmtk/neuro_toolkit/test/services/client_deployment_service_bundle_test.dart`
- Create: `nmtk/neuro_toolkit/test/services/client_deployment_service_health_test.dart`
- Create: `nmtk/neuro_toolkit/test/services/client_deployment_service_persistence_test.dart`
- Delete: `nmtk/neuro_toolkit/test/services/client_deployment_service_test.dart`

Test-to-file mapping (test descriptions verbatim, from the research map — move each `test(...)` block unmodified, only regrouped):

- **bootstrap** (34 tests: #1-#34 in file order): all account-reconciliation, rootless-Podman-reconciliation, credential-generation, transcript-drain/watchdog, and Podman-API-fallback tests, plus script-text assertions and transcript/marker parsers, plus #36 ("remote setup creates a persisted job before SSH bootstrap completes"). Also move the shared helper functions `_writeExecutable`, `_runRootlessReconciliationFixture`, `_runDeploymentAccountFixture`, `_runDeploymentCredentialFixture`, `_runPodmanApiProvisioningFixture` into this file since only bootstrap tests use them.
- **bundle** (4 tests): #37 ("deployment bundle accepts exact slices from offset asset data"), #38 ("invalid deployment bundles fail before persistence or SSH setup"), #41 ("deployment bundle verifies every uploaded asset checksum"), #42 ("deployment bundle reports unreadable checksum output separately").
- **health** (6 tests): #45, #46, #47, #48, #49, #50. Move the shared helper `_completedRemotePersistence` into this file.
- **persistence** (5 tests): #33 ("a progress heartbeat does not look like real progress"), #35 ("deployment failure details survive job persistence JSON"), #43 ("redacts every credential type from deployment logs"), #44 ("saving a remote target replaces older records for the same IP"), #51 ("relinking SSH credentials preserves an existing admin token").

- [ ] **Step 1:** Create `client_deployment_service_bootstrap_test.dart`: copy the 34 listed tests plus their 5 shared helper functions verbatim (byte-for-byte test bodies) from the current file, add `import 'deployment/client_deployment_test_fakes.dart';` plus whatever other imports those specific tests use.
- [ ] **Step 2:** Create `client_deployment_service_bundle_test.dart` with its 4 tests, same import pattern.
- [ ] **Step 3:** Create `client_deployment_service_health_test.dart` with its 6 tests plus `_completedRemotePersistence`.
- [ ] **Step 4:** Create `client_deployment_service_persistence_test.dart` with its 5 tests.
- [ ] **Step 5:** Verify 34 + 4 + 6 + 5 = 49, plus... **recount check:** the research map lists 51 total tests but the bucket counts above (34+4+6+5=49) are short by 2 — re-verify against the live file during execution: confirm whether #33 doubling (listed in both a bootstrap footnote and persistence) and #46 (listed with a "recommend health" caveat) account for the gap, and place each in exactly one file. Do not proceed to Step 6 until every one of the 51 `test(...)` blocks in the original file has been assigned to exactly one new file — grep-count `test(` across all four new files and confirm it equals 51.
- [ ] **Step 6:** Delete `client_deployment_service_test.dart`.
- [ ] **Step 7:** Run `flutter test nmtk/neuro_toolkit/test/services/`. All 51 tests must pass across the four new files (plus whatever else already lived in that directory).

---

### Task 10: Final verification and cleanup

- [ ] **Step 1:** Run `flutter test nmtk/neuro_toolkit/test/` (full test suite, not just `services/`) from `nmtk/neuro_toolkit` to catch any other file that imported the old private fakes or relied on `client_deployment_service_test.dart` existing.
- [ ] **Step 2:** Run `flutter analyze` on `nmtk/neuro_toolkit`. Zero new warnings.
- [ ] **Step 3:** `grep -rn "_loadDeploymentBundle\|_exactAssetBytes\|_runLocalDeployment\|_runKubernetesDeployment" nmtk/neuro_toolkit/lib` to confirm no dangling references to removed private methods.
- [ ] **Step 4:** Confirm no temporary/scratch files were left behind (this plan file itself stays, per the task-management convention of keeping dated task records — but check `current tasks/2026-09-04/` doesn't need a duplicate copy per repo convention).
- [ ] **Step 5:** Report line counts of the new files (`wc -l` on each) to confirm none of them are themselves oversized god-files.

---

## Original spec (for traceability)

The full original task description is preserved in the conversation that produced this plan; key constraints repeated here for the executor's convenience:

- No `part`/`part of` files; no splitting a single class's body across files.
- Every existing test must still exist and pass, unmodified in assertions (only moved/regrouped).
- Run `flutter test nmtk/neuro_toolkit/test/services/` after each extraction step.
- Run `flutter analyze` on `nmtk/neuro_toolkit` when done.
- Delete the old two files once their contents are fully migrated; don't leave re-export shims.
- Follow `CODING_STYLE_GUIDE.md` for the new files' doc comments and naming.
