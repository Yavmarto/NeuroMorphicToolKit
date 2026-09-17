# Neurotraining Factory Mission Plan

Date: 2026-05-11

## Purpose

This document is a Factory Missions planning brief for a new `neurotraining` surface inside `neurocnl`.
It is written for an agent that does not have access to sibling repos or private infrastructure.

The goal is to create a first-class training workflow for CNL Studio that is compatible with the
current `neurocnl` architecture, truthful about backend support, and safe to implement in isolation.

This plan intentionally avoids sharing private or unnecessary cross-repo details. It assumes only
the local checkout contents described below.

---

## Factory Mission Framing

Factory Missions work best when the plan is split into:

- clear features
- milestone checkpoints
- explicit validation
- intervention rules when the mission drifts or stalls

This plan is structured that way on purpose.

Rough Factory run estimate using the published heuristic:

- features: 8
- milestones: 4
- estimated floor: `8 + 2 * 4 = 16` runs

Actual run count will be higher if validation workers open follow-up fixes.

Reference used for shaping this plan:
- [Factory Missions docs](https://docs.factory.ai/cli/features/missions)

---

## Safe Context Package For Factory

Share only these local files and folders with Factory for this mission:

- `neurocnl/AGENTS.md`
- `CODING_STYLE_GUIDE.md`
- `neurocnl/docs/support_matrix.md`
- `docs/neurocnl_status_and_priorities.md`
- `docs/unified_toolkit_architecture.md`
- `neurocnl/neurocnl/training_registry.py`
- `neurocnl/neurocnl/pipeline.py`
- `neurocnl/backend/app/routers/prosthetic/sleep.py`
- `neurocnl/backend/app/services/sleep_runner.py`
- `neurocnl/backend/tests/test_prosthetic_sleep.py`
- `neurocnl/backend/tests/test_sleep_runner_service.py`
- `neurocnl/frontend/lib/providers/learning_provider.dart`
- `neurocnl/frontend/lib/models/sleep_train.dart`
- `neurocnl/frontend/lib/widgets/learning_config_panel.dart`
- `neurocnl/frontend/lib/providers/pipeline_provider.dart`
- `neurocnl/frontend/lib/screens/studio_screen.dart`
- `neurocnl/frontend/test/`

Do not share with Factory unless absolutely necessary:

- any sibling repo internals outside this checkout
- unpublished hardware SDK credentials or license files
- proprietary datasets, benchmark artefacts, or customer-specific workflows
- private runtime endpoints or remote host details
- the full contents of unrelated module docs

If Factory asks for missing context from sibling repos, answer with interface expectations only.
Do not paste code from repos it cannot access.

---

## Problem Statement

`neurocnl` already contains training groundwork, but it is not a real product surface yet.

What exists today:

- A tested adapter registry scaffold in `neurocnl/neurocnl/training_registry.py`
- A narrow sleep-training backend path at `POST /api/prosthetic/sleep`
- A sleep-training service in `neurocnl/backend/app/services/sleep_runner.py`
- Frontend learning state and config UI in:
  - `neurocnl/frontend/lib/providers/learning_provider.dart`
  - `neurocnl/frontend/lib/models/sleep_train.dart`
  - `neurocnl/frontend/lib/widgets/learning_config_panel.dart`
- Architecture docs that explicitly say:
  - one real training adapter should be added next
  - a thin public `compile()` / `fit()` / `evaluate()` layer is still missing

What is missing:

- a first-class training module in Studio
- a unified backend API for listing capabilities and running training jobs
- a concrete adapter model that can grow beyond one hard-coded prosthetic flow
- clear truthfulness rules for what training modes are supported vs. planned
- persistence and UX for training results inside Studio workflows

---

## Scope

### In Scope

- Build a first-class `neurotraining` product surface inside `neurocnl`
- Reuse the existing training registry as the canonical selection mechanism
- Convert the current sleep-training flow into the first concrete adapter
- Add a generic backend training API with capability discovery
- Add a Studio training panel or training workspace section
- Keep background-job semantics aligned with the existing backend job system
- Keep support claims honest in docs and UI

### Explicitly Out Of Scope

- Broad multi-framework training support in the first ship
- Dataset ingestion systems for N-MNIST, DVS Gesture, DDD17
- Loihi, Xylo, BrainScaleS, or other hardware-in-the-loop training
- Changing sibling repos to consume new training artefacts
- New launcher or control-plane behavior in `nmtk`
- Publishing training jobs to external services
- Any requirement for access to `Neuro-Dream-Hand` source code

---

## Target Product Definition

Ship a training experience in NeuroCNL Studio where a user can:

1. open or author a CNL model
2. open a Training surface in the Studio
3. see which training modes are actually supported
4. configure the selected training run
5. start training as a background job
6. monitor status and errors in a truthful way
7. inspect and retain the result inside the current Studio session
8. optionally use the result in downstream local flows that already exist in `neurocnl`

The first supported adapter should be the existing sleep/PES-style training path, promoted from
a prosthetic-only endpoint into a generic training framework with a compatibility shim.

---

## Architecture Guardrails

These are non-negotiable if the implementation is to remain compatible with the current repo.

### Ownership Boundaries

- Library semantics live in `neurocnl/neurocnl/**`
- API routes and job orchestration live in `neurocnl/backend/**`
- Studio UX and local session state live in `neurocnl/frontend/**`
- Do not hide shared training semantics inside only the backend or only the UI

### Truthfulness Rules

- Do not claim a backend is trainable just because an adapter stub exists
- Capability discovery must expose only actually runnable modes
- Optional dependency absence must show as unavailable capability, not silent success
- Update `neurocnl/docs/support_matrix.md` and `docs/neurocnl_status_and_priorities.md` when support claims change

### Compatibility Rules

- Keep `POST /api/prosthetic/sleep` working during migration
- The existing sleep flow becomes a wrapper over the new generic training path
- Use the existing job store pattern rather than inventing a second async mechanism
- Do not couple the new API to a single downstream module or proprietary runtime

### Privacy And Repo-Isolation Rules

- Treat external training frameworks as optional adapters, not hard requirements
- When a dependency is unavailable, fail closed with a structured reason
- Never require sibling-repo code inspection to determine core `neurotraining` behavior

---

## Current-Code Anchors

Factory should treat these as the primary local anchors:

### Library

- `neurocnl/neurocnl/training_registry.py`
- `neurocnl/neurocnl/pipeline.py`
- `neurocnl/neurocnl/tests/test_training_registry.py`

### Backend

- `neurocnl/backend/app/routers/prosthetic/sleep.py`
- `neurocnl/backend/app/services/sleep_runner.py`
- `neurocnl/backend/tests/test_prosthetic_sleep.py`
- `neurocnl/backend/tests/test_sleep_runner_service.py`

### Frontend

- `neurocnl/frontend/lib/providers/learning_provider.dart`
- `neurocnl/frontend/lib/models/sleep_train.dart`
- `neurocnl/frontend/lib/widgets/learning_config_panel.dart`
- `neurocnl/frontend/lib/providers/pipeline_provider.dart`
- `neurocnl/frontend/lib/screens/studio_screen.dart`

### Planning Docs

- `docs/neurocnl_status_and_priorities.md`
- `docs/unified_toolkit_architecture.md`
- `neurocnl/docs/support_matrix.md`

---

## Recommended End-State Design

### 1. Canonical Domain Model

Create a generic training domain around these concepts:

- `TrainingCapability`
- `TrainingRequest`
- `TrainingResult`
- `TrainingRunSummary`
- `TrainingAvailability`
- `TrainingAdapter`

The existing `training_registry.py` should remain the canonical backend-name and mode-selection
mechanism. Extend it rather than replacing it.

### 2. First Concrete Adapter

Implement one real adapter first:

- backend name: `sleep_pes`
- supported mode(s): start with one honest mode, for example `offline_sleep`
- implementation source:
  - primary path uses the existing sleep-training logic
  - optional runtime dependency may enhance execution
  - deterministic fallback remains available for dev/test

This makes the first adapter real without depending on sibling repo access.

### 3. Generic Backend API

Add generic training routes under a new training router, for example:

- `GET /api/training/capabilities`
- `POST /api/training/run`
- `GET /api/training/jobs/{job_id}`

Keep `POST /api/prosthetic/sleep` as a compatibility wrapper during migration.

### 4. Studio Training Surface

Add a dedicated training surface in Studio rather than burying training inside a single dialog.

Recommended shape:

- a right-hand training inspector or a tab/panel alongside existing Studio surfaces
- capability list
- parameter form driven by selected capability
- start action
- live job status
- result summary
- actionable error rendering

### 5. High-Level Public API

If time allows in the same mission, expose a thin library-facing API that aligns with the roadmap:

- `compile(...)`
- `fit(...)`
- `evaluate(...)`

Do not attempt a large abstraction layer. A thin wrapper over existing pipeline and training
components is enough.

---

## Mission Features

Define the Factory Mission around these features.

### Feature 1: Training Domain Contract

Create a stable training domain model in `neurocnl/neurocnl/`:

- capability model
- request model
- result model
- structured unavailable-reason model

Validation:

- library tests cover capability normalization, unsupported modes, and structured failure paths

### Feature 2: Sleep Adapter Promotion

Turn the current sleep-training flow into the first real adapter:

- isolate sleep-specific execution behind the adapter interface
- keep deterministic fallback behavior for tests and local development
- remove direct route-to-service coupling where practical

Validation:

- existing sleep endpoint tests still pass
- new adapter tests verify both available and unavailable dependency modes

### Feature 3: Generic Training Router

Add backend routes for capability discovery and job submission.

Validation:

- backend tests cover:
  - capabilities listing
  - invalid backend selection
  - invalid mode selection
  - queued job submission
  - completed job retrieval
  - structured dependency-unavailable responses

### Feature 4: Compatibility Shim

Keep the legacy prosthetic sleep route working by delegating to the new generic system.

Validation:

- old route behavior remains stable
- response contract changes are either avoided or explicitly versioned

### Feature 5: Studio Training State

Add frontend state models and providers for generic training jobs.

Validation:

- provider tests cover idle, submitting, polling, success, and failure states

### Feature 6: Training UX In Studio

Expose the new training flow in Studio with a truthful capability-driven UI.

Validation:

- widget tests cover:
  - no capability available
  - one capability available
  - job progress
  - success summary
  - error rendering

### Feature 7: Result Reuse

Persist the result in current Studio state well enough for users to inspect and continue working.

Minimum acceptable scope:

- keep most recent result in provider state
- allow rerender after job poll completion
- display learned-weight or summary metadata without inventing a final model-zoo flow

Validation:

- provider and widget tests verify result state restoration within the current session

### Feature 8: Docs And Truthfulness Update

Update docs that describe current capabilities and support claims.

Validation:

- support docs mention the first supported training adapter
- planned-but-unimplemented training ecosystems remain clearly marked as future work

---

## Milestones

Factory should group features into four milestones.

### Milestone 1: Honest Core Training Backend

Includes:

- Feature 1
- Feature 2
- Feature 3

Success criteria:

- generic training domain exists
- one real adapter exists
- backend can list capabilities and submit a job
- unsupported states are structured and truthful

Validation worker checklist:

- `PYTHONPATH=. pytest neurocnl/neurocnl/tests/test_training_registry.py -v`
- targeted new training tests
- `PYTHONPATH=. pytest neurocnl/backend/tests/test_prosthetic_sleep.py -v`
- `PYTHONPATH=. pytest neurocnl/backend/tests/test_sleep_runner_service.py -v`

### Milestone 2: Backward Compatibility And API Stability

Includes:

- Feature 4

Success criteria:

- legacy sleep endpoint still works
- new system owns execution under the hood
- compatibility behavior is documented

Validation worker checklist:

- re-run all sleep endpoint tests
- ensure job payload shape remains acceptable for the current frontend

### Milestone 3: Studio Product Surface

Includes:

- Feature 5
- Feature 6
- Feature 7

Success criteria:

- training is visible as a first-class Studio capability
- UI is capability-driven, not hard-coded to prosthetic sleep text
- job status and results are understandable

Validation worker checklist:

- `cd neurocnl/frontend && flutter test`
- targeted provider tests
- targeted widget tests

### Milestone 4: Truthfulness, Cleanup, And Handoff Readiness

Includes:

- Feature 8
- selective refactor cleanup required to keep the system understandable

Success criteria:

- docs and support claims are aligned
- route and provider naming are coherent
- Factory can hand back a clean change set without sibling-repo assumptions

Validation worker checklist:

- `ruff check neurocnl`
- `mypy neurocnl`
- relevant pytest slices
- `cd neurocnl/frontend && flutter test`

---

## Recommended File-Level Change Map

This is the safest initial write set.

### Likely Library Files

- Modify: `neurocnl/neurocnl/training_registry.py`
- Create: `neurocnl/neurocnl/training/` package if a focused subpackage helps
- Create or modify training result/request models in `neurocnl/neurocnl/`
- Add tests near `neurocnl/neurocnl/tests/`

### Likely Backend Files

- Create: `neurocnl/backend/app/routers/training.py`
- Modify: `neurocnl/backend/app/routers/prosthetic/sleep.py`
- Modify or split: `neurocnl/backend/app/services/sleep_runner.py`
- Add backend tests under `neurocnl/backend/tests/`

### Likely Frontend Files

- Create generic training models/providers under `neurocnl/frontend/lib/models/` and `lib/providers/`
- Modify: `neurocnl/frontend/lib/providers/learning_provider.dart`
- Modify or replace: `neurocnl/frontend/lib/widgets/learning_config_panel.dart`
- Modify: `neurocnl/frontend/lib/screens/studio_screen.dart`
- Add tests under `neurocnl/frontend/test/`

### Likely Docs

- Modify: `docs/neurocnl_status_and_priorities.md`
- Modify: `docs/unified_toolkit_architecture.md` only where it speaks about current status
- Modify: `neurocnl/docs/support_matrix.md`

---

## Sequencing Rules For Factory

Use these ordering rules to prevent drift:

1. Do not start with UI.
2. Stabilize the training domain and backend capability contract first.
3. Keep the legacy sleep route working throughout.
4. Only then build the generic Studio surface.
5. Update docs last, after the truth of the code is settled.

If a worker proposes multiple adapters in the first milestone, reject that expansion.
One honest adapter is the correct scope.

---

## Validation Gates

Use these command groups at milestone boundaries.

### Library And Backend

- `cd /NeuroMorphicToolKit`
- `PYTHONPATH=. pytest neurocnl/neurocnl/tests/ -v`
- `PYTHONPATH=. pytest neurocnl/backend/tests/ -v`
- `ruff check neurocnl`
- `mypy neurocnl`

### Frontend

- `cd /NeuroMorphicToolKit/neurocnl/frontend && flutter test`

### Stretch Verification

If the mission changes support semantics or shared deploy/status language, also re-check:

- `neurocnl/frontend/test/widgets/error_reporting_test.dart`
- `neurocnl/frontend/test/pipeline_integration_test.dart`

---

## Intervention Guide For Mission Control

Use these intervention messages if Factory stalls:

### If the mission drifts into multi-framework abstraction

Tell Mission Control:

> Keep scope to one real adapter only. Do not add Norse, snnTorch, SpikingJelly, or dataset loaders in this mission. Re-plan around a single honest adapter.

### If a worker blocks on sibling-repo access

Tell Mission Control:

> Do not depend on sibling repos. Use the local adapter interface and the existing fallback behavior. Re-scope any cross-repo logic into interface-only compatibility notes.

### If a worker starts inventing launcher or suite behavior

Tell Mission Control:

> Training belongs inside neurocnl library, backend, and Studio UX only. Do not add launcher or nmtk work in this mission.

### If the mission gets stuck on naming

Tell Mission Control:

> Prefer generic names like training capability, training run, and training result. Keep the old sleep naming only at the compatibility boundary.

---

## Acceptance Criteria

The mission is complete when all of the following are true:

- `neurocnl` has a generic training registry path with one real adapter
- capability discovery is available via backend API
- training runs execute as background jobs
- the legacy sleep route still works
- Studio exposes a first-class training workflow
- unsupported or unavailable modes are surfaced honestly
- docs reflect what is actually implemented now
- no change depends on hidden sibling-repo logic

---

## Nice Follow-Ups After This Mission

Do not include these in the initial Factory mission unless the first four milestones complete cleanly:

- additional adapters beyond `sleep_pes`
- thin public `fit()` / `evaluate()` convenience wrappers if not already finished
- workspace persistence for training results
- benchmark handoff to NeuroBench
- dataset ingestion and training corpus loaders
