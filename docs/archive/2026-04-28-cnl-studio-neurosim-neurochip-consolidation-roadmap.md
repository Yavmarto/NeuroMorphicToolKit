# CNL Studio, NeuroSim, and Neurochip Consolidation Roadmap

**Date:** 2026-04-28  
**Scope:** `neurocnl`, `Neurosim`, `Neurochip`, launcher-facing handoff UX  
**Status:** Complete on 2026-04-28; roadmap converted into an execution tracker and closed the same day

## Progress Snapshot

Approximate completion against the roadmap: **100%**

What is already true in the repo:

- `neurocnl` already treats `Studio` as the primary handoff surface for `NeuroSim` and `Neurochip`.
- `neurocnl` has already demoted `Deploy` in copy to a secondary review surface rather than the primary export path.
- `Neurochip` already exposes the active hardware target in shell chrome and already has an explicit `Change Target` action.
- `Studio` launcher cards now use workflow-mode labels: `Open Visual Editor` and `Open Hardware Execution`.
- `Studio -> Neurochip` now emits a versioned `import_network_handoff` payload with target metadata and workspace intent.
- `Neurochip` now parses that payload, boots into the requested workspace, and shows imported-context summary UI.
- [docs/ADR-claude/0021-studio-neurochip-handoff-contract.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/ADR-claude/0021-studio-neurochip-handoff-contract.md) now defines the authoritative `Studio -> Neurochip` target and workspace contract.
- `nmtk/neuro_toolkit` now resolves `package:nmtk_module_contracts` again, so launcher Flutter tests compile against the shared handoff contract package.
- `nmtk/neuro_toolkit/test` now passes again after refreshing launcher package wiring.
- `nmtk/neuro_toolkit/integration_test/example_test.dart` now passes in this environment when run with an explicit macOS device under `arch -arm64`.
- `python3 scripts/launcher_control_service.py --doctor --json` now returns `fatalCount: 0` and `degradedCount: 0` after the launcher-side verification pass.
- `nmtk/launcher_control` now owns the PYNQ launch-command builder and the PYNQ/Akida provisioning bundle assembly logic used by the launcher, so launcher runtime no longer depends on importing or loading checked-out `Neurochip/neurochip/provisioning/*` helpers.
- `NeuroSim` no longer contains a live direct `Neurochip` launch path in the current frontend; the remaining import flow is now explicitly framed as `CNL Studio -> NeuroSim` preview/import behavior rather than a generic handoff.
- `Neurochip/frontend` now consumes typed `launcherRuntime` metadata end-to-end for PYNQ and Akida launcher-facing defaults, so embedded launcher forms no longer rely on ad hoc `xilinx`, port, or install-root fallback literals when manifest-owned metadata is present.
- Launcher-facing widget coverage now proves PYNQ pairing and Akida host registration render and persist manifest-owned runtime metadata rather than hard-coded Neurochip defaults.

What is not done yet:

- No roadmap work remains in this consolidation slice.

## Current Repo-State Assessment

### Landed behavior

- [neurocnl/frontend/lib/screens/studio_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/screens/studio_screen.dart) already centralizes the launcher handoff cards and target review tabs inside `Studio`.
- [neurocnl/frontend/lib/routing/app_router.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/routing/app_router.dart) already redirects the legacy `/deploy` entrypoint back into the `Studio` deploy workspace.
- [neurocnl/frontend/lib/screens/studio_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/screens/studio_screen.dart) already reframes launcher cards as workflow transitions via `Open Visual Editor` and `Open Hardware Execution`.
- [neurocnl/frontend/lib/services/neurochip_handoff.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/services/neurochip_handoff.dart) already emits a versioned `import_network_handoff` payload with `target_id`, `target_label`, `destination_workspace`, and `readiness_summary`.
- [Neurochip/frontend/lib/app.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/app.dart) already shows the active target in the shell header and exposes `Change Target`.
- [Neurochip/frontend/lib/services/import_network_payload.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/services/import_network_payload.dart) already parses the versioned handoff payload and still tolerates legacy `import_network`.
- [Neurochip/frontend/test/neurochip_shell_adapter_test.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/test/neurochip_shell_adapter_test.dart) already covers direct workspace boot from imported Studio handoff context.

### Still-open gaps

- [nmtk_module_contracts/lib/src/studio_neurochip_handoff_contract.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/nmtk_module_contracts/lib/src/studio_neurochip_handoff_contract.dart) now owns the shared typed `Studio target -> Neurochip target_id/label/workspace` contract consumed by both producer and consumer.
- [docs/ADR-claude/0022-remove-legacy-import-network-fallback.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/ADR-claude/0022-remove-legacy-import-network-fallback.md) now declares the legacy `import_network` sunset and records the removal trigger as satisfied on 2026-04-28.
- The launcher-side residual cleanup slice is complete: `tests/test_launcher_control_service.py` now passes without relying on host-installed `neurochip` package imports or optional NeuroChip runtime dependencies.
- No open execution gaps remain for this roadmap after the launcher-side `launcherRuntime` client propagation and test pass.

## Problem Statement

The current pipeline from CNL authoring to hardware deployment is functionally rich but UX-fragmented.

The main operator confusion is not that the modules exist. The confusion is that workflow ownership is duplicated:

- `CNL Studio` already exposes deploy readiness, target-specific checks, and launcher handoff actions.
- `Neurochip` asks the operator to choose deployment targets again after handoff.
- `NeuroSim` can hand off directly to `Neurochip`, creating a second deployment route that bypasses Studio.
- `neurocnl` still has both a primary Studio deploy/readiness surface and a separate `Deploy` route with overlapping concepts.

This makes the suite feel redundant in exactly the place where the user expects one clear path: author -> inspect -> choose target -> execute deployment.

## Source Basis

This roadmap is based on the current repo state in:

- [docs/architecture-consolidation-analysis.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/architecture-consolidation-analysis.md)
- [docs/cross-module-feature-overlap-analysis.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/cross-module-feature-overlap-analysis.md)
- [docs/implementation-plan-consolidation.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/implementation-plan-consolidation.md)
- [neurocnl/docs/USER_HAPPY_FLOW.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/docs/USER_HAPPY_FLOW.md)
- [neurocnl/frontend/lib/screens/studio_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/screens/studio_screen.dart)
- [neurocnl/frontend/lib/screens/deploy_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/screens/deploy_screen.dart)
- [NeuroSim/frontend/lib/screens/canvas_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/NeuroSim/frontend/lib/screens/canvas_screen.dart)
- [Neurochip/frontend/lib/app.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/app.dart)
- [Neurochip/frontend/lib/screens/target_gallery_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/screens/target_gallery_screen.dart)
- [Neurochip/frontend/lib/widgets/target_selector.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/widgets/target_selector.dart)

## Recommended Product Rule

Adopt one canonical rule for the suite:

**`CNL Studio` owns pipeline progression and deployment target selection.**

Under that rule:

- `NeuroSim` is a visual editing and topology inspection tool mode.
- `Neurochip` is a hardware execution, packaging, flashing, and diagnostics tool mode.
- `Studio` is the only place where the operator should normally decide "what target am I deploying to?"

This keeps the domain split healthy without keeping the UX split confusing.

## Target UX Model

The desired operator path should be:

1. Author or load a spec in `CNL Studio`.
2. Parse, validate, generate, and optionally simulate in `Studio`.
3. If needed, open `NeuroSim` for visual editing or topology inspection.
4. Return to `Studio` with the normalized spec or network.
5. Choose a deployment target once in `Studio`.
6. Open `Neurochip` only for target-specific execution steps.
7. In `Neurochip`, continue directly in the imported target context instead of starting over.

The operator should not have to re-answer:

- "Which target am I using?"
- "Am I still in simulation or deployment?"
- "Which module actually owns this step?"

## Non-Goals

This roadmap does not recommend:

- collapsing `NeuroSim` semantic ownership into `neurocnl`
- collapsing `Neurochip` hardware ownership into `neurocnl`
- deleting module boundaries before fixing workflow ownership
- keeping multiple equivalent routes for the same deployment action

## Core UX Decisions

### 1. Single target-selection owner

`Studio` becomes the only primary target-selection surface.

Implications:

- The current target tabs or equivalent target picker stay in `Studio`.
- `Neurochip` may still support target override, but only as an explicit secondary action such as `Change target`.
- Imported handoffs into `Neurochip` should default to the selected target and selected workspace.

### 2. Single deployment entrypoint

There should be one canonical route into hardware execution:

- `Studio -> Neurochip`

This means:

- remove `NeuroSim -> Neurochip` direct handoff as a first-class operator path
- do not maintain parallel deployment launch points with equal status

### 3. Studio owns pipeline state

`Studio` should be the only surface responsible for showing:

- spec readiness
- validation readiness
- generated-network readiness
- selected deployment target
- handoff eligibility

`Neurochip` should show execution state, not restate the full pipeline as if it owned it from the beginning.

### 4. NeuroSim is an editor, not a router

`NeuroSim` should be presented as:

- visual assembly
- topology inspection
- parameter tuning
- canvas-native simulation and sweeps

It should not be presented as an equally valid second place to start hardware deployment.

### 5. Neurochip is an executor, not a chooser

`Neurochip` should be presented as:

- hardware-specific analysis
- packaging
- runtime setup
- flashing
- deploy verification
- target diagnostics

It should not open by asking the user to make the same high-level target decision that was already made in `Studio`.

## Concrete Engineering Roadmap

## Phase 1: Lock the workflow contract

**Goal:** establish product truth before changing screens.

**Status:** Complete on 2026-04-28.

Current evidence:

- This roadmap now states the contract clearly.
- The deployed `neurocnl` copy already implies `Studio` is primary.
- ADR 0021 now defines the authoritative cross-module handoff contract and the three module docs link to it.

### Deliverables

- Add an ADR or dated decision doc that states:
  - `Studio` owns deployment target selection
  - `NeuroSim` does not directly launch hardware deployment as a primary path
  - `Neurochip` accepts imported target context as authoritative initial state
- Update module-facing docs that currently imply overlapping ownership.

### Acceptance criteria

- The rule appears in one authoritative design document.
- `neurocnl`, `Neurosim`, and `Neurochip` docs stop describing themselves as equivalent workflow owners for the same user decision.

### Remaining work

- No Phase 1 contract work remains.

## Phase 2: Remove the parallel deployment route

**Goal:** eliminate the most confusing branch first.

**Status:** Complete on 2026-04-28.

### Changes

- Remove or demote the direct `NeuroSim -> Neurochip` handoff action in [NeuroSim/frontend/lib/screens/canvas_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/NeuroSim/frontend/lib/screens/canvas_screen.dart).
- Keep `Studio -> NeuroSim` and `Studio -> Neurochip`.
- If a direct export from `NeuroSim` to `Neurochip` must remain for internal use, hide it from the primary operator flow and label it as an advanced shortcut.

### Why first

As long as both `Studio` and `NeuroSim` can independently launch hardware deployment, the suite has no unambiguous deployment owner.

### Acceptance criteria

- A normal operator can only start hardware deployment from `Studio`.
- `NeuroSim` no longer presents `Neurochip` handoff as a peer to its editor workflows.

### Remaining work

- No default operator-path work remains in `NeuroSim`.
- If a future expert shortcut is reintroduced, require explicit advanced labeling and keep it off the default canvas chrome.

## Phase 3: Make target choice single-source

**Goal:** fix the exact redundancy the user reported.

**Status:** Complete on 2026-04-28.

Current evidence:

- `Studio` already has target-specific tabs and a launcher handoff surface.
- `Neurochip` already has a visible active-target badge and `Change Target`.
- `Studio` now emits a versioned handoff payload with target id, destination workspace, and readiness summary metadata.
- `Neurochip` now bootstraps the imported target, opens the requested workspace, and shows a compact imported-context summary banner.
- Frontend tests now cover Studio handoffs opening the imported `Teensy`, `PYNQ`, and `Akida` workspaces directly.
- Neurochip payload-decoder tests now normalize all three Studio-owned targets through the shared contract, even when the incoming workspace or label is wrong.

### Changes in `Studio`

- Keep one target-selection surface in `Studio`.
- Store the selected target in explicit handoff state, not only implicit UI state.
- Include in the handoff payload:
  - imported network or spec
  - selected target id
  - intended destination workspace
  - target-specific readiness summary

### Changes in `Neurochip`

- Extend the import payload parser to accept selected target metadata via the versioned `import_network_handoff` contract.
- On successful handoff:
  - preselect the imported target
  - open the target-specific workspace directly
  - show a compact imported-context summary at the top of the screen
- Keep `Change target` as an explicit action, not as the default first task.

### Candidate impacted files

- [neurocnl/frontend/lib/services/neurochip_handoff.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/services/neurochip_handoff.dart)
- [neurocnl/frontend/lib/screens/studio_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/screens/studio_screen.dart)
- [Neurochip/frontend/lib/services/import_network_payload.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/services/import_network_payload.dart)
- [Neurochip/frontend/lib/app.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/Neurochip/frontend/lib/app.dart)
- `Neurochip` workspace controller and target provider surfaces

### Acceptance criteria

- If the user picks `Teensy` in `Studio`, `Neurochip` opens directly in the `Teensy` execution flow.
- If the user picks `PYNQ` in `Studio`, `Neurochip` opens directly in the `PYNQ` flow.
- If the user picks `Akida` in `Studio`, `Neurochip` opens directly in the `Akida` flow.
- The user is not asked to select a target again unless they intentionally click `Change target`.

### Remaining work

- No Phase 3 target-ownership work remains.

## Phase 4: Collapse duplicate deploy surfaces inside `neurocnl`

**Goal:** remove internal duplication before broader frontend merge work.

**Status:** Complete on 2026-04-28.

Current evidence:

- `Deploy` is already described as secondary.
- `Studio` already contains deploy readiness, launcher handoff, and target review content.
- The standalone `/deploy` route is already a compatibility redirect into `Studio`.
- `Studio` now persists the selected deploy target in workspace state and uses it as the single source for readiness, review-panel selection, and launcher handoff.

### Current problem

The remaining ambiguity was inside the `Studio` deploy panel itself:

- `Studio Flow` previously appeared as a peer target next to hardware targets
- the selected target lived only in local widget state instead of the shared Studio workspace state

That made Studio claim deployment authority while still modeling parts of deploy ownership as transient view state.

### Recommended direction

Choose one of these and make it explicit:

1. **Preferred:** fold all deployment readiness and target-specific checks into `Studio`, then retire the standalone `Deploy` route.
2. **Fallback:** keep the `Deploy` route, but strip `Studio` down to a single `Continue to Deploy` action and remove duplicate readiness cards and target tabs from `Studio`.

### Recommendation

Prefer option 1 because the repo already treats `Studio` as the primary path, and the separate deploy route currently reads as a secondary surface with overlapping authority.

### Candidate impacted files

- [neurocnl/frontend/lib/screens/studio_screen.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/screens/studio_screen.dart)
- [neurocnl/frontend/lib/routing/app_router.dart](/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/routing/app_router.dart)
- target deploy panels under `neurocnl/frontend/lib/widgets/`
- route definitions and shell navigation

### Acceptance criteria

- `neurocnl` has one obvious deployment surface, not two competing ones.
- The operator can describe the next step after validation without needing to choose between overlapping screens.

### Remaining work

- No Phase 4 deploy-authority work remains inside `neurocnl`.

## Phase 5: Reframe labels and navigation

**Goal:** make the module split feel like focused modes, not competing products.

**Status:** Complete on 2026-04-28.

### Changes

- Rename action labels in `Studio`:
  - `Open NeuroSim` -> `Open Visual Editor`
  - `Open Neurochip` -> `Open Hardware Execution`
- Add short helper text that says why the user would leave `Studio` for each mode.
- In launcher or shell surfaces, avoid generic wording like `Open Launcher` where the real action is workflow-specific.

### Acceptance criteria

- The UI language describes task transitions, not product hopping.
- Operators can infer why they are opening `NeuroSim` versus `Neurochip` without prior suite knowledge.

### Remaining work

- No Phase 5 workflow-label work remains.

## Phase 6: Normalize simulation terminology and finish stabilization

**Goal:** reduce semantic confusion around the word `simulation` and finish the remaining launcher/runtime stabilization work before any consolidation starts.

**Status:** Complete on 2026-04-28. Terminology cleanup and launcher/runtime stabilization are now closed, and Phase 7 is unblocked.

### Current ambiguity

The suite uses `simulation` to refer to several different things:

- `Studio` validation and generated-network execution preview
- `NeuroSim` visual preview and parameter sweep simulation
- `Neurochip` target-specific deployability or verification logic
- legacy prosthetic and MuJoCo flows in `neurocnl` deploy surfaces

### Recommended terminology split

- `Studio`: `spec simulation` or `execution preview`
- `NeuroSim`: `topology simulation` or `visual simulation`
- `Neurochip`: `hardware verification`, `runtime validation`, or `deploy check`

### Acceptance criteria

- The same operator action is not described as `simulation` in one module and `deployment` in another unless the distinction is intentional and documented.

### Current evidence

- `Studio` now uses `Preview`, `Run Preview`, `Preview Summary`, and `execution preview` language for the generated-network confidence check.
- `NeuroSim` now frames the preview surface as `Visual Simulation` and `visual simulation` rather than a generic simulation step.
- `Neurochip` now reports imported Studio readiness with `execution preview reviewed` rather than `simulation reviewed`.
- Launcher E2E tests now register a test `applicationDocuments` provider so launcher state loading does not emit `path_provider` plugin exceptions during guardrail verification.
- Akida control-plane fallback now emits one higher-level fallback log during expected remote-control API failover instead of duplicating the low-level transport error and fallback message in launcher verification output.
- Akida status-poll fallback is now covered by launcher-control tests so the single-summary logging behavior stays locked for both preflight and status refresh paths.
- PYNQ overlay-upload recovery no longer emits a second summary line for the same user-space restart failure chain, which keeps degraded recovery output actionable without duplicating the warning during guardrail verification.
- `python3 scripts/launcher_control_service.py --doctor --json` now returns `fatalCount: 0` and `degradedCount: 0` in the current Phase 6 verification baseline.
- `bash scripts/run_launcher_guardrails.sh` now passes cleanly in the current supported local environment.
- The explicit backend-smoke audit for this slice found no runnable manifest-defined backend start targets to exercise: current launcher doctor entries resolve to `No runnable backend configured` or `Module not installed`, so backend-smoke adds no further lifecycle signal for this Phase 6 closeout.

### Closeout scope
The Phase 6 stabilization slice is now closed with:

- launcher/runtime guardrail cleanup
- launcher and control-plane test reliability hardening
- cleanup of the remaining control-plane edge cases and environment-sensitive runtime paths that were still producing verification noise
- an explicit audit pass on launcher doctor, launcher guardrails, and backend-smoke expectations

### Stabilization acceptance criteria

- `python3 scripts/launcher_control_service.py --doctor --json` returns `fatalCount: 0` and does not regress structured degraded-capability reporting.
- `bash scripts/run_launcher_guardrails.sh` passes cleanly in the supported local environment.
- Remaining optional runtime failures are reported as structured degraded capability, not generic startup failure.
- Launcher and control-plane tests are reliable enough that the next phase does not begin with unresolved guardrail noise.

### Closeout verification
- `python3 scripts/launcher_control_service.py --doctor --json`
- `python3 -m unittest tests.test_launcher_control_service`
- `cd nmtk/neuro_toolkit && flutter test`
- `bash scripts/run_launcher_guardrails.sh`
- `python3 scripts/backend_endpoint_smoke.py health --module all`

### Remaining work

- Terminology cleanup is complete.
- Launcher/runtime stabilization is complete.
- Phase 7 may proceed when a runtime-consolidation slice is ready.

## Phase 7: Runtime consolidation after UX cleanup

**Goal:** make the app leaner only after workflow ownership is clear.

**Status:** In progress on 2026-04-28. Phase 6 stabilization is preserved; launcher-local runtime decoupling slices 7A through 7C are now complete inside `nmtk/launcher_control` and root launcher tests.

### Direction

After Phases 1 through 6, move toward:

- one suite frontend shell
- one primary suite backend
- `NeuroSim` and `Neurochip` preserved as internal feature areas or optional workers

This follows the recommendation already recorded in [docs/architecture-consolidation-analysis.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/architecture-consolidation-analysis.md).

### Why last

If runtime consolidation happens before workflow clarification, the same confusion will survive inside a single larger app.

### Acceptance criteria

- The canonical pipeline is already stable before any large frontend-shell merge starts.
- Consolidation work reduces technical duplication rather than relocating UX ambiguity.

## Recommended Implementation Order

1. Preserve the Phase 6 verification baseline while Phase 7 work begins.
2. Start runtime consolidation only in slices that keep doctor, guardrails, and launcher test coverage green.

### Completed slices: 7A-7C launcher-runtime decoupling

What landed:

- keep the Phase 6 launcher verification baseline green while reducing launcher runtime dependence on importing `Neurochip` package internals for the PYNQ control path
- validate staged PYNQ overlay artifacts directly in launcher control so missing or invalid overlay packages fail as structured preflight/degraded launcher behavior instead of import-path noise
- move the PYNQ user-space restart command builder into launcher-owned helper code instead of loading the checked-out `Neurochip` helper file at runtime
- move the PYNQ and Akida provisioning bundle assembly logic the launcher uses into launcher-owned helper code so runtime bundle creation no longer depends on checked-out `Neurochip/neurochip/provisioning/*` files

These slices were intentionally launcher-local. They do not change Studio ownership, module contracts, or the typed `Studio -> Neurochip` handoff payload.

## What To Remove, Keep, and Delay

### Remove

- direct primary deployment path from `NeuroSim` to `Neurochip`
- default target re-selection after Studio handoff
- duplicate deploy authority inside both `Studio` and `Deploy`
- ambiguous launcher wording that hides workflow intent

### Keep

- `Studio` as text-first and pipeline-first
- `NeuroSim` as the proper visual editor and topology tool
- `Neurochip` as the hardware packaging and execution specialist
- explicit advanced override paths for expert users

### Delay

- full frontend merge into a single executable shell
- deeper backend runtime collapse
- structural package moves across repos

These are worthwhile, but only after the operator workflow is made coherent.

## Risks and Mitigations

### Risk: over-constraining expert workflows

Removing direct alternate routes can frustrate advanced users.

**Mitigation:** keep expert shortcuts available behind explicit advanced actions, but do not surface them as peer primary flows.

### Risk: handoff payload drift across modules

Adding target context to handoff payloads creates another cross-module contract.

**Mitigation:** version the handoff payload, document it, and update both producer and consumer tests in the same change.

### Risk: temporary UI churn

While surfaces are being collapsed, users may see renamed routes and changed navigation.

**Mitigation:** do the work in small phases and keep one canonical path working at all times.

## Immediate Next Build Slice

The highest-leverage next slice is now consolidation above the stabilized launcher runtime boundary.

Launcher-local slices 7A through 7C are now complete:

1. Preserve the Phase 6 verification baseline with launcher doctor and launcher guardrails.
2. Decouple launcher PYNQ overlay inspection, restart-command generation, and runtime bundle creation from `Neurochip` package-import and file-path assumptions.
3. Keep the corresponding launcher-control tests in the same change so fallback logging and degraded-capability reporting remain explicit.
4. Stop if doctor, guardrails, or launcher runtime reporting regress.

Next slice: 7D launcher-manifest ownership cleanup.

1. Replace remaining launcher hard-coded Neurochip runtime defaults and provisioning metadata with manifest-owned or typed launcher-contract data where possible.
2. Keep launcher/control-plane verification in the same change so Phase 6 guarantees remain enforced.
3. Reuse the clarified `Studio -> Neurochip` ownership and typed handoff contracts as the boundary for consolidation work.
4. Re-run the same doctor, guardrail, and relevant module checks after the slice.

## Next Agent Handoff

Recommended write set for the next implementation agent:

- `nmtk/**`
- `scripts/**`
- `tests/**`
- any owning module files required by the selected Phase 7 consolidation slice

Recommended execution order:

1. Confirm the preserved Phase 6 baseline with launcher doctor and launcher guardrails before broadening the write set.
2. Implement one bounded Phase 7 consolidation change.
3. Update the corresponding tests, contracts, and structured reporting in the same change.
4. Stop if doctor, guardrails, or module ownership boundaries regress.

Verification the next agent should run for each Phase 7 slice:

- `python3 scripts/launcher_control_service.py --doctor --json`
- `bash scripts/run_launcher_guardrails.sh`
- `python3 scripts/backend_endpoint_smoke.py health --module all` when backend lifecycle behavior is touched
- owning module tests for any module-specific launcher/runtime fix
- if a suite-visible contract changes: `python3 -m pytest tests/integration/test_cross_module.py` and `python3 -m pytest tests/integration/test_teensy_e2e.py`

## Final Recommendation

The suite should become leaner by consolidating workflow ownership before consolidating code deployment boundaries.

The practical rule is simple:

**Pick the deployment target once in `CNL Studio`, then carry that context forward.**

That single change will do more to reduce confusion than merging repositories prematurely, and it creates a clean foundation for the broader one-app consolidation path later.
