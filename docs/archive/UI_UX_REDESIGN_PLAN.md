# NeuroMorphicToolkit UI/UX Redesign Plan

Date: 2026-04-24

## Goal

Turn NeuroMorphicToolkit from a collection of functional Flutter screens into a coherent scientific workstation suite.

This plan is intentionally concrete. It is not a moodboard. It defines:

- the new product framing
- the information architecture
- the shell redesign
- the redesign direction for each module
- the shared design system changes
- the implementation order

## Product Framing

The suite should be positioned and designed as:

**A neuromorphic engineering workstation with specialized labs**

Not:

- a generic app store
- a CRUD admin panel
- a tab wrapper around embedded web apps

That means the product should consistently express four things:

1. **Active project context**
2. **Current workflow stage**
3. **System/module health**
4. **Immediate next action**

## The New UX Model

The suite should use a three-layer UX model.

### Layer 1: Shell

The shell is the command center.

Responsibilities:

- install/manage modules
- show system health
- show active workspaces
- show recent runs/logs/events
- route users into the correct module with preserved context

Reference shape:

- Docker Desktop
- Portainer
- JupyterLab

### Layer 2: Workbench

Each module is a specialized workbench.

Responsibilities:

- one primary task surface
- persistent inspectors and context panels
- explicit workflow progress
- easy switching between authoring, execution, and results

Reference shape:

- JupyterLab
- Node-RED
- KNIME
- Postman

### Layer 3: Instrument Panels

Live and analytical views should look like technical instruments, not like oversized forms.

Responsibilities:

- charts, traces, logs, comparisons
- live states
- warnings and degraded states
- dense but scannable information

Reference shape:

- OpenBCI GUI
- OpenSignals
- Grafana
- LabVIEW

## Information Architecture

## Top-level shell IA

Replace the current `Dashboard / Catalog / Workspace` framing with:

1. **Home**
   Mission control overview.

2. **Projects**
   Active projects, recent work, pinned runs.

3. **Modules**
   Installed, available, unhealthy, updating.

4. **Workspaces**
   Open module sessions and active tasks.

5. **System**
   Python, dependencies, ports, runtime health, logs.

`Catalog` can remain as a subsection inside `Modules`, not as a top-level identity.

## Core shell layout

Desktop layout should become:

- left rail for global navigation
- center main content region
- right utility drawer for health/logs/activity/context
- top command bar for project selector, search, quick actions, global status

This is a major improvement over the current simple route shell because it gives the suite persistent operational context.

## Shared Design System Changes

The current tokens are not the main problem, but the system needs clearer behavioral rules.

## Design family

Use one family with three modes:

1. **Command mode**
   For shell and NeuroHub.
   Clean, structured, operational.

2. **Studio mode**
   For neurocnl and NeuroSim.
   Dark, paneled, editor/canvas-first.

3. **Instrument mode**
   For NeuroSense, NeuroChip, and heavy data sections of NeuroBench.
   High contrast, status-forward, chart-heavy.

## Typography

Current typography is inconsistent and not strong enough.

Recommendation:

- Use one expressive family for branding/headings.
- Use one highly legible family for data and UI.
- Use a real monospaced family for code, logs, and numeric panels.

Suggested stack:

- Heading/UI: `Space Grotesk` or `Sora`
- Dense data/code: `IBM Plex Mono` or `JetBrains Mono`

Do not rely on default Material feel across modules.

## Color semantics

Current palette use is too aesthetic and not operational enough.

Define semantic layers:

- `neutral`: surfaces, panes, dividers
- `accent`: module identity / selection
- `success`: valid/running/healthy
- `warning`: degraded/pending/requires attention
- `error`: failed/broken/disconnected
- `live`: streaming/recording/connected

Color should indicate state first, branding second.

## Component rules

Adopt these rules across the suite:

- Cards are for summaries, not for primary technical work.
- Main work surfaces should use panes, inspectors, split views, and tables.
- Logs, traces, and comparisons should be first-class widgets.
- Every long-running action needs a visible lifecycle:
  queued, running, partial, success, warning, failed.
- Every module should expose "last run", "active target", and "warnings" without forcing navigation.

## Redesign By Product Area

## 1. NMTK Shell Redesign

## Current problems

- Feels like a basic launcher.
- Dashboard is just a list of installed modules.
- Catalog is a flat install screen.
- Workspace is just tabbed webviews.
- Runtime/system state is buried or absent.

## New structure

### Home

Home should become mission control.

Sections:

- **Continue Working**
  Recent projects, recent module sessions, open workspaces.

- **System Status**
  Python status, running services, unhealthy modules, storage/dependencies.

- **Pipeline Snapshot**
  Show where active projects currently are:
  design, simulate, encode, deploy, benchmark.

- **Recent Activity**
  Installs, runs, failed launches, benchmark completions, exports.

### Modules

Replace the current catalog list with module detail pages.

Each module should have:

- summary
- purpose
- install status
- runtime status
- dependencies
- health
- entry actions
- recent outputs

Module cards should open into module profiles, not just present an install button.

### Workspaces

This should feel like a real session manager.

For each open workspace:

- module name
- project context
- current task
- runtime status
- last event
- open / focus / stop / reopen actions

Tabs alone are not enough. Add a workspace index view.

### System

Add a dedicated operational page:

- Python detection/version
- venv/module environments
- ports in use
- failed bootstraps
- logs
- repair actions

This will reduce the "mysterious desktop wrapper" feeling.

## Shell implementation priority

1. Add top app bar with:
   project switcher, global search, quick launch, system badge
2. Convert current dashboard into mission-control overview
3. Add module detail pages
4. Add workspace manager screen
5. Add system diagnostics page

## 2. neurocnl Redesign

## Current problems

- Strong underlying workflow, but UI is still screen-oriented.
- Results are hidden behind generic tabs.
- Analysis/deploy surfaces are separated too bluntly.
- Editor context is not persistent enough.
- Visual language is decent but still generic.

## New interaction model

`neurocnl` should become an editor-first studio.

### Primary layout

Desktop:

- left sidebar: templates, project files, presets
- center: editor + optional split network view
- right inspector: parse/validation issues, selected entity, parameters
- bottom panel: simulation, logs, export preview, backend output
- top pipeline ribbon: parse -> validate -> generate -> simulate -> deploy

This is closer to IDEs and JupyterLab than to a form-plus-tabs app.

### Main modes

Do not make these top-level screens that feel disconnected. Keep them as workbench modes:

- **Author**
- **Analyze**
- **Deploy**

Within one studio shell.

### Author mode

Contains:

- CNL editor
- template browser
- inline grammar help
- parse diagnostics
- parameter explorer

### Analyze mode

Contains:

- network graph
- spike rasters
- membrane traces
- quantitative summaries
- energy / quantization / fault views

### Deploy mode

Contains:

- target config
- export previews
- simulation-to-hardware handoff
- deployment history

## Concrete UX changes

- Keep pipeline ribbon always visible.
- Move validation from passive tab to persistent issue panel.
- Let graph and simulation open as bottom or side panes.
- Add a "compare runs" view for parameter changes.
- Add reusable workspace presets:
  writing, debugging, simulation, export.

## Implementation priority

1. Convert current results tabs into dockable panes
2. Add persistent issues/inspector panel
3. Collapse analysis/deploy into one studio shell
4. Add run history and diff view
5. Add saved workspace layouts

## 3. NeuroSim Redesign

## Current problems

- The structure is correct, but visually too raw.
- Preview results feel bolted on.
- Inspector/property panel is basic.
- The canvas system lacks a strong workflow grammar.

## New interaction model

NeuroSim should feel like a visual network authoring IDE.

### Primary layout

- left: searchable component library with categories and starter circuits
- center: canvas
- right: contextual inspector
- bottom: validation / preview / generated CNL / execution messages
- top: run controls, graph health, zoom/layout tools, template picker

### Key UX upgrades

- Stronger node states:
  valid, warning, error, selected, dirty, simulated
- Better edge semantics:
  excitatory, inhibitory, delayed, learned
- Better graph tooling:
  auto-layout, align, group, collapse subgraph
- Better preview structure:
  preview should live in a bottom results dock, not a temporary attached panel

### New views

- **Canvas**
- **Generated CNL**
- **Simulation Preview**
- **Sweep Results**

These should share one workbench, not separate the user too far from the canvas.

## Implementation priority

1. Replace attached preview strip with bottom results dock
2. Improve inspector into full contextual property system
3. Add graph-state visual grammar
4. Add auto-layout and group/subgraph features
5. Add multi-result sweep comparison

## 4. NeuroSense Redesign

## Current problems

- Current UI is pale and generic.
- Too much vertical card stacking.
- Live streaming state is visually weak.
- Device, quality, recording, and encoding are not composed like one instrument workflow.

## New interaction model

NeuroSense should feel like a recording and signal-analysis instrument.

### Primary layout

- left rail: setup, acquisition, sessions, replay
- top control strip: connected device, stream state, sample rate, recording state
- center main region: large waveform/chart area
- right side panel: encoding settings, quality metrics, markers, notes
- bottom bar: transport controls, session timer, dropped frames, warnings

### Acquisition screen redesign

Current card stack should become a real console:

- top device strip
- middle waveform area dominating the page
- right encoding/quality tools
- bottom recording transport

### Key UX upgrades

- High-contrast chart-first surface
- Strong live indicators:
  connected, streaming, recording, clipping, noisy, disconnected
- Per-channel quality badges
- Marker/event lane
- Split raw vs filtered vs spike-encoded views

### Sessions

Session browser should become a real analysis/replay tool, not just a list:

- sessions table
- metadata filters
- preview mini-trace
- reopen in replay mode

## Implementation priority

1. Rebuild acquisition as chart-first console
2. Add persistent live status strip
3. Add marker/event lane
4. Add session browser with preview/replay-first UX
5. Improve encoding side panel and preset switching

## 5. NeuroChip Redesign

## Current problems

- Current layout is fragmented across generic pages.
- Hardware target context is weak.
- Deployment lifecycle is not strong enough in the UI.
- Comparison and history feel like basic screens rather than a deployment workflow.

## New interaction model

NeuroChip should feel like a hardware deployment cockpit.

### Primary layout

- left rail: targets, analysis, compare, deploy, history
- top bar: active target, active profile, compatibility state
- center content: current task surface
- right utility: constraints, warnings, memory usage, estimated latency/power
- bottom/log area: compile/flash/output logs

### Task surfaces

#### Target gallery

Turn this into a target browser with richer cards:

- hardware image/icon
- capabilities
- limits
- supported exports
- common use cases
- compatibility summary for current network

#### Analysis

Use a split analytical layout:

- center charts/tables
- right target facts and warnings

#### Deploy

Use a staged deployment flow:

- compile
- validate
- flash
- verify

Each stage should show status, duration, and output.

#### History

Use a proper run/deployment timeline rather than a plain page.

## Implementation priority

1. Add persistent active-target chrome
2. Add staged deployment flow UI
3. Add bottom log console
4. Upgrade target gallery into rich compatibility browser
5. Add history timeline with diff against previous deployments

## 6. NeuroBench Redesign

## Current problems

- Too skeletal.
- Benchmarking is conceptually strong, but UI currently behaves like a selected-item detail page.
- Lacks run-centric mental model.

## New interaction model

NeuroBench should feel like an experiment tracking and evaluation lab.

### Primary layout

- left: benchmark catalog, filters, saved views
- center: run table / result explorer
- right: selected run summary or benchmark config
- bottom: charts, diffs, robustness curves, artifacts

### Core objects

Elevate these to first-class UI entities:

- benchmark definitions
- runs
- baselines
- comparisons
- reports

### Main views

- **Catalog**
- **Runs**
- **Compare**
- **Robustness**
- **Reports**

### Key UX upgrades

- run table with filtering/grouping
- baseline pinning
- diff-only comparison
- saved comparison views
- artifact/report browser

This should borrow heavily from W&B and MLflow, not from a typical admin dashboard.

## Implementation priority

1. Build runs table as primary center surface
2. Add baseline/diff workflow
3. Add compare view with side-by-side metrics
4. Add robustness curves and saved views
5. Add report builder/export browser

## 7. NeuroHub Redesign

## Current problems

- Concept is strong, but current UI is very dashboard-template-like.
- Project management dominates over orchestration.
- Live test and workflow editor are underexpressed.

## New interaction model

NeuroHub should be the executive and orchestration view across the suite.

### Primary layout

- left rail: overview, projects, workflows, assets, live test, settings
- top strip: suite health, active workflow runs, notifications
- center: dashboard/project/workflow surfaces
- right: activity feed or contextual project info

### Dashboard

Home dashboard should show:

- suite health by module
- active project states
- current workflow runs
- blocked/failed items
- recent benchmark wins/regressions
- recent deployments

### Project detail

Project detail should be a dashboard, not a document page.

Sections:

- project summary
- lifecycle/milestone timeline
- linked assets across modules
- latest runs and deployments
- active issues/warnings
- notes and team activity

### Workflow editor

This should borrow from Node-RED/KNIME:

- step cards
- drag/reorder
- step config inspector
- status output
- reusable templates

### Live test

Live test should be a real monitoring surface:

- live input stream
- active network
- output stream
- end-to-end latency
- connection health

## Implementation priority

1. Redesign dashboard into suite command center
2. Redesign project detail into operational project dashboard
3. Build real workflow editor
4. Build live test dashboard
5. Add asset library with richer browse/filter/version UI

## Cross-Suite UX Rules

These rules should apply everywhere.

## Rule 1: One primary surface per module

Every module must have a dominant working surface:

- editor
- canvas
- waveform
- run table
- dashboard

If everything is visually equal, nothing feels important.

## Rule 2: Persistent context

Always show at least:

- active project
- active target/device
- current run state
- warnings/errors

## Rule 3: Long-running jobs must be observable

Any install, simulation, flash, benchmark, export, or workflow run needs:

- status
- progress
- logs
- result link
- retry action

## Rule 4: Technical surfaces should be denser

Reduce oversized cards and excessive white space in technical modules.

Increase:

- split panes
- tables
- traces
- compact summaries
- inspectors

## Rule 5: Screen count should go down

The current suite is over-separated into screens.

Prefer:

- one strong workbench with modes/panes

Over:

- many disconnected pages

## Proposed Implementation Roadmap

## Phase 1: Shell and design system foundation

Deliverables:

- new shell navigation
- top command bar
- workspace manager
- system diagnostics page
- updated tokens for command/studio/instrument modes
- shared components for:
  health badges, run states, logs, split panes, inspectors, dock panels

Why first:

Without this, each module redesign will still feel disconnected.

## Phase 2: neurocnl and NeuroSim

Deliverables:

- editor-first studio shell for neurocnl
- docked result panes
- improved simulation/run history
- graph-workbench redesign for NeuroSim
- bottom result dock and richer inspector

Why second:

These are the clearest core authoring tools and set the tone for the suite.

## Phase 3: NeuroSense and NeuroChip

Deliverables:

- instrument-grade acquisition console
- session browser/replay UX
- hardware deployment cockpit
- bottom log console and staged deploy flow

Why third:

These benefit most from the shared instrument mode patterns.

## Phase 4: NeuroBench and NeuroHub

Deliverables:

- run-centric benchmark lab
- suite command center dashboard
- workflow editor
- live test dashboard

Why fourth:

These depend on the identity and shared patterns established earlier.

## Suggested Immediate Backlog

If you want a practical starting backlog, do these next:

1. Redesign the main NMTK shell into `Home / Projects / Modules / Workspaces / System`
2. Add a top command bar with project switcher, search, and global status
3. Build shared split-pane and bottom-dock components in `nmtk_ui_core`
4. Refactor `neurocnl` into a single studio shell with docked panes
5. Refactor `NeuroSense` into a chart-first acquisition console

That sequence will produce visible improvement fastest.

## What Success Looks Like

The redesign is successful when:

- the shell feels like mission control, not a launcher list
- each module feels like a specialized technical workstation
- users can always tell project, status, next step, and health at a glance
- results, logs, and comparisons are first-class
- the suite feels coherent without making every module visually identical

## Final Recommendation

Do not start by "making it prettier."

Start by changing the UI architecture:

- persistent context
- stronger workbenches
- better operational visibility
- fewer disconnected screens
- clearer workflow progression

If you do that well, the visual design work will finally have something solid to sit on.
