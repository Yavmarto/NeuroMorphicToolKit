# Multi-Agent Desktop Migration Execution Map

## Purpose

This document converts the desktop migration plans into an execution model for parallel agent work.

It is designed for a mixed setup where:

- some agents have full local workspace access across the whole suite
- some agents, such as Jules by Google, only have access to one repository at a time in the cloud
- the user wants to keep making progress on Akida or PYNQ Z2 work in parallel

## Short answer

Yes, the migration can be parallelized.

But it should not be parallelized as "everyone edits everything at once."

It should be parallelized as:

1. a small shared-foundation lane
2. multiple independent module lanes
3. a separate hardware lane for Akida or PYNQ Z2

The migration is safe in parallel only after the shared shell contracts are stable enough.

## Parallelization model

Use a hub-and-spoke model.

### Hub

The hub owns the suite-level contracts:

- `DESIGN.md`
- `nmtk_ui_core`
- `nmtk` shell and workspace host
- shell adapter interface
- desktop navigation rules
- workspace persistence and deep-link semantics
- mode semantics for command mode, studio mode, and instrument mode

### Spokes

Each spoke owns one module migration:

- `neurocnl`
- `Neurosim`
- `Neurochip`
- `Neurobench`
- `Neurosense`
- `Neurohub`
- `Neuro-Dream-Hand`

### Independent side lane

Hardware work can proceed in parallel in:

- `Neurochip`
- `neurocnl`
- `Neurobench`
- `Neuro-Dream-Hand`
- `nmtk` launcher capability reporting

That lane should focus on:

- Akida runtime preparation
- PYNQ Z2 deployment paths
- capability reporting
- verification and docs

It should avoid depending on unstable shell UI decisions.

## Agent classes

## Class A: full-workspace local agents

Examples:

- Codex running locally
- any local agent with access to the full checkout and all submodules

Best use:

- shared contract work
- cross-repo coordination
- root docs
- launcher shell work
- cross-module reviews
- integration fixes

These agents can safely own:

- `DESIGN.md`
- `nmtk_ui_core`
- `nmtk`
- root `docs/`
- root `tests/`
- cross-module ADRs and integration updates

## Class B: single-repo cloud agents

Examples:

- Jules by Google
- any cloud agent limited to one repo checkout

Best use:

- one module at a time
- self-contained UI migrations inside that repo
- package extraction inside that repo
- feature-layer refactors
- repo-local tests

These agents should not be used to invent suite-level contracts.

They should consume:

- an already-written shell adapter spec
- an already-written `DESIGN.md`
- an already-stabilized set of shell and token expectations

## Rule for Jules-like agents

A Jules-like agent needs a repo-local brief that includes everything it cannot discover from the rest of the monorepo.

For each module repo, provide:

1. the target desktop-shell contract
2. the expected package or adapter name
3. the required deep-link and restoration hooks
4. the mobile posture for that module
5. the exact files or package boundaries it owns
6. the validation commands it must run
7. the cross-repo contracts it must not change casually

Without that brief, a single-repo cloud agent will drift or recreate suite decisions locally.

## Dependency gates

The following gates should be treated as hard prerequisites.

### Gate 0: design direction frozen enough

Must exist before broad module UI migration:

- root `DESIGN.md`
- top app bar decision
- top module workspace bar decision
- persistent `/workspace` session direction
- desktop-first, mobile-portable rule set

Status:

- mostly started already, but still needs refinement into implementation-ready guidance

### Gate 1: shell adapter contract

Must exist before module teams fan out:

- adapter interface shape
- desktop entry surface contract
- deep-link contract
- restoration contract
- capability/degradation reporting contract

This is the most important gate for parallelization.

### Gate 2: shared UI core baseline

Must exist before module-native desktop surfaces are built broadly:

- top app bar primitives
- workspace switcher primitives
- shell badges and states
- spacing, shape, and motion tokens

### Gate 3: workspace host baseline

Must exist before native modules can be integrated confidently:

- stable `/workspace` route
- persistent session host
- module registration model
- adapter loading lifecycle

After Gate 3, module work can scale much more safely.

## Recommended agent map

## Foundation lane

### Agent F1: design contract owner

Type:

- full-workspace local agent

Owns:

- `DESIGN.md`
- shell design decisions in root `docs/`
- design-token governance docs

Responsibilities:

- refine the suite design contract
- define component states and shell behavior
- publish a module-facing design brief

Why this should not be Jules:

- this role touches root docs and suite-wide standards

### Agent F2: shared UI core owner

Type:

- full-workspace local agent preferred

Owns:

- `nmtk_ui_core`

Responsibilities:

- top app bar
- workspace switcher
- shell states
- tokens from `DESIGN.md`

Can Jules do this:

- only if Jules is pointed at the `nmtk_ui_core` repo/package itself and given the full design brief
- still better owned locally because this is a high-churn shared dependency

### Agent F3: shell host owner

Type:

- full-workspace local agent

Owns:

- `nmtk`
- launcher shell routing
- workspace state
- module integration host

Responsibilities:

- remove side primary nav
- implement top-bar shell
- implement persistent `/workspace`
- load module adapters

Why this should not be Jules:

- it depends on root-level context, manifest semantics, and launcher guardrails

### Agent F4: shell adapter spec owner

Type:

- full-workspace local agent

Owns:

- root docs for adapter interface
- integration examples

Responsibilities:

- write the adapter contract
- define desktop entrypoints
- define restoration and deep-link hooks
- define capability and degradation reporting

This role unlocks the module lanes.

## Module lanes

Each module lane can be assigned to a different agent after Gates 1-3 are in place.

### Agent M1: `Neurohub`

Good candidate for Jules:

- yes

Why:

- strong self-contained orchestration UI work
- lower hardware risk than some other modules

Jules needs:

- shell adapter spec
- design brief
- project/workflow restoration requirements
- note that heavy orchestration logic stays out of frontend-only code

### Agent M2: `neurocnl`

Good candidate for Jules:

- yes

Why:

- editor and diagnostics UI can be migrated mostly within one repo once shell contracts are defined

Jules needs:

- shell adapter spec
- design brief
- explicit warning not to change handoff/export contracts without reading listed downstream consumers
- desktop target and mobile posture from the module plan

### Agent M3: `Neurobench`

Good candidate for Jules:

- yes

Why:

- report and comparison UI work is mostly repo-local if contracts remain stable

Jules needs:

- shell adapter spec
- chart/table component expectations from `nmtk_ui_core`
- explicit warning not to redefine result schemas in frontend-only code

### Agent M4: `Neurosim`

Good candidate for Jules:

- yes, but only after the shell adapter and desktop interaction patterns are clearer

Why:

- the canvas is interaction-heavy and more coupled to shell behavior than the report-style modules

Jules needs:

- shell adapter spec
- desktop shortcut and selection expectations
- restoration semantics for project/canvas state
- warning that graph contracts must remain stable

### Agent M5: `Neurosense`

Good candidate for Jules:

- yes, with caution

Why:

- session browser and replay are good parallel targets
- hardware-facing acquisition surfaces need stricter coordination

Jules needs:

- shell adapter spec
- desktop monitoring/replay scope
- warning to preserve hardware bridge contracts
- clear mobile posture so it does not overfit phone layouts

### Agent M6: `Neurochip`

Good candidate for Jules:

- yes, but best scoped tightly

Recommended Jules scope:

- artifact browser
- deploy status UI
- desktop-native deploy shell

Poor Jules scope:

- cross-repo hardware contract changes
- launcher manifest semantics
- suite-wide capability reporting design

Jules needs:

- shell adapter spec
- hardware capability/degradation contract
- explicit note that optional hardware paths must stay optional

### Agent M7: `Neuro-Dream-Hand`

Good candidate for Jules:

- only for low-risk UI slices

Recommended Jules scope:

- telemetry viewer
- session review UI
- simulation dashboard shell

Poor Jules scope:

- safety-bound changes
- hardware bridge changes
- guardrail semantics

Jules needs:

- shell adapter spec
- explicit guardrail and safety boundaries
- strict note that safety and hardware assumptions are not to be changed casually

## Hardware lane

### Agent H1: Akida / PYNQ Z2 owner

Type:

- ideally you or a full-workspace local agent

Owns:

- hardware runtime work
- deploy verification
- capability reporting
- docs

Recommended scope while UI migration is running:

- Akida runtime preparation and validation
- PYNQ Z2 deployment and artifact validation
- module capability reporting
- deployment diagnostics
- backend or service stability

Avoid during shared UI churn:

- tying hardware flows to unfinished shell widgets
- depending on still-changing module adapter APIs unless necessary

## Safe parallel combinations

These combinations are good:

1. F1 + F2 + F3 + F4 in sequence with light overlap
2. H1 in parallel with F1-F4
3. M1, M2, M3 in parallel once F4 is ready
4. M4, M5 after shell patterns stabilize
5. M6 and M7 later, with tighter scope and more review

## Unsafe parallel combinations

These combinations are risky:

1. multiple agents editing `DESIGN.md` and `nmtk_ui_core` without one owner
2. multiple agents inventing adapter APIs inside different module repos
3. a Jules agent changing cross-module payloads because the local repo tests pass
4. Akida/PYNQ work depending on unstable shell UI wiring
5. hardware-sensitive modules migrating UI and hardware contracts in the same uncontrolled batch

## What each Jules task packet should contain

For a Jules-like single-repo cloud agent, provide a task packet with:

1. Goal
   - what module slice is being migrated
2. Write scope
   - exact directories/files allowed
3. Read-first docs
   - module `AGENTS.md`
   - module spec
   - relevant root migration doc excerpt copied into the prompt
4. Non-goals
   - what not to change
5. Shell contract summary
   - entry widget
   - deep links
   - restoration
   - degradation reporting
6. Visual mode target
   - command mode, studio mode, or instrument mode
7. Mobile posture
   - full candidate, partial candidate, or review-only candidate
8. Validation
   - exact repo-local commands
9. Escalation triggers
   - conditions that require handing work back to a full-workspace agent

## Suggested rollout phases

## Phase A: foundation

Owners:

- F1
- F2
- F3
- F4

Deliverables:

- stable `DESIGN.md`
- shell adapter spec
- top app bar and workspace bar primitives
- `/workspace` host baseline

## Phase B: early module fan-out

Owners:

- M1 `Neurohub`
- M2 `neurocnl`
- M3 `Neurobench`
- H1 Akida/PYNQ

Why these first:

- they are easier to scope
- they are valuable
- they are less interaction- or safety-coupled than the later modules

## Phase C: interactive module fan-out

Owners:

- M4 `Neurosim`
- M5 `Neurosense`

Why later:

- more interaction and restoration complexity

## Phase D: hardware-sensitive surfaces

Owners:

- M6 `Neurochip`
- M7 `Neuro-Dream-Hand`

Why last:

- higher hardware and safety complexity
- tighter coupling to optional runtime and device assumptions

## Review model

Every spoke agent should hand changes back to a full-workspace local agent for:

- shell contract conformance review
- design conformance review
- cross-module contract review
- integration verification

This is especially important for Jules-like agents because they cannot see the whole suite.

## Practical recommendation

If you want maximum throughput with minimum chaos:

1. keep `DESIGN.md`, `nmtk_ui_core`, `nmtk`, and the shell adapter spec under local full-workspace ownership
2. send Jules-like agents into single modules with sharply bounded write scopes
3. keep Akida/PYNQ work as a separate hardware lane
4. require reintegration and review through a full-workspace agent before merge

That gives you real parallelism without letting each module invent its own desktop platform.
