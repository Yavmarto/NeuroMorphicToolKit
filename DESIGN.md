# NMTK Suite Design

## Purpose

This file is the design contract for the NeuroMorphicToolKit desktop suite.

It exists to keep the launcher, shared UI core, and future module-native desktop surfaces aligned around one coherent product identity.

This file should guide:

- shell layout decisions
- `nmtk_ui_core` token and component design
- module adapter chrome
- future desktop-native module surfaces

This file is intentionally desktop-first.

## Contract status

`DESIGN.md` is the canonical suite-shell design contract for the desktop
rewrite.

When this file conflicts with exploratory or execution-oriented language in
other root docs, this file wins for:

- shell layout and chrome ownership
- mode semantics
- readiness and degraded/error language
- desktop-first and mobile-portable rules
- shell-visible status and utility-panel behavior

## Product intent

NMTK should feel like one professional desktop suite for technical work, not like a launcher wrapping unrelated apps.

The design language should feel:

- focused
- calm
- precise
- high-density without looking cramped
- modern without looking decorative

The interface should prioritize:

- content space
- state clarity
- workflow continuity
- low-friction switching between workspaces

The suite should be designed as:

- a shell that behaves like mission control
- modules that behave like specialized workbenches
- live and analytical surfaces that behave like instrument panels

## Layout principles

### 1. Global navigation belongs at the top

The suite should use a normal desktop-style top navigation bar.

Do not use a left sidebar as the primary app navigation pattern.

The top app bar is for:

- Home
- Projects
- Modules
- Workspace
- System
- Search
- Settings
- suite-level status and actions

`Catalog` should not remain the primary identity of the shell. Discovery and install flows belong under `Modules`.

### 2. Module navigation also stays at the top

Module switching should remain visible at the top, below the global app bar.

This second bar is for:

- open modules
- pinned modules
- running status
- close actions
- fast switching between active workspaces

This bar should not look like legacy square tabs.

The two top bars should remain distinct.

The top app bar owns:

- global destinations
- search
- suite-level status
- suite-wide actions
- settings and operator controls

The top workspace bar owns:

- open and pinned modules
- active workspace switching
- module running state
- close and restore affordances

### 3. The content canvas must dominate

The module workspace should own most of the screen.

Chrome should be compact and intentional.

Side panels are allowed only when they hold contextual tools such as:

- logs
- diagnostics
- project context
- inspector panels

They should not exist just to hold basic navigation.

## Shell structure

The default desktop shell should have:

1. Top app bar
2. Top workspace switcher bar
3. Main workspace canvas
4. Optional contextual utility panel

The utility panel is contextual support chrome, not a second navigation system.

It may contain:

- logs
- diagnostics
- background jobs
- contextual inspectors
- degraded-state detail
- recovery actions

It should not contain:

- primary app navigation
- duplicate module-local navigation
- shell destinations already present in the top app bar

Primary shell destinations should be:

1. Home
2. Projects
3. Modules
4. Workspaces
5. System
6. Settings

## Visual direction

### Tone

- neutral, technical, and mature
- not playful
- not dashboard-heavy
- not visually noisy

### Suite modes

The suite should share one family identity, but it should support three operating modes:

- command mode
- studio mode
- instrument mode

These are not separate brands. They are controlled variations within one suite.

The current migration uses this fixed mode mapping:

- command mode: shell chrome and `Neurohub`
- studio mode: `neurocnl` and `Neurosim`
- instrument mode: `Neurosense`, `Neurochip`, `Neurobench`, and
  `Neuro-Dream-Hand`

#### Command mode

Used for:

- shell chrome
- NeuroHub
- operational overviews

Characteristics:

- structured
- clear status hierarchy
- strong operational clarity

#### Studio mode

Used for:

- neurocnl
- Neurosim

Characteristics:

- editor and canvas first
- persistent inspectors
- stronger pane framing

#### Instrument mode

Used for:

- Neurosense
- Neurochip
- data-heavy Neurobench surfaces

Characteristics:

- high information density
- clear live state semantics
- charts, traces, logs, and measurement-oriented layouts

### Shape

- rounded, but not soft to the point of looking mobile-first
- prefer medium radii over sharp corners or oversized pills everywhere
- module chips may use fuller rounding than cards and panels

### Surfaces

- layered surfaces with clear hierarchy
- subtle contrast between app frame, bars, panels, and canvases
- avoid heavy borders as the main way to separate regions

### Motion

- quick and quiet
- transitions should reinforce continuity
- switching modules should feel instant and persistent, not like opening a new page

## Workspace switching

The module switcher should be:

- top-aligned
- horizontally scrollable when needed
- keyboard navigable
- visually compact
- stateful

Recommended module chip contents:

- module icon
- module name
- status dot
- close affordance

Optional states:

- active
- idle
- starting
- degraded
- error
- pinned

## Desktop behavior requirements

The desktop shell should preserve continuity.

When a module is opened:

- its view should remain alive until explicitly closed or restarted
- switching away should not destroy the view
- switching back should restore the same view state

This continuity is part of the design. It is not only an engineering concern.

The shell should also distinguish between:

- first open latency
- backend warming latency
- warm-session switching

Switching between already-open modules should not feel like startup.

## Desktop-first, mobile-portable rules

The suite shell is desktop-first. Future mobile work should reuse contracts and
state models where practical, but mobile should not force the desktop shell to
adopt mobile-first layout or interaction assumptions.

Required rules:

- Keep shell, module, and workflow state machines independent from desktop
  widget trees where practical.
- Keep business logic, readiness contracts, and capability reporting portable
  across hosts.
- Treat mobile as a future composition target, not the optimization target for
  shell chrome.
- Hardware-heavy workflows may degrade on mobile to monitoring, review, setup,
  or companion flows instead of full local control.
- Dense authoring, deployment, and live instrument surfaces may remain
  desktop-primary even when lighter mobile views exist later.

## Readiness model

Long startup should be represented as staged readiness, not as a blank or resetting UI.

Required shell-visible states:

- opening
- warming up
- ready
- degraded
- error

Optional module-specific readiness states:

- probing hardware
- restoring session
- indexing assets
- loading model

The user should see the module shell immediately, even if the deepest feature surface is still warming.

These shell-visible states are normative. Implementations may map them to typed
enum values or transport names such as `warming_up`, but operator-facing
wording should preserve the meanings above.

## Status language

Shell-visible status language must be short, stable, and operationally honest.

Required distinctions:

- `preflight failed`: a required dependency, manifest, runtime, or startup
  condition is blocking normal operation
- `degraded optional capability`: the suite or module can still run, but an
  optional runtime, hardware path, or advanced feature is unavailable
- `degraded`: the module or workspace is available with reduced function,
  impaired connectivity, or a recoverable runtime problem
- `error`: the current workflow cannot continue without intervention or restart

Rules:

- Do not collapse `preflight failed` and `degraded optional capability` into
  the same user-facing label.
- Prefer actionable language over generic failure wording.
- Keep degraded messaging tied to the affected capability or workflow.
- Show recovery actions in-place when the shell can offer them.

## Typography

Typography should support dense technical workflows.

Guidance:

- prefer clean sans-serif UI typography for shell chrome
- use stronger contrast between navigation labels, headings, and metadata
- do not rely on oversized type to create hierarchy
- technical metadata should remain readable at compact sizes

## Color guidance

The suite should use a restrained palette.

Guidance:

- neutrals should carry most of the interface
- accent color should guide attention, not flood the shell
- status colors should be clear and stable
- avoid loud gradients or highly saturated default surfaces in the shell

Module content may introduce its own accents, but shell chrome should stay suite-consistent.

State color should communicate:

- healthy
- running
- degraded
- warning
- error
- live/recording/connected

## Token scaffold

These are starting token groups. They can later be expanded into a more formal schema for tooling.

```yaml
theme:
  mode: "desktop"
  intent: "technical_suite"

layout:
  top_app_bar_height: 60
  workspace_bar_height: 48
  utility_panel_width: 320
  content_maximize_priority: true

shape:
  radius_xs: 8
  radius_sm: 12
  radius_md: 16
  radius_lg: 22
  radius_chip: 999

motion:
  fast_ms: 120
  standard_ms: 180
  emphasized_ms: 240

navigation:
  primary_position: "top"
  workspace_position: "top_secondary"
  left_sidebar_primary_nav: false

workspace:
  persistent_module_views: true
  route_model: "/workspace"
  allow_instant_switching: true

shell:
  primary_destinations:
    - "Home"
    - "Projects"
    - "Modules"
    - "Workspaces"
    - "System"
    - "Settings"
  product_framing: "mission_control"
  utility_panel_role: "contextual_support_only"
  status_language:
    preflight_blocker: "preflight failed"
    optional_capability: "degraded optional capability"

mode_variants:
  command: true
  studio: true
  instrument: true
  assignments:
    command:
      - "shell"
      - "Neurohub"
    studio:
      - "neurocnl"
      - "Neurosim"
    instrument:
      - "Neurosense"
      - "Neurochip"
      - "Neurobench"
      - "Neuro-Dream-Hand"
```

## Component priorities

The first components that should align with this design contract are:

1. desktop top app bar
2. module workspace switcher
3. workspace header
4. shell status badges
5. utility panel shell
6. empty, loading, degraded, and recovery states

## Implementation mapping

This design contract should map to code as follows:

- shell tokens and shared widgets: `nmtk_ui_core`
- desktop shell and workspace state: `nmtk/neuro_toolkit`
- future shell integration contracts: `nmtk_shell_sdk`

## Near-term decisions

For the current redesign effort:

1. Move the primary navigation from the left side to the top.
2. Keep module navigation at the top in a second bar.
3. Replace square module tabs with rounded workspace chips.
4. Move the workspace to a stable `/workspace` route.
5. Keep module views persistent across switching.
6. Use this file as the reference when updating `nmtk_ui_core`.

## Open areas to define next

- concrete color tokens
- typography scale
- elevation scale
- spacing scale
- workspace chip interaction states
- iconography rules
