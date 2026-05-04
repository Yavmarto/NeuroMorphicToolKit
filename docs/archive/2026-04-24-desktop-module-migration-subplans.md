# Desktop-Only Module Migration Subplans

## Purpose

This document breaks the suite-wide desktop redesign into module-specific migration tracks.

It assumes the target architecture from the main redesign plan:

- one true desktop suite
- top-aligned shell navigation
- top-aligned module workspace switching
- persistent workspace sessions
- separate repositories retained
- package and adapter based integration instead of nested desktop apps

It also adds one important constraint:

- the migration should stay flexible enough to support a future mobile port where that makes product sense

## Canonical contract

This document is a module-lane execution guide. `DESIGN.md` remains the
canonical source for shared shell behavior, shell status language, and
desktop-first/mobile-portable rules.

Module teams should consume the shell contract rather than reinterpret it
locally.

The shell integration baseline for every module lane is:

- [Shell Adapter Contract And Package Conventions](./2026-04-24-shell-adapter-contract-and-package-conventions.md)
- [ADR 0017: Desktop Shell Adapter Contract](./ADR-claude/0017-desktop-shell-adapter-contract.md)

## Core strategy

Each module should move toward the same structure:

1. Domain core remains platform-agnostic.
2. Backend or service contracts remain typed and versioned.
3. UI logic is split into:
   - desktop shell adapter
   - reusable responsive feature widgets
   - optional mobile-specific composition later
4. Hardware-only or heavy workflows degrade cleanly on mobile instead of blocking the architecture.

The attached UI analysis adds an important product framing that should drive every module migration:

- the shell is mission control
- each module is a specialized workbench
- live and analytical surfaces should feel like instrument panels where appropriate

Current mode assignments are fixed by `DESIGN.md` and should be treated as part
of the adapter contract baseline.

## Mobile-flexibility rules

These rules apply to every module during desktop migration:

1. Do not bury business logic in desktop widget trees.
2. Keep domain models, contracts, and state machines independent from window size and pointer assumptions.
3. Prefer feature packages over app-local one-off screens.
4. Separate dense desktop layouts from reusable interaction primitives.
5. Treat mobile as a future composition target, not as the primary optimization target.
6. For hardware-bound workflows, plan for mobile as:
   - remote monitor
   - lightweight review client
   - setup companion
   rather than forcing full local execution.

These rules are normative for downstream module work. Repo-local briefs should
reference them instead of rewriting shell portability expectations from
scratch.

## Platform layers

### `nmtk`

Role:

- owns the desktop shell
- owns workspace state
- owns module lifecycle, install, launch, health, and recovery

Desktop migration plan:

1. Replace left sidebar navigation with a top app bar.
2. Move module switching into a second top workspace bar.
3. Replace route-per-module with `/workspace`.
4. Introduce persistent desktop workspace sessions.
5. Add a shell adapter contract for package-based module entrypoints.
6. Allow a temporary coexistence model where some modules are native desktop surfaces and others still bridge through embedded web content during migration.

Mobile-flexibility requirement:

- keep shell routing, session state, and module contracts independent from desktop-only widgets so a future mobile host can reuse the same module registry and workspace concepts.

### `nmtk_ui_core`

Role:

- shared design system and shell component library

Desktop migration plan:

1. Implement the top app bar, workspace switcher bar, shell status badges, and utility panel shell.
2. Move token authority under the new root `DESIGN.md`.
3. Build components as adaptive primitives:
   - desktop composition first
   - responsive behavior second
   - mobile-safe primitives where possible
4. Add shell-specific spacing, shape, elevation, and motion tokens.
5. Publish desktop and compact variants for key components rather than mixing all logic into one giant widget.

Mobile-flexibility requirement:

- keep core tokens, buttons, chips, forms, and status patterns reusable on smaller layouts even if the shell itself remains desktop-first.

### `neurocli`

Role:

- scriptable companion to the desktop suite

Desktop migration plan:

1. Define CLI commands that mirror shell actions:
   - install
   - launch
   - status
   - diagnostics
   - scaffold
2. Make desktop shell workflows callable through stable command contracts where practical.
3. Use the CLI as a portability layer for automation and future remote/mobile support.

Mobile-flexibility requirement:

- `neurocli` itself is not a mobile target, but its command contract should make it easier for a future mobile client to call into the same orchestration layer through an API.

## Product module subplans

### `neurocnl`

Current role:

- controlled natural language authoring, validation, generation, and export

Workbench mode:

- studio mode

Desktop target:

- native desktop authoring studio with split-pane editing, validation, preview, and export workflows

Why it fits desktop well:

- text editing
- multi-pane comparison
- export configuration
- dense diagnostics

Desktop migration plan:

1. Extract parser, validation, generation, and export orchestration into platform-agnostic application services.
2. Promote the editor, diagnostics panel, support-verdict panel, and export flows into a desktop-native feature package.
3. Keep backend support verdicts and export claims contract-driven and independent of the UI shell.
4. Add a `neurocnl_shell_adapter` package that exposes:
   - module metadata
   - desktop entry widget
   - deep-link targets for files, validations, exports, and support panels
5. Preserve current backend APIs during migration so other modules are not blocked.

Mobile-flexibility posture:

- full authoring can exist on tablet later
- phone should likely support review, validation summaries, and artifact browsing rather than full dense editing

Recommended migration order:

1. diagnostics and support panels
2. editor workspace
3. export and handoff surfaces

### `Neurosim`

Current role:

- graph canvas, simulation design, and visual preview

Workbench mode:

- studio mode

Desktop target:

- native desktop graph and simulation workspace

Why it fits desktop well:

- drag-and-drop canvas
- multi-selection
- dense inspector panels
- timeline and preview workflows

Desktop migration plan:

1. Extract canvas state, graph commands, simulation orchestration, and preview state into platform-neutral controller layers.
2. Build a desktop-native canvas surface optimized for mouse, keyboard, shortcuts, and large screens.
3. Move inspector panels, graph libraries, and simulation controls into desktop shell panels rather than web-embedded chrome.
4. Expose a `Neurosim_shell_adapter` package with:
   - desktop entry surface
   - project deep links
   - selection and simulation state restoration hooks
5. Keep shared graph contracts unchanged while the UI host changes.

Mobile-flexibility posture:

- tablet may support lightweight graph inspection and limited node editing
- phone should likely be review-only for simulations, previews, and run status

Recommended migration order:

1. simulation inspector and preview
2. project loading and state restoration
3. full desktop graph canvas

### `Neurochip`

Current role:

- hardware deployment, firmware generation, target configuration, and runtime packaging

Workbench mode:

- instrument mode

Desktop target:

- native desktop deployment workstation

Why it fits desktop well:

- file workflows
- hardware target configuration
- deployment logs
- firmware and artifact handling

Desktop migration plan:

1. Extract deployment orchestration, hardware capability checks, and artifact generation into shell-safe service layers.
2. Move deployment dashboards, target selectors, artifact browsers, and flash progress surfaces into a native desktop package.
3. Keep Akida, PYNQ, Lava, and serial workflows optional and capability-gated.
4. Expose a `Neurochip_shell_adapter` package with:
   - target capability metadata
   - deploy entry widget
   - artifact/result deep links
   - degradation reporting for unavailable hardware paths
5. Integrate shell-level notifications for long-running deploy jobs and recoverable failures.

Mobile-flexibility posture:

- phone should not be the primary local deployment surface
- mobile later can support deploy monitoring, artifact review, and basic target status

Recommended migration order:

1. artifact browser and deploy status
2. target configuration
3. flash and hardware action surfaces

### `Neurobench`

Current role:

- benchmarking, regression analysis, and report comparison

Workbench mode:

- instrument mode

Desktop target:

- native desktop benchmarking and comparison workstation

Why it fits desktop well:

- report comparison
- tables and charts
- multi-run analysis
- export and review workflows

Desktop migration plan:

1. Extract benchmark job orchestration and report models into reusable controllers.
2. Build desktop-native result comparison surfaces using shared charts and data views from `nmtk_ui_core`.
3. Expose a `Neurobench_shell_adapter` package with:
   - benchmark entry widget
   - report deep links
   - comparison workspace restoration
4. Keep heavy benchmark execution optional and isolated from the UI composition layer.
5. Add shell-managed background job tracking for long-running benchmark runs.

Mobile-flexibility posture:

- tablet can likely support report browsing well
- phone should focus on summary dashboards, result review, and comparison snapshots

Recommended migration order:

1. results summary and report browsing
2. comparison workspace
3. benchmark job setup and execution controls

### `Neurosense`

Current role:

- acquisition, filtering, spike encoding, session recording, and replay

Workbench mode:

- instrument mode

Desktop target:

- native desktop acquisition and replay console

Why it fits desktop well:

- live signal monitoring
- dense parameter controls
- recording and replay workflows
- device setup

Desktop migration plan:

1. Extract acquisition state machines, preset handling, and recording session logic into platform-neutral services.
2. Build a desktop-native monitoring console with:
   - live channels
   - preset/config panels
   - record/replay controls
   - session artifact browser
3. Expose a `Neurosense_shell_adapter` package with:
   - desktop entry widget
   - session deep links
   - device state and replay restoration hooks
4. Keep hardware bridges and simulated acquisition paths behind explicit capability layers.
5. Route session artifacts through stable typed contracts so Neurobench and Neurohub remain decoupled from the UI host.

Mobile-flexibility posture:

- tablet may support replay, session review, and limited live monitoring
- phone should focus on remote monitoring and recorded-session review, not full acquisition setup

Recommended migration order:

1. session browser and replay
2. live monitoring dashboard
3. full acquisition and hardware setup controls

### `Neurohub`

Current role:

- suite dashboard, orchestration, projects, and bundle/workflow coordination

Workbench mode:

- command mode

Desktop target:

- native desktop suite control center

Why it fits desktop well:

- multi-project context
- orchestration state
- bundle review
- cross-module workflow visibility

Desktop migration plan:

1. Separate orchestration state, project metadata, and workflow tracking from UI concerns.
2. Build a desktop-native control-center package for:
   - project browsing
   - workflow launch and monitoring
   - suite status
   - bundle inspection
3. Expose a `Neurohub_shell_adapter` package with:
   - desktop dashboard entry surface
   - project deep links
   - workflow restoration hooks
4. Keep module-specific heavy logic outside Neurohub and continue to use centralized suite-client orchestration contracts.
5. Make Neurohub the primary cross-module handoff and project context surface inside the desktop shell.

Mobile-flexibility posture:

- this is the strongest mobile candidate
- tablet and phone can later support project status, workflow monitoring, approvals, and artifact review

Recommended migration order:

1. project and workflow overview
2. bundle inspection
3. richer orchestration controls

### `Neuro-Dream-Hand`

Current role:

- prosthetic simulation, learning, hardware, and HITL flows

Workbench mode:

- instrument mode

Desktop target:

- native desktop simulation and prosthetic control console

Why it fits desktop well:

- simulation controls
- hardware safety context
- dense experiment setup
- logs and telemetry

Desktop migration plan:

1. Extract simulation, learning, hardware bridge, and session orchestration into platform-neutral services with strict guardrail ownership preserved.
2. Build a desktop-native control console for:
   - experiment setup
   - simulation runs
   - telemetry
   - hardware/HITL status
3. Expose a `neuro_dream_hand_shell_adapter` package with:
   - desktop entry widget
   - scenario deep links
   - guardrail-aware state restoration
4. Keep safety bounds and optional hardware dependencies enforced outside presentation code.
5. Integrate explicit shell-level degraded states for missing MuJoCo, hardware bridges, or optional learning paths.

Mobile-flexibility posture:

- phone should not be a primary control surface for safety-sensitive hardware operation
- mobile later can support telemetry viewing, session review, and alerts

Recommended migration order:

1. telemetry and run review
2. simulation control
3. guarded hardware/HITL control surfaces

## Cross-module sequencing

Recommended implementation order across the suite:

1. `nmtk_ui_core`
2. `nmtk`
3. `Neurohub`
4. `neurocnl`
5. `Neurobench`
6. `Neurosim`
7. `Neurosense`
8. `Neurochip`
9. `Neuro-Dream-Hand`

Rationale:

- build the shell and design primitives first
- migrate the orchestration layer early
- move desktop-friendly knowledge work modules before the more hardware-bound modules
- leave the highest-risk hardware and HITL surfaces until the shell contracts are stable

## Shared milestones for every module

Each module migration should hit the same checkpoints:

1. Define module shell adapter contract.
2. Extract platform-neutral application services.
3. Build native desktop entry surface.
4. Add deep-link and state restoration support.
5. Add capability and degradation reporting.
6. Verify cross-module contracts remain unchanged unless intentionally revised.
7. Confirm what subset can later be reused by tablet or phone.

## Definition of done per module

A module is considered migrated when:

- it opens as a native desktop workspace inside the shell
- it no longer relies on an embedded web frontend for the primary experience
- its contracts remain stable for upstream and downstream consumers
- it supports shell restoration and deep linking
- desktop-specific layout code is separated from reusable feature logic
- its future mobile posture is explicitly documented as:
  - full candidate
  - partial candidate
  - review-only candidate

## Recommended next deliverables

1. A shell adapter interface spec for all modules.
2. A per-module package naming convention document.
3. A desktop migration backlog for each repository.
4. A mobile posture matrix across all modules.
5. A cross-module ADR for native package integration.

The first two deliverables are now covered by the root shell adapter contract
document and ADR above. Future module briefs should link to those files instead
of restating shell semantics locally.
