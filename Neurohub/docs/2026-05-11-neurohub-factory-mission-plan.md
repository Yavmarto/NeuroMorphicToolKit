# NeuroHub Factory Mission Plan

Date: 2026-05-11

## Purpose

This document is a Factory Missions planning brief for `Neurohub`.
It is written for an agent that only has this checkout and should not rely on other repos,
private runtime services, or proprietary artefacts.

The goal is to move NeuroHub forward as a registry and sharing-space module that stays compatible
with the current architecture decision that `nmtk` owns the suite control plane.

This plan is intentionally scoped so Factory can execute useful long-horizon work without needing
the whole multi-repo environment.

---

## Factory Mission Framing

This plan is shaped for Factory Missions:

- features are discrete and validation-friendly
- milestones are self-contained and meaningful
- intervention guidance is explicit
- repo-isolation is built into the scope

Rough Factory run estimate using the published heuristic:

- features: 9
- milestones: 4
- estimated floor: `9 + 2 * 4 = 17` runs

Reference used for shaping this plan:
- [Factory Missions docs](https://docs.factory.ai/cli/features/missions)

---

## Safe Context Package For Factory

Share only these local files and folders with Factory for this mission:

- `Neurohub/AGENTS.md`
- `CODING_STYLE_GUIDE.md`
- `Neurohub/neurohub_spec.md`
- `docs/ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md`
- `issues-archive/05-neurohub-reposition-as-sharing-space.md`
- `Neurohub/issues/025-prod-responsive-dashboard-and-bundle-surfaces.md`
- `Neurohub/neurohub/contracts/**`
- `Neurohub/neurohub/app/schemas/**`
- `Neurohub/neurohub/app/routers/**`
- `Neurohub/neurohub/app/services/**`
- `Neurohub/neurohub/tests/**`
- `Neurohub/frontend/lib/**`
- `Neurohub/frontend/test/**`

Do not share with Factory unless truly required:

- unrelated `nmtk` source trees
- private auth secrets or local environment files
- private production registry data or user records
- unpublished project metadata from external systems
- internal notes from sibling repos that are not needed to implement this module

If Factory asks for launcher or workspace behavior from another repo, answer with this rule:

- `nmtk` owns install, startup, runtime health, workspace hosting, and launcher actions
- `NeuroHub` owns registry metadata, sharing flows, bundles, project metadata, and local views

Do not paste code from repos Factory cannot access.

---

## Problem Statement

NeuroHub already has meaningful code, but it sits between two competing identities:

1. an older hub/orchestration concept
2. the newer registry-and-sharing-space direction

The current architecture is clear:

- `nmtk` is the sole suite control plane
- `NeuroHub` is a registry and metadata module

The local codebase already supports this direction better than the old story suggests:

- backend contracts for projects, workflows, and bundles exist
- property tests already exist for workflow, project, and bundle invariants
- sharing routes already exist:
  - `Neurohub/neurohub/app/routers/sharing.py`
- frontend sharing screens already exist:
  - `Neurohub/frontend/lib/screens/feed_screen.dart`
  - `Neurohub/frontend/lib/screens/my_shares_screen.dart`
  - `Neurohub/frontend/lib/screens/team_screen.dart`
- responsive audit coverage already exists:
  - `Neurohub/frontend/test/screens/neurohub_responsive_audit_test.dart`

What is still missing is a clear, execution-ready plan that focuses on module-local work and
does not require Factory to coordinate across the whole suite.

---

## Scope

### In Scope

- Harden NeuroHub as a registry and sharing-space module
- Remove or isolate orchestration-era UX and route assumptions inside the local module
- Improve the backend contract and service boundaries around projects, workflows, bundles, and shares
- Ship a clean frontend information architecture centered on dashboard, feed, my shares, team, and bundle inspection
- Finish responsive and narrow-width usability for core NeuroHub workflows
- Strengthen tests around contracts, workflows, feed/shares, and responsive UI

### Explicitly Out Of Scope

- Adding launcher, startup, repair, install, or workspace-hosting behavior
- Cross-repo manifest edits in `nmtk` as part of this mission
- Building the full public internet-scale HuggingFace-style registry on day one
- Private production auth/permissions integrations that need external services
- External billing, notifications, or commercial marketplace features

---

## Target Product Definition

At the end of this mission, NeuroHub should read and behave as:

- a local and future-hostable registry/metadata service
- a sharing surface for bundles and artefacts
- a project/workflow metadata workspace
- a frontend that is usable on compact widths
- a module that never pretends to be the suite launcher

The module should still support:

- project metadata
- workflow metadata/history
- bundle inspection and sharing
- feed and my-shares views
- team surface, even if partially stubbed

The module should not add new runtime-control responsibilities.

---

## Architecture Guardrails

These guardrails come from the module AGENTS file and accepted ADRs.

### Ownership Boundaries

- `Neurohub` owns registry metadata and sharing-space behavior
- `nmtk` owns launcher, install/startup, runtime health, and workspace hosting
- Cross-app reads and writes stay centralized in `Neurohub/neurohub/app/services/suite_client.py`

### Contract Discipline

- Update contracts before changing router semantics
- Keep schemas, services, routers, and frontend models aligned
- Do not change payload fields only in the frontend

### Repo-Isolation Discipline

- Avoid any required implementation step that depends on sibling repos
- If a cross-module behavior is referenced, treat it as a link or metadata reference, not a required code dependency
- Defer launcher rail renames or manifest changes to a separate manual follow-up outside this mission

### UX Discipline

- Project selection in NeuroHub is local metadata navigation, not suite workspace control
- Feed, my shares, team, dashboard, and bundle inspection are the primary surfaces
- Any surviving legacy orchestration state should restore into the nearest metadata view, not a control-plane view

---

## Current-Code Anchors

Factory should orient itself around these files first.

### Local Architecture

- `Neurohub/AGENTS.md`
- `docs/ADR-claude/0023-nmtk-sole-control-plane-neurohub-metadata-layer.md`
- `issues-archive/05-neurohub-reposition-as-sharing-space.md`
- `Neurohub/issues/025-prod-responsive-dashboard-and-bundle-surfaces.md`

### Backend Contracts And APIs

- `Neurohub/neurohub/contracts/project_contracts.py`
- `Neurohub/neurohub/contracts/workflow_contracts.py`
- `Neurohub/neurohub/contracts/bundle_contracts.py`
- `Neurohub/neurohub/app/routers/sharing.py`
- `Neurohub/neurohub/app/routers/projects.py`
- `Neurohub/neurohub/app/routers/workflows.py`
- `Neurohub/neurohub/app/routers/dashboard.py`
- `Neurohub/neurohub/app/services/project_service.py`
- `Neurohub/neurohub/app/services/workflow_engine.py`
- `Neurohub/neurohub/app/services/bundle_service.py`

### Frontend

- `Neurohub/frontend/lib/screens/dashboard_screen.dart`
- `Neurohub/frontend/lib/screens/bundle_inspection_screen.dart`
- `Neurohub/frontend/lib/screens/project_detail_screen.dart`
- `Neurohub/frontend/lib/screens/new_project_screen.dart`
- `Neurohub/frontend/lib/screens/feed_screen.dart`
- `Neurohub/frontend/lib/screens/my_shares_screen.dart`
- `Neurohub/frontend/lib/screens/team_screen.dart`
- `Neurohub/frontend/lib/widgets/activity_feed.dart`
- `Neurohub/frontend/lib/widgets/project_card.dart`
- `Neurohub/frontend/lib/widgets/asset_card.dart`
- `Neurohub/frontend/lib/widgets/suite_health_bar.dart`
- `Neurohub/frontend/lib/shell/neurohub_route_state.dart`
- `Neurohub/frontend/lib/shell/neurohub_deep_link.dart`
- `Neurohub/frontend/lib/shell/neurohub_restoration_snapshot.dart`

### Tests

- `Neurohub/neurohub/tests/test_contracts.py`
- `Neurohub/neurohub/tests/test_contract_invariants.py`
- `Neurohub/neurohub/tests/properties/test_project_properties.py`
- `Neurohub/neurohub/tests/properties/test_workflow_properties.py`
- `Neurohub/neurohub/tests/properties/test_bundle_properties.py`
- `Neurohub/frontend/test/screens/neurohub_responsive_audit_test.dart`

---

## Recommended End-State Design

### 1. Stable Module Identity

NeuroHub should become internally consistent around one identity:

- registry
- sharing
- metadata
- bundle/project/workflow inspection

Anything that looks like launcher control should be removed, gated off, or reframed into metadata.

### 2. Contract-First Backend

The backend should continue to center around:

- project contracts
- workflow contracts
- bundle contracts
- sharing assets

This is already a strength of the module. The mission should reinforce it, not replace it.

### 3. Sharing-Centered Frontend IA

The frontend should clearly expose:

- dashboard
- feed
- my shares
- team
- bundle inspection
- new project
- project detail

Screens should be explicit about whether they are local project metadata, community feed, or team view.

### 4. Responsive, Compact-Width Usability

The frontend needs deliberate compact layouts, not passive shrinking.
The responsive work should be treated as product work, not polish.

### 5. Local-Only Cross-Module Awareness

Deep links and cross-module references can remain, but they must stay as references.
No new launcher orchestration behavior should be implemented in this mission.

---

## Mission Features

### Feature 1: Identity Cleanup

Audit and remove local remnants of the orchestration-hub story from NeuroHub-owned code.

This includes:

- labels
- empty or misleading tabs
- control-plane copy
- restoration behavior that points to non-surviving orchestration screens

Validation:

- no primary local surface presents NeuroHub as launcher/controller

### Feature 2: Route And Schema Truthfulness

Align backend routes and schemas with the registry/sharing identity.

Priority surfaces:

- sharing feed
- my shares
- project bundle inspection
- workflow and project metadata

Validation:

- router tests and schema tests pass

### Feature 3: Contract Hardening

Strengthen and reconcile contract invariants where needed.

This includes:

- project refs
- workflow DAG rules
- bundle integrity
- asset metadata consistency

Validation:

- unit tests and property tests pass

### Feature 4: Dashboard Information Architecture

Refine the dashboard so it acts as the local entry point for project and sharing workflows,
not a pseudo-launcher.

Validation:

- dashboard tests pass
- no dashboard card depends on suite-control semantics

### Feature 5: Sharing Surfaces

Complete the feed, my shares, and team surfaces so they feel intentional and connected.

Validation:

- feed and my-shares routes are exercised in backend tests
- frontend tests cover empty state, populated state, and navigation

### Feature 6: Bundle Inspection And Project Detail

Make bundle inspection and project detail strong metadata views.

Validation:

- narrow-width and medium-width layouts are proven by widget tests
- core metadata remains visible without page-level horizontal scrolling

### Feature 7: Responsive Audit Completion

Treat responsive behavior as its own feature, anchored by:

- `Neurohub/issues/025-prod-responsive-dashboard-and-bundle-surfaces.md`

Validation:

- target widths: `1440`, `1024`, `768`, `600`, `390`
- no `RenderFlex overflow`
- primary actions stay visible

### Feature 8: Shell And Restoration Consistency

Align route state, deep links, and restoration snapshots with the surviving screen model.

Validation:

- shell tests pass
- restoring app state never routes to removed control-plane surfaces

### Feature 9: Documentation And Handoff

Update local docs so a future agent or human sees the same truthful story as the code.

Validation:

- NeuroHub docs and comments describe registry/metadata behavior, not launcher ownership

---

## Milestones

### Milestone 1: Contract And Identity Foundation

Includes:

- Feature 1
- Feature 2
- Feature 3

Success criteria:

- local module identity is clear
- contracts and routes match that identity
- no new work depends on other repos

Validation worker checklist:

- `cd /NeuroMorphicToolKit`
- `PYTHONPATH=. pytest Neurohub/neurohub/tests/test_contracts.py -v`
- `PYTHONPATH=. pytest Neurohub/neurohub/tests/test_contract_invariants.py -v`
- `PYTHONPATH=. pytest Neurohub/neurohub/tests/properties/ -v`

### Milestone 2: Backend And Shell Coherence

Includes:

- Feature 4
- Feature 8

Success criteria:

- dashboard role is clean
- shell/deeplink/restoration semantics match the surviving IA

Validation worker checklist:

- relevant backend router tests
- `cd Neurohub/frontend && flutter test`
- targeted shell tests

### Milestone 3: Sharing Product Surfaces

Includes:

- Feature 5
- Feature 6

Success criteria:

- feed, my shares, team, bundle inspection, and project detail form a coherent product flow

Validation worker checklist:

- backend sharing route tests
- frontend screen and widget tests

### Milestone 4: Responsive Readiness And Documentation

Includes:

- Feature 7
- Feature 9

Success criteria:

- responsive audit is complete
- docs match the shipped behavior

Validation worker checklist:

- `cd Neurohub/frontend && flutter test`
- responsive audit tests
- `PYTHONPATH=. pytest Neurohub/neurohub/tests/ -v`
- `ruff check Neurohub`
- `mypy Neurohub`

---

## Recommended File-Level Change Map

This is the safest initial write set for Factory.

### Backend

- Modify: `Neurohub/neurohub/app/routers/sharing.py`
- Modify: `Neurohub/neurohub/app/routers/dashboard.py`
- Modify as needed: `Neurohub/neurohub/app/routers/projects.py`
- Modify as needed: `Neurohub/neurohub/app/routers/workflows.py`
- Modify service files only where route semantics actually require it

### Contracts And Schemas

- Modify: `Neurohub/neurohub/contracts/*.py`
- Modify: `Neurohub/neurohub/app/schemas/*.py`

### Frontend Screens And Widgets

- Modify: `Neurohub/frontend/lib/screens/dashboard_screen.dart`
- Modify: `Neurohub/frontend/lib/screens/bundle_inspection_screen.dart`
- Modify: `Neurohub/frontend/lib/screens/project_detail_screen.dart`
- Modify: `Neurohub/frontend/lib/screens/new_project_screen.dart`
- Modify: `Neurohub/frontend/lib/screens/feed_screen.dart`
- Modify: `Neurohub/frontend/lib/screens/my_shares_screen.dart`
- Modify: `Neurohub/frontend/lib/screens/team_screen.dart`
- Modify supporting widgets only where responsive or IA issues actually surface

### Shell

- Modify: `Neurohub/frontend/lib/shell/neurohub_route_state.dart`
- Modify: `Neurohub/frontend/lib/shell/neurohub_deep_link.dart`
- Modify: `Neurohub/frontend/lib/shell/neurohub_restoration_snapshot.dart`

### Tests

- Modify or add backend tests in `Neurohub/neurohub/tests/`
- Modify or add frontend tests in `Neurohub/frontend/test/`

### Docs

- Modify: `Neurohub/neurohub_spec.md` if shipped behavior or scope wording changes
- Optionally update local README or notes if they still carry orchestration-era language

---

## Sequencing Rules For Factory

1. Do not begin with CSS-only or widget-only polishing.
2. Stabilize module identity and backend truthfulness first.
3. Make shell/restoration behavior align with the surviving IA before heavy frontend polishing.
4. Finish responsive work only after screen responsibilities are clear.
5. Defer any `nmtk` edits to a separate non-Factory follow-up.

If a worker proposes manifest or launcher changes, reject them as out of scope for this mission.

---

## Validation Gates

Use these command groups at milestone boundaries.

### Backend

- `cd /NeuroMorphicToolKit`
- `PYTHONPATH=. pytest Neurohub/neurohub/tests/ -v`
- `ruff check Neurohub`
- `mypy Neurohub`

### Frontend

- `cd /NeuroMorphicToolKit/Neurohub/frontend && flutter test`

### High-Signal Responsive Checks

Specifically review:

- `Neurohub/frontend/test/screens/neurohub_responsive_audit_test.dart`
- `Neurohub/frontend/test/screens/dashboard_screen_test.dart`
- `Neurohub/frontend/test/screens/bundle_inspection_screen_test.dart`
- `Neurohub/frontend/test/screens/project_detail_screen_test.dart`

---

## Intervention Guide For Mission Control

### If the mission drifts into launcher ownership

Tell Mission Control:

> NeuroHub is not allowed to add launcher, startup, runtime health, or workspace-hosting behavior. Re-scope back to registry, metadata, and sharing.

### If a worker blocks on `nmtk`

Tell Mission Control:

> Do not depend on nmtk implementation access. Keep any launcher-facing work to notes or follow-up items, not code in this mission.

### If a worker starts chasing full public-registry scale

Tell Mission Control:

> Keep this mission local and product-real. Prioritize contract truthfulness, sharing surfaces, and responsive UX over internet-scale registry ambitions.

### If a worker gets stuck polishing without settling IA

Tell Mission Control:

> Pause visual polish. First finalize which screens survive, what each owns, and how shell state maps to them. Then resume responsive work.

---

## Acceptance Criteria

The mission is complete when all of the following are true:

- NeuroHub locally reads as a registry/metadata/sharing module
- no primary local surface implies launcher ownership
- backend contracts and routes align with that story
- feed, my shares, team, bundle inspection, project detail, and dashboard feel coherent
- responsive behavior is proven at compact and medium widths
- shell and restoration state map only to surviving screens
- no implementation step required access to hidden sibling repos

---

## Explicit Follow-Ups Outside This Mission

These are valid next steps, but should not be part of the initial Factory mission:

- launcher rail rename or module manifest copy changes in `nmtk`
- external auth integration beyond local module needs
- public cloud registry scaling work
- richer cross-module import/publish flows requiring sibling-repo coordination
- broad suite-wide docs cleanup outside NeuroHub-owned docs

