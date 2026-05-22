# NMTK Feasibility Review

Date: 2026-05-22
Status: Suite-level product and delivery review

## Purpose

This document evaluates how feasible the current NMTK product promises are if the intended delivery model is:

- a compiled desktop launcher
- a packaged backend install flow triggered from the launcher UI on first start
- a mobile app distributed through app stores
- a work-in-progress codebase where some modules and workflows are intentionally incomplete

This is not a rejection of the product direction. It is a realism check on what can be shipped credibly and what should be narrowed in the pitch until the implementation surface catches up.

## Short Answer

The core desktop promise is feasible in a narrowed form.

The broad promise of a seamless, low-barrier, cross-platform, multi-module, multi-hardware neuromorphic suite is only partially feasible in the near term.

The mobile app is feasible only if it is positioned as a companion or remote client rather than as a full local runtime host.

## What Is Technically Plausible

### Desktop launcher with UI-driven backend install

This is plausible.

A Flutter desktop app can ship as a compiled shell and can orchestrate first-run installation flows such as:

- downloading signed module bundles
- unpacking packaged backend artifacts
- creating isolated Python environments
- pulling container images when needed
- starting local services and workers
- storing logs, install state, and diagnostics

This is a demanding packaging and operations problem, but it is not an impossible research problem.

### Mobile app in app stores

This is also plausible, but only with a narrower role.

The mobile app is realistic if it acts as:

- a remote dashboard
- a project and artifact browser
- a health and job monitor
- a launch trigger for remotely hosted or desktop-hosted workflows
- a viewer for results, models, logs, or shared assets

The mobile app is not realistic as a full host for the suite's local heavy backends, hardware SDKs, Python toolchains, or board-specific runtime setup.

## Main Feasibility Constraints

### 1. Distribution complexity is the real product risk

The hard part is not building one more Flutter screen or one more FastAPI route.

The hard part is shipping a stable product that can:

- install scientific Python environments reliably
- manage optional native dependencies
- survive OS updates, codesigning, and permissions
- handle background processes on macOS, Windows, and Linux
- recover cleanly when a module install fails halfway through
- present useful diagnostics without pushing users back to the terminal

If this problem is not solved well, the product promise collapses even if the individual modules are good.

### 2. Hardware support multiplies product risk

Every real hardware target adds a support surface that behaves unlike a normal software plugin.

That includes:

- board connectivity
- USB and serial permissions
- SSH setup
- vendor SDK availability
- target-specific runtime packaging
- firmware and overlay compatibility
- partial support on some operating systems

A suite that claims broad hardware support too early will usually disappoint users faster than a suite that is explicit about support tiers.

### 3. The implementation surface is broader than the validated workflow surface

The repo already contains real code, contracts, tests, docs, and accepted ADRs. That is a strength.

But the current suite story still overstates how much of the system is likely to be robust end to end. Some flows are clearly approximate, export-only, mock-validated, or still planning-stage. That is normal for a work in progress, but it means the pitch has to be narrower than the architecture.

### 4. Mobile and desktop should not be sold as equivalent product surfaces

If the mobile app is framed as "NMTK on your phone," the promise is not credible.

If the mobile app is framed as "NMTK companion access to projects, health, jobs, and selected workflows," the promise becomes much more credible.

## Feasibility by Time Horizon

## 3 Months

Realistic if tightly scoped:

- compiled desktop launcher for one primary desktop OS, with developer support for the others
- first-run installer for `suite_api` plus a very small set of core modules
- launcher-visible install state, readiness state, and repair actions
- one or two golden-path workflows that are truly demoable end to end
- mobile app prototype as a remote dashboard or viewer

Likely unrealistic in 3 months:

- fully seamless install and orchestration across macOS, Windows, and Linux
- broad, reliable hardware deployment across multiple physical targets
- an app-store-like experience for all advertised modules
- mobile parity with desktop

Recommended 3-month product line:

"NMTK desktop provides a packaged launcher with UI-guided install and operational visibility for the core suite, with a companion mobile surface for monitoring and project access."

## 12 Months

Realistic if execution stays disciplined:

- stable desktop launcher on all three desktop platforms
- signed update and module-delivery pipeline
- reliable first-run install and repair flow for core modules
- a supported simulation-first workflow that works without hardware
- one or two genuinely validated hardware targets with strong diagnostics
- mobile app with useful companion workflows and shared registry access

Still risky even at 12 months:

- broad "write once, deploy everywhere" semantics across many neuromorphic targets
- seamless no-terminal hardware provisioning for every advertised board
- store-grade mobile experience that meaningfully replaces desktop for serious work

Recommended 12-month product line:

"NMTK is a desktop-first neuromorphic workstation with UI-managed backend installation, validated simulation workflows, and limited but real hardware deployment support for selected targets."

## What Should Be Cut From The Pitch Now

These claims should be removed, softened, or moved behind explicit support qualifiers until the implementation and validation surface is much deeper.

- "No terminal required" as a blanket statement
- "Completely hides" dependency and interoperability complexity
- "One-click" deployment across multiple hardware families
- broad implied parity across all desktop operating systems
- any suggestion that mobile is a full local host for the suite
- any suggestion that exportability means real deployability
- any suggestion that parser recognition means faithful backend execution

Better wording:

- "UI-guided setup for supported configurations"
- "Desktop-first control plane with structured diagnostics and repair actions"
- "Validated support tiers by module and target"
- "Simulation-first, hardware-validated on selected targets"
- "Mobile companion app for monitoring, browsing, and selected remote workflows"

## What Makes The Product Credible

The project becomes credible if it proves a few narrow things well.

### Golden path 1

- author a model
- validate it
- simulate it
- inspect the result
- persist the project

No hardware required. This should be the default success path for new users.

### Golden path 2

- take a validated model
- target one supported hardware path
- run preflight
- install what is missing from the launcher
- deploy
- capture logs, metrics, and failure reasons in the UI

This should exist for one hardware target first, not many.

### Golden path 3

- browse project and artifact state from mobile
- see health, job, and deployment status
- review results and trigger safe remote actions

This is a realistic and valuable mobile story.

## What Would Make The Product Non-Credible

The current direction becomes non-credible if it continues to promise all of the following at once:

- multiple personas with minimal onboarding
- multiple desktop platforms with equal maturity
- many backend modules
- many hardware targets
- no terminal
- smooth first-run install
- mobile app stores
- seamless interoperability

That combination is too much promise for a single near-term product unless support tiers become much stricter.

## Recommended Product Positioning

Use this framing instead:

NMTK is a desktop-first neuromorphic workstation. It ships a compiled launcher that installs and manages supported backend components from the UI, provides structured diagnostics and operational visibility, and enables a small number of validated end-to-end workflows. Mobile extends the workstation as a companion surface for monitoring, browsing, and selected remote actions. Hardware support is tiered and explicit.

## Delivery Priorities

1. Make the desktop launcher operationally trustworthy before making it visually ambitious.
2. Prove one simulation-first workflow end to end.
3. Prove one hardware workflow end to end with honest diagnostics.
4. Treat support matrices as product truth, not just engineering truth.
5. Position mobile as companion access until a stronger remote-control model exists.

## Final Assessment

The project's promises are feasible if they are narrowed to a desktop-first control plane, UI-managed backend installation, a simulation-first default experience, and a very small number of validated hardware targets.

They are not currently feasible if interpreted as a universal, low-friction, app-store-like neuromorphic platform across many targets, operating systems, and personas at once.

The project does not need less ambition. It needs a smaller claim surface than its architecture surface.
