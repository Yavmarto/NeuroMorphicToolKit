# Desktop UI Modernization And Module Embedding Plan

## Goal

Redesign the current desktop launcher into a coherent, modern workspace application with:

- a top-aligned desktop navigation model instead of a left sidebar
- a better module switching experience
- persistent module views that do not reload every time the user switches
- a true-desktop product direction without forcing repository consolidation

This plan assumes the current accepted architecture remains the starting point:

- native Flutter desktop launcher in `nmtk/neuro_toolkit`
- module registry in `nmtk/neuro_toolkit/assets/modules.json`
- module UIs embedded from local web frontends
- shared design system in `nmtk_ui_core`
- design-contract documentation inspired by `google-labs-code/design.md`
- workstation-oriented product framing informed by the attached `UI_UX_INSPIRATION_ANALYSIS.md` and `UI_UX_REDESIGN_PLAN.md`

## Current Problems

### 1. Desktop navigation feels oversized and low-value

The current desktop scaffold in `nmtk_ui_core/lib/app_theme.dart` uses a wide fixed sidebar:

- expanded width: `256`
- collapsed width: `88`

That makes the shell feel heavier than the content. It takes meaningful space away from module work while not providing enough context, hierarchy, or utility to justify that footprint.

### 2. Workspace tabs look dated

The current module tabs in `nmtk/neuro_toolkit/lib/widgets/module_tab_bar.dart` are:

- flat and boxy
- visually similar to old browser tabs
- weakly integrated with the rest of the shell
- too mechanical for a modern desktop product

### 3. Module switching is conceptually wrong

The current workspace route is `/tool/:moduleId`, and `ToolViewScreen` swaps the active module id while rebuilding the workspace shell around route state. Although the screen keeps a map of `WebViewController`s, the overall experience still behaves like opening pages rather than moving through a persistent workspace.

The user expectation is:

- start a module once
- keep its UI alive
- switch instantly
- return to the exact prior state without a reload flash

### 4. The product still feels like a launcher, not a suite

Today the shell is mainly a module catalog plus embedded views. A better desktop app should feel like:

- one product
- with multiple specialized workspaces
- sharing one design language
- one navigation grammar
- one state model for launch, readiness, errors, and background execution

### 5. The shell does not yet feel like mission control

The attached UI analysis correctly identifies that the suite is closer to:

- Docker Desktop
- Portainer
- JupyterLab
- scientific workstation software

than to a generic Flutter admin app.

That framing is relevant and should be adopted. The shell should present:

- active project context
- current workflow stage
- module and runtime health
- recent events and recoverable failures
- the next useful action

## Product Direction

## Recommended UX model

Move from a launcher-with-tabs model to a desktop workspace model with two top bars:

- Top app bar: global navigation, suite controls, search, settings, status
- Top workspace bar below it: module switching, pinned modules, running state, close actions
- Main area: persistent module canvases
- Background module status: compact indicators, not primary layout blocks

The shell should feel closer to Linear, Notion Calendar, Arc, or modern IDE workspace patterns than to a legacy admin dashboard.

The attached inspiration analysis adds a useful refinement:

- the shell should behave like mission control
- modules should behave like specialized workbenches
- live and analytical views should behave like instrument panels

That three-part framing should guide the redesign.

## Recommended information architecture

Use three levels only:

1. Global navigation
   - Home
   - Workspace
   - Projects
   - Modules
   - System
   - Settings
2. Workspace navigation at the top
   - open/running modules
   - recent modules
   - pinned modules
3. Module-local UI
   - owned by the module frontend itself

This keeps the launcher focused on suite concerns and avoids duplicating module navigation in the shell.

Relevant adjustment from the attached redesign plan:

- `Catalog` should no longer be the primary identity of the shell
- install/discovery should live under `Modules`
- a dedicated `System` surface should exist for Python, ports, runtime health, logs, and repair actions

## UI Redesign Plan

### Design system governance addition

Use the `google-labs-code/design.md` repository as a model for how the suite should document and enforce visual identity.

What is useful from that repo:

- a `DESIGN.md` file combines machine-readable design tokens with human-readable design rationale
- the format is explicit about colors, typography, spacing, rounded values, and component tokens
- the toolchain supports validation and diffing, which is useful for controlling design drift

For NMTK, this should become part of the redesign plan, not a separate design exercise.

Recommended adoption:

- add a root `DESIGN.md` for the suite shell
- describe shell tokens for colors, typography, spacing, shape, elevation, and component patterns
- align `nmtk_ui_core` implementation with those tokens
- treat the markdown rationale as the explanation for how the suite should feel, not just how it should be colored
- use the design contract to keep launcher and module shell surfaces coherent over time

This is especially useful here because the current problem is not only bad component styling. The deeper problem is that the suite lacks a persistent, explicit visual contract.

### Phase 1: Move primary navigation to the top

Remove the current left sidebar as the primary navigation model.

Recommended desktop layout:

- Primary top bar: `56-64px` high
- Secondary workspace bar below it: `44-52px` high
- Optional contextual side panel only when the active screen actually needs it
- Workspace canvas: dominant area, minimum visual interruption

This solves the current problem directly:

- the app reads like a normal desktop product
- the content gets its horizontal space back
- navigation is visible without dominating the layout
- any side panel that remains has to earn its space by holding contextual content, not basic navigation

### Phase 2: Keep module navigation at the top, but redesign it

Replace the current tab strip with one of these patterns:

#### Preferred

A rounded workspace switcher in the second top bar with:

- pill-shaped module chips
- module icon + name
- live status dot
- close action on hover or secondary affordance
- horizontal overflow with good scroll behavior

#### Optional enhancement

Add a command-style quick switcher:

- `Cmd/Ctrl+K` opens module switcher
- search modules by name and status
- jump to running, recent, or installed modules

This immediately makes the product feel more modern without introducing conceptual complexity.

### Phase 3: Introduce a proper desktop visual language

Unify the suite around one shell language in `nmtk_ui_core`:

- one spacing scale
- one radius scale
- one elevation system
- one set of shell surfaces
- one typography direction
- one motion vocabulary for opening, switching, and loading

The attached redesign plan also suggests a useful suite-level visual taxonomy:

- command mode for the shell and NeuroHub
- studio mode for neurocnl and Neurosim
- instrument mode for Neurosense, Neurochip, and the data-heavy parts of Neurobench

That idea is relevant and should be carried into `DESIGN.md` and `nmtk_ui_core`, while still preserving one product family.

Recommended shell characteristics:

- softer geometry, not square tabs and hard dividers everywhere
- stronger surface layering
- quieter default chrome
- more intentional use of accent color
- status expressed with badges and dots instead of full-width banners where possible

The module UIs can keep some identity, but the suite shell should clearly come from one product family.

This phase should produce two artifacts in parallel:

- implementation tokens and widgets in `nmtk_ui_core`
- a suite-level `DESIGN.md` that describes the intended identity in a structured way

That combination is stronger than theme code alone because it gives both engineers and coding agents a stable design contract.

### Phase 4: Treat the workspace as the core screen

The workspace should become the centerpiece of the app, not a secondary route.

Recommended workspace regions:

- top app bar: global suite navigation and shell controls
- module switcher row under the app bar: rounded chips or segmented cards
- content area: persistent module canvases
- utility drawer: logs, launch diagnostics, readiness, background jobs

This gives the user a sense that modules are active workspaces, not disposable pages.

The attached redesign plan is also right that the shell needs more explicit operational surfaces. In the desktop rewrite, the shell should include:

- a mission-control home
- module detail pages
- a workspace manager/index
- a system diagnostics view

## Module Reload Fix

## Required behavior

When a module is started and its UI has loaded once:

- switching away must not destroy the view
- switching back must restore the existing live view
- the module should reload only when the user explicitly refreshes, restarts the module, or the backend becomes unavailable

## Root cause to address

The code already tries to cache `WebViewController`s per module inside `ToolViewScreen`, but the launcher still models the workspace around route changes and active module ids instead of a persistent session host.

The fix should not be "cache a little harder". The fix should be architectural:

- separate workspace session lifetime from route lifetime
- keep module canvases mounted
- switch visibility, not instance ownership

## Implementation plan

### Step 1: Introduce a persistent workspace session layer

Create a shell-owned session model, for example:

- `WorkspaceSession`
- `WorkspaceCanvasState`
- `ModuleViewSession`

Each session should own:

- module id
- resolved URL
- readiness state
- webview controller or canvas handle
- last active timestamp
- recoverable error state
- explicit refresh token

This state should live above the route widget so route changes do not rebuild the session.

### Step 2: Replace route-per-module with a stable workspace route

Move from:

- `/tool/:moduleId`

To something conceptually closer to:

- `/workspace`

Then manage active module selection inside workspace state, not through route replacement.

That change matters because it turns module switching into in-workspace state, not navigation churn.

### Step 3: Keep canvases alive instead of reloading them

Inside the workspace screen:

- maintain one mounted view per running or opened module
- show only the active canvas
- hide inactive canvases with an indexed stack, visibility layer, or platform-specific kept-alive host

The important rule is:

- inactive modules stay resident unless memory pressure or explicit user action closes them

### Step 4: Add explicit lifecycle rules

Define clear shell behavior:

- `Open module`: create session if missing
- `Switch module`: activate existing session
- `Close module tab/chip`: dispose session only if user closes it
- `Restart module`: keep shell session, recreate underlying view intentionally
- `Backend crash`: show degraded overlay on the existing canvas instead of silently rebuilding

### Step 5: Add persistence for workspace recovery

Store lightweight session metadata:

- open modules
- active module
- pinned modules
- last selected workspace

On app relaunch:

- restore workspace layout
- reconnect to running modules when possible
- show clear recovery states when not possible

## Startup latency and warm-session UX

The desktop migration must explicitly distinguish between:

1. workspace switching latency
2. first-render UI latency
3. backend or runtime startup latency

These are not the same problem and should not be solved with one generic loading spinner.

### What the desktop rewrite should eliminate

The true-desktop workspace host should eliminate repeated reloads when the user switches between already-open modules.

Target behavior:

- switching back to an open module should be instant or near-instant
- the shell should preserve the module view state
- the shell should preserve the module workspace chrome even if the backend is still warming or reconnecting

This is primarily a shell architecture responsibility.

### What the desktop rewrite will not fix by itself

Even with a native desktop workspace, first open can still be slow because of:

- Python environment startup
- backend process startup
- health and readiness probing
- hardware capability checks
- model loading
- artifact indexing
- large chart or canvas initialization

This is primarily a backend, runtime, and initialization performance responsibility.

### Required UX model for slow first open

If a module can take several seconds to become fully usable, the desktop app should not show that as a blank page or a reload loop.

Instead, it should:

- open the workspace shell immediately
- show module identity and context immediately
- show staged readiness states inside the workspace
- preserve that workspace while services warm up
- allow the user to switch away and back without restarting the experience

### Required readiness states

Every module should support a shell-visible readiness lifecycle:

1. `opening`
2. `warming_up`
3. `ready`
4. `degraded`
5. `error`

Optional extended states:

1. `probing_hardware`
2. `indexing_assets`
3. `loading_model`
4. `restoring_session`

These states should be backed by typed contracts, not ad-hoc text strings.

### Performance strategy

The migration should include explicit work for:

1. warm-session persistence
   - keep opened modules alive until closed
2. staged rendering
   - render shell and module chrome before heavy content
3. background prewarming
   - optionally prewarm likely-next modules
4. lazy heavy panels
   - defer non-critical inspectors, charts, and logs until needed
5. backend startup profiling
   - measure which parts of first open are frontend versus runtime cost

### Measurement requirement

Each migrated module should track at least:

- time to shell visible
- time to first interactive state
- time to fully ready state
- reopen time from warm session

This should become part of the migration verification, not an afterthought.

## Target Architecture: One True Desktop Suite While Keeping Repos Separate

Description:

- one Flutter desktop shell
- shared design system and shell SDK
- modules progressively expose native Flutter screens, package entrypoints, or desktop-first adapters
- repositories stay separate

Ease: Medium  
Risk: Medium  
Rewrite cost: Medium to high

This is now the target direction for the redesign.

The key is to keep repository separation while changing the integration contract.

Recommended contract model:

- each module keeps its own repo
- each module exposes a stable package or shell adapter
- the shell consumes versioned packages or path dependencies during local development
- backend APIs remain owned by the module

This gives one desktop product without merging all source code into one repository.

## Flutter modules vs Flutter packages

For this codebase, prefer Flutter packages and package-based adapters over Flutter modules.

Why:

- Flutter modules are mainly for embedding Flutter into native host apps
- your shell is already Flutter
- package composition is cleaner for Flutter-to-Flutter integration
- packages preserve repo separation better
- shared shell SDKs, design tokens, and workspace adapters fit naturally as packages

Recommended stack:

- `nmtk_ui_core` for shared design system
- `nmtk_shell_sdk` for shell contracts and workspace APIs
- per-module adapter package such as `neurocnl_shell_adapter`
- optional module-native package later if a module is ported from web to desktop-native Flutter

This means the long-term plan is not "keep embedding everything forever." The plan is:

- use the current launcher only as the bridge state
- progressively move high-value modules to true desktop surfaces
- keep shell ownership and repository ownership separate through versioned package contracts

## Recommended Long-Term Architecture

Use a three-layer model:

### Layer 1: Shell

Owned by `nmtk`

Responsibilities:

- install
- launch
- health
- diagnostics
- workspace session management
- global navigation
- shell theme and design language

### Layer 2: Shared suite packages

Owned centrally, still reusable across repos

Recommended packages:

- `nmtk_ui_core`
- `nmtk_shell_sdk`
- optional `nmtk_workspace_components`
- optional design-contract tooling around a root `DESIGN.md`

Responsibilities:

- design tokens
- shell surfaces
- shared workspace widgets
- host-module communication contracts
- design-contract validation and controlled evolution of the suite identity

### Layer 3: Module adapters and native module packages

Owned by each module repo

Responsibilities:

- declare shell capabilities
- provide module metadata
- expose native Flutter entry widgets where a module is ready
- provide deep-link and startup contracts
- map module health and readiness into shell-friendly states

This allows progressive migration rather than a risky rewrite.

## Migration Roadmap

## Track 1: Shell restructure

Target: fix what users feel first.

1. Remove the left navigation sidebar as the primary app navigation.
2. Add a top app bar for global navigation and suite controls.
3. Keep module navigation at the top in a second bar with rounded workspace chips.
4. Move from `/tool/:moduleId` to a stable `/workspace` route.
5. Introduce persistent workspace sessions that keep module views mounted.
6. Add explicit manual refresh and restart actions so reloads are intentional.

Expected difficulty: Moderate  
Expected impact: Very high

## Track 2: Shared shell design system

Target: make the suite look like one product.

1. Extend `nmtk_ui_core` with shell-specific primitives.
2. Define suite-level spacing, corner radius, typography, motion, and status tokens.
3. Add a root `DESIGN.md` modeled on the `google-labs-code/design.md` approach so the suite has a structured visual identity file.
4. Standardize launcher cards, headers, diagnostics, badges, and workspace controls.
5. Publish a shell UI guideline for all module frontends.

Expected difficulty: Moderate  
Expected impact: High

## Track 3: Better module-shell contracts

Target: reduce integration friction and improve reliability.

1. Add explicit frontend readiness contracts beyond simple `/health`.
2. Add shell-visible capability metadata for each module.
3. Add module deep-link support for workspace restoration.
4. Add state recovery overlays instead of blank reloads.

Expected difficulty: Moderate  
Expected impact: High

## Track 4: Progressive native unification

Target: make one true desktop suite possible over time.

1. Keep the current launcher functioning while the migration starts.
2. Introduce `nmtk_shell_sdk` contracts.
3. Pilot one module as a package-based desktop-native surface.
4. Compare:
   - startup time
   - memory
   - keyboard integration
   - file handling
   - perceived quality
5. Decide module-by-module whether to stay temporarily web-embedded or move native next.

Expected difficulty: High  
Expected impact: Strategic

## Recommendation Summary

The best plan is:

1. Move primary app navigation from the left side to a normal desktop-style top bar.
2. Keep module navigation at the top as a second, dedicated workspace bar.
3. Fix the switching problem by introducing persistent workspace sessions and a stable `/workspace` route.
4. Treat one true desktop suite as the target architecture.
5. Keep repositories separate through Flutter packages and shell adapters, not through nested desktop apps.
6. Standardize suite visuals in `nmtk_ui_core` and formalize them in a root `DESIGN.md`.
7. Use the `google-labs-code/design.md` model as the reference for design-token structure, rationale sections, and future lint or diff workflows.

## Success Criteria

The redesign is successful when:

- the desktop shell uses materially less horizontal chrome
- navigation feels intentional rather than oversized
- module switching is instant and stateful
- returning to a module does not trigger a visible reload
- the suite looks like one product family
- modules can still be developed in separate repositories
- the shell has a credible migration path toward deeper native integration later

## Proposed follow-up deliverables

After this plan, the next useful artifacts would be:

1. a desktop shell wireframe set
2. a launcher workspace state ADR
3. a shell-session technical design for persistent module canvases
4. a top-navigation desktop shell spec
5. a first-pass root `DESIGN.md` for the NMTK suite
6. a repo-separation migration note for package-based module adapters
