# Suite Consolidation Roadmap

**Date:** 2026-04-29  
**Scope:** `nmtk`, `Neurohub`, `neurocnl`, `Neurochip`, `Neurosim`, `Neurosense`, `Neuro-Dream-Hand`  
**Status:** Proposed execution roadmap

## Progress Snapshot

Approximate completion against this roadmap: **20%**

What is already true in the repo:

- The 2026-04-28 consolidation pass established `Studio` as the canonical `neurocnl` workflow surface for `NeuroSim` and `Neurochip`.
- The launcher manifest in `nmtk` still describes `NeuroHub` as a suite dashboard and project orchestrator.
- `NeuroHub` documentation still describes the module primarily as a registry and metadata layer rather than the suite control plane.
- `neurocnl` still exposes sibling `Hardware` and `Analysis` routes that own operator decisions adjacent to `Studio`.
- `Neurochip` still repeats target choice across shell workspace state, target dropdowns, comparison flows, and gallery overrides.
- `NeuroSim` still contains a local regex-based CNL interpretation path.
- `NeuroSense` and `Neuro-Dream-Hand` still describe overlapping ownership around EMG ingestion, encoding, and hardware-in-the-loop preparation.
- `nmtk` manifest copy now describes `NeuroHub` as `Project registry and workflow metadata` rather than a suite orchestrator.
- `NeuroHub` spec, README, and shell copy now align around registry plus metadata ownership, and its project-focus chrome no longer presents itself as suite workspace control.
- [docs/ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md](/Users/yoshimartodihardjo/NeuroMorphicToolKit/docs/ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md) now records that `nmtk` is the sole suite control plane.

What is not done yet:

- The suite still lacks one unambiguous owner for launcher orchestration versus registry metadata.
- The remaining module boundaries still ask the operator to make the same decision in more than one place.
- Duplicate semantic ownership and duplicate biosignal ownership have not yet been reduced to single-source contracts.
- `neurocnl` still exposes `Studio`, `Hardware`, and `Analysis` as peer shell destinations in `frontend/lib/routing/app_router.dart`.
- `Hardware` still owns serial connectivity and live telemetry as a routed screen instead of a subordinate workflow surface.
- `Analysis` still owns energy, quantization, and fault-injection review as a peer top-level screen instead of a `Studio` workflow panel.

## Problem Statement

The remaining consolidation work is no longer about whether the modules should exist. It is about whether one user decision has one owner.

The current suite still has four kinds of duplicated authority:

- `nmtk` and `NeuroHub` both present themselves close to orchestration surfaces.
- `Studio` in `neurocnl` owns the workflow in principle, but sibling routes still own nearby hardware and analysis decisions in practice.
- `Neurochip` still lets target selection reappear as a first-class choice after the upstream workflow already picked a target.
- `NeuroSim`, `NeuroSense`, and `Neuro-Dream-Hand` still retain local interpretations of inputs or signals that should belong to a single upstream source.

This keeps the suite functionally rich but operationally ambiguous. The operator can still end up asking:

- Which module actually owns suite startup and workspace orchestration?
- Which screen is the real place to choose a target?
- Which service defines valid CNL semantics?
- Which module owns generic EMG acquisition and encoding artifacts?

## Source Basis

This roadmap is based on the current repo state in:

- `docs/2026-04-28-cnl-studio-neurosim-neurochip-consolidation-roadmap.md`
- `nmtk/neuro_toolkit/assets/modules.json`
- `Neurohub/neurohub_spec.md`
- `Neurohub/README.md`
- `Neurohub/frontend/lib/screens/dashboard_screen.dart`
- `nmtk/neuro_toolkit/lib/screens/catalog.dart`
- `nmtk/neuro_toolkit/lib/screens/tool_view.dart`
- `neurocnl/frontend/lib/screens/studio_screen.dart`
- `neurocnl/frontend/lib/routing/app_router.dart`
- `neurocnl/frontend/lib/screens/hardware_screen.dart`
- `neurocnl/frontend/lib/screens/analysis_screen.dart`
- `Neurochip/frontend/lib/models/shell_workspace.dart`
- `Neurochip/frontend/lib/widgets/target_selector.dart`
- `Neurochip/frontend/lib/screens/comparison_screen.dart`
- `Neurochip/frontend/lib/screens/target_gallery_screen.dart`
- `Neurosim/neurosim/app/services/cnl_to_graph.py`
- `Neurosense/README.md`
- `Neuro-Dream-Hand/README.md`
- `Neuro-Dream-Hand/SPEC.md`

## Recommended Product Rule

Adopt one canonical suite rule:

**Every operator decision gets one owner module, and adjacent modules consume that context instead of re-asking the question.**

Under that rule:

- `nmtk` owns suite control plane behavior, launcher state, install state, runtime state, and workspace orchestration.
- `NeuroHub` owns registry, project metadata, workflow metadata, and cross-module references, but not suite runtime control.
- `Studio` in `neurocnl` owns authoring-stage target choice and deployment handoff intent.
- `Neurochip` consumes imported target context by default and exposes override only as a secondary action.
- `neurocnl` owns canonical CNL semantics; downstream modules consume typed outputs instead of interpreting CNL independently.
- `NeuroSense` owns generic biosignal acquisition and EMG-to-spike artifacts; `Neuro-Dream-Hand` consumes those artifacts for prosthetic-specific behavior.

## Target UX and Ownership Model

The desired suite model should be:

1. Launch and workspace orchestration begin in `nmtk`.
2. `NeuroHub` contributes project and workflow metadata into that control plane instead of acting like a second launcher.
3. `Studio` owns pipeline progression, readiness, and initial target selection.
4. `Neurochip` opens directly in imported target context and only offers target override as an explicit secondary action.
5. `NeuroSim` edits, lays out, and persists graphs without becoming a second CNL authority.
6. `NeuroSense` produces reusable signal and encoding artifacts that `Neuro-Dream-Hand` and other modules consume.

The operator should not have to re-answer:

- "Where do I start the suite?"
- "What target am I using?"
- "What does this CNL mean?"
- "Which module owns EMG ingestion?"

## Non-Goals

This roadmap does not recommend:

- collapsing all product modules into the launcher
- deleting `NeuroHub`, `NeuroSim`, or `Neuro-Dream-Hand` as products
- moving hardware execution into `neurocnl`
- moving prosthetic-specific control logic into `NeuroSense`
- removing expert override paths where they remain explicitly secondary and clearly labeled

## Core Consolidation Decisions

### 1. One suite control plane

`nmtk` becomes the only suite control plane.

Implications:

- launcher manifests, install state, health state, workspace routing, and runtime orchestration stay in `nmtk`
- `NeuroHub` stops behaving like a peer launcher UI
- launcher-visible descriptions and manifests stop describing `NeuroHub` as the orchestrator

### 2. One workflow owner in `neurocnl`

`Studio` becomes the only primary workflow owner inside `neurocnl`.

Implications:

- `Hardware` and `Analysis` no longer operate as top-level peer routes for decisions already covered by `Studio`
- hardware diagnostics either move into `Studio` review panels or into the true owner module
- analysis panels become subordinate workflow surfaces rather than competing entrypoints

### 3. One target-context owner in `Neurochip`

Imported target context becomes the default state for `Neurochip`.

Implications:

- target choice is imported from upstream by default
- `Change Target` remains allowed, but as a secondary action
- comparison becomes an evaluation workflow, not another selection workflow

### 4. One semantic owner for CNL

`neurocnl` becomes the only canonical owner of valid CNL meaning.

Implications:

- `NeuroSim` consumes typed graph or repair payloads rather than defining equivalent local semantics
- any local parser in `NeuroSim` must be explicitly lossy and visibly labeled as fallback behavior

### 5. One generic biosignal owner

`NeuroSense` becomes the generic owner of EMG acquisition and encoding artifacts.

Implications:

- `Neuro-Dream-Hand` stops claiming generic EMG ingestion and encoding as a primary product boundary
- prosthetic-specific control, HITL logic, and actuation remain in `Neuro-Dream-Hand`
- generic hardware-prep kernels belong in `Neurochip`, not in the prosthetic app

## Concrete Engineering Roadmap

## Phase 1: Resolve `nmtk` versus `NeuroHub`

**Goal:** remove the suite’s biggest orchestration ambiguity first.

**Priority:** Highest

### Changes

- Update `nmtk/neuro_toolkit/assets/modules.json` and any launcher-facing copy so `NeuroHub` is described as registry and project metadata, not as the suite orchestrator.
- Update `NeuroHub` specs, README language, and dashboard chrome so the module no longer behaves like a second launcher with parallel `Home`, `Projects`, `Workflows`, and `System` ownership.
- Move any remaining runtime-control UX from `NeuroHub` into `nmtk`, or demote it to metadata views and deep links back into `nmtk`.
- Add or update an ADR that states `nmtk` is the only suite control plane and `NeuroHub` is not the runtime orchestrator.

### Status on 2026-04-29

- `nmtk/neuro_toolkit/assets/modules.json` now describes `NeuroHub` as registry and metadata.
- NeuroHub docs and module guidance now say `nmtk` owns runtime control.
- NeuroHub dashboard chrome now uses project-focus navigation instead of launcher-like workspace ownership language.
- Legacy NeuroHub orchestration and workflow deep links restore into surviving metadata views instead of keeping parallel runtime-control routes alive.

### Acceptance criteria

- `nmtk` is the only module that describes itself as the suite control plane in manifests, docs, and primary UI copy.
- `NeuroHub` no longer presents launcher-parallel navigation or workspace switching as if it owns suite runtime control.
- Launcher manifests, Dart models, tests, and helper scripts remain synchronized after the description and ownership update.
- `python3 scripts/launcher_control_service.py --doctor --json` reports no new fatal launcher regressions after the change.

## Phase 2: Collapse `neurocnl` side-route ownership

**Goal:** make `Studio` the only primary workflow owner inside `neurocnl`.

**Priority:** High

### Changes

- Remove, demote, or reframe the top-level `Hardware` and `Analysis` routes in `neurocnl/frontend/lib/routing/app_router.dart`.
- Fold serial connectivity, live telemetry, energy profiling, quantization review, and fault-injection review into `Studio` when they are part of the authoring-to-deployment workflow.
- Move hardware-signal work that is really a live device concern to `NeuroSense`.
- Move deployability diagnostics that are really a target-execution concern to `Neurochip`.
- Update route copy, docs, and tests so `Studio` is unambiguously the default workflow shell.

### Status on 2026-04-29

- `neurocnl/frontend/lib/routing/app_router.dart` still preserves `/hardware` and `/analysis`, but only as compatibility redirects back into `Studio`.
- The shell chrome exposes only `Studio` as a primary destination.
- `Studio` remains the main authoring-to-deploy workflow surface with `Parsed Specs`, `Validation`, `Generate`, `Preview`, and `Deploy` panels.
- Legacy `Analysis` and `Hardware` ownership is now collapsed into a subordinate `Deploy Review & Handoff` section inside `Studio` `Deploy`.
- Energy, quantization, fault-injection, serial preview, and local telemetry preview remain accessible inside `Studio`, while downstream runtime diagnostics still hand off into `Neurochip` and reusable live telemetry still hands off into `NeuroSense`.
- `neurocnl/docs/USER_HAPPY_FLOW.md` now describes `Studio` `Deploy` as the canonical owner of deploy review plus subordinate diagnostics or local preview.

### Execution slices

1. Route demotion
   Replace top-level `/hardware` and `/analysis` ownership with `Studio`-owned panels or subordinate deep links, and remove them from primary shell navigation.
2. Workflow reassignment
   Keep authoring-stage validation and deploy review inside `Studio`; move true live-device concerns toward `NeuroSense` and true target-execution diagnostics toward `Neurochip`.
3. Documentation and verification
   Update `README.md`, `docs/USER_HAPPY_FLOW.md`, and frontend tests so `Studio` is the only canonical workflow shell in both copy and behavior.

### Acceptance criteria

- A normal `neurocnl` operator can complete the primary workflow without leaving `Studio` for a peer top-level route.
- No top-level `neurocnl` route asks for a target, connectivity, or analysis decision that `Studio` already owns.
- Any surviving advanced routes are explicitly subordinate, not peers in the default workflow.
- Module docs and route labels describe `Studio` as the canonical workflow owner.

### Phase 2 next implementation step

Phase 2 is complete enough to move the consolidation thread forward. The next follow-up in `neurocnl` should be cleanup-only: remove any now-unused legacy screen wrappers once no downstream tests or embeds rely on them.

## Phase 3: Remove repeated target-selection flows in `Neurochip`

**Goal:** make imported target context the default and only primary target choice.

**Priority:** High

### Changes

- Refactor `Neurochip` workspace state so imported target context is the default state across `Analysis`, `Compare`, and `Change Target`.
- Reframe comparison UI as “evaluate alternatives” rather than “pick target again.”
- Keep `Change Target` available, but only as an explicit secondary override path.
- Update shell chrome, summary cards, and workspace labels so the active target remains visible and stable across screens.
- Align any import payload handling and shell tests with the single-source target model.

### Status on 2026-04-29

- Imported Studio handoff now seeds the active Neurochip workspace, selected target, and default comparison baseline together.
- `Analysis` no longer opens with a fresh target selector; it starts from the active imported target context and sends manual target changes through `Target Override`.
- The comparison workspace is now framed as alternative evaluation against the active target rather than as a second primary target chooser.
- The former `Change Target` workspace is now labeled `Target Override` and explicitly documents override-only intent.
- Shell labels, target badges, and focused tests now reflect the single-source imported target model, including Akida following the same explicit handoff-first ownership pattern as Teensy and PYNQ.

### Acceptance criteria

- A handoff from `Studio` opens `Neurochip` in one clear active-target context without an immediate second target-selection flow.
- `Comparison` no longer acts as a parallel target chooser; it is clearly framed as alternative evaluation.
- `Change Target` remains possible but is visibly secondary to the imported context.
- Frontend tests cover imported target context, explicit override, and comparison behavior under the new model.

## Phase 4: Demote local CNL interpretation in `NeuroSim`

**Goal:** make `neurocnl` the only canonical owner of CNL semantics.

**Priority:** Medium

### Changes

- Replace the default `NeuroSim` regex-based CNL parsing path with typed graph import or typed repair/import contracts sourced from `neurocnl`.
- If a local fallback parser remains, label it as a lossy repair or import path rather than a semantic peer to `neurocnl`.
- Add or update ADR and contract documentation that states `NeuroSim` consumes canonical semantics instead of defining them.
- Update tests on both sides of the boundary so graph ids, connectivity, and import semantics stay stable.

### Status on 2026-04-29

- `NeuroSim` now labels the local regex importer as a lossy repair path instead of a semantic peer to `neurocnl`.
- Preview, validation, export, and sweep runtime metadata fail closed for topologies that exceed the canonical two-node sensory -> motor reflex arc.
- Canonical reflex-arc sweeps over population-specific preview parameters now keep `faithful` runtime metadata when NeuroSim can execute the authored graph exactly through its local Nengo preview builder, instead of regressing to `approximate`.
- `Neurosim/docs/neurocnl_runtime_alignment.md` now documents the boundary between shared NeuroCNL generator fidelity and faithful NeuroSim-local preview execution for those sweep-only parameter variations.
- Cross-module sweep smoke coverage now expects the canonical `neurocnl` -> `NeuroSim` round-trip to retain `faithful` support metadata during parameter sweeps.

### Acceptance criteria

- `NeuroSim` no longer presents its local parser as an equivalent source of valid CNL meaning.
- Canonical CNL-to-graph semantics are documented as owned by `neurocnl`.
- Any fallback import path is explicitly marked as lossy or repair-oriented.
- Cross-module tests prove `NeuroSim` consumes the shared semantic contract rather than an independent local interpretation.

## Phase 5: Separate generic EMG ownership from prosthetic-specific logic

**Goal:** remove duplicate biosignal ownership between `NeuroSense` and `Neuro-Dream-Hand`.

**Priority:** Medium

### Changes

- Update `NeuroSense` docs and contracts so generic EMG acquisition, filtering, spike encoding, recording, and replay are the clearly owned reusable artifacts.
- Update `Neuro-Dream-Hand` docs and architecture so generic EMG ingestion and generic encoding are described as consumed capabilities, not owned product boundaries.
- Move or contract any generic hardware-prep kernels, quantization artifacts, or crossbar-export semantics into `Neurochip` where they are not prosthetic-specific.
- Keep prosthetic-specific HITL control, policy logic, and actuation verification in `Neuro-Dream-Hand`.

### Status on 2026-04-29

- `NeuroSense` README and artifact docs now describe the module as the canonical owner of reusable EMG acquisition, filtering, encoding, recording, replay, and session-artifact semantics.
- `NeuroSense` toolkit handoff guidance now names `Neuro-Dream-Hand` as a downstream consumer of the same canonical artifact contract already used by `neurocnl` and `Neurobench`.
- `Neuro-Dream-Hand` README and `SPEC.md` now describe generic EMG ingestion and encoding as consumed capabilities from `NeuroSense`, while keeping prosthetic-specific HITL control, intent mapping, and actuation verification local.
- `Neuro-Dream-Hand` contracts now include an explicit consumed-`NeuroSense` session handoff contract, and contract tests pin the consumer-versus-owner split in code.

### Acceptance criteria

- `NeuroSense` is the only module that describes itself as the generic owner of reusable EMG acquisition and encoding artifacts.
- `Neuro-Dream-Hand` documentation no longer claims generic EMG and encoding ownership where that overlaps with `NeuroSense`.
- Hardware-prep ownership is documented so generic chip-prep behavior belongs to `Neurochip`, not the prosthetic app.
- Downstream contracts and tests make the consumer-versus-owner split explicit.

## Verification Expectations

The implementation work for this roadmap should verify by phase, not only at the end.

Expected checks when code changes land:

- For `nmtk` or launcher-visible contract changes: `bash scripts/run_launcher_guardrails.sh`
- For launcher-visible contract or startup changes: `bash scripts/run_launcher_guardrails.sh --with-integration`
- For cross-module contract changes: `python3 -m pytest tests/integration/test_cross_module.py`
- For suite-visible hardware flow changes: `python3 -m pytest tests/integration/test_teensy_e2e.py`
- For `NeuroHub`, `neurocnl`, `Neurochip`, `NeuroSim`, `NeuroSense`, and `Neuro-Dream-Hand` changes: run the owning checks required by each module `AGENTS.md`

## Recommended Execution Order

1. Phase 1: `nmtk` versus `NeuroHub`
2. Phase 2: `neurocnl` side-route collapse
3. Phase 3: `Neurochip` target-context consolidation
4. Phase 4: `NeuroSim` semantic demotion
5. Phase 5: `NeuroSense` versus `Neuro-Dream-Hand`

This order matters because:

- `nmtk` versus `NeuroHub` affects the whole suite’s control-plane story.
- `neurocnl` and `Neurochip` are the most visible remaining UX ambiguities after the April 28 consolidation.
- semantic ownership and biosignal ownership should be tightened after the operator-facing control surfaces are unambiguous.

## Immediate Next Step

Start Phase 2 in `neurocnl/frontend/lib/routing/app_router.dart` by removing `Hardware` and `Analysis` from primary shell navigation and treating `Studio` as the only default workflow destination. That route change should land together with the first `Studio` panel migration and doc updates so the UX, copy, and ownership model stay synchronized.

## Exit Condition

This roadmap is complete when:

- the suite has one visible control plane
- each cross-module user decision has one clear owner
- adjacent modules consume imported context rather than re-asking the same question
- docs, manifests, UI copy, and tests all describe the same ownership model
