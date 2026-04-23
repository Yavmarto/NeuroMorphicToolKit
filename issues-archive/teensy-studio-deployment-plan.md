---
title: "Move Teensy Deployment from Experimental to Usable Toolkit Workflow"
labels: ["enhancement", "frontend", "backend", "hardware", "teensy", "integration", "toolkit"]
---

## Audit Status

Status as of 2026-04-13: `implemented with remaining real-board evidence`

What is already landed:
- NeuroCNL exposes a fail-closed Teensy deploy gate and maps accepted networks into the exact Neurochip payload shape.
- Neurochip owns firmware generation, serial flashing, and post-flash verification endpoints.
- NMTK has a target-specific Teensy deployment workflow with serial-port selection and flash polling.
- Cross-module integration coverage exists for the happy path and rejected-network paths.

What is still open:
- The issue still lacks hard evidence of a recorded real-board smoke-test success in this repo state; current proof is API/test-contract strong but still hardware-light.
- Keep the issue open until the post-flash verification story is backed by concrete acceptance evidence on an actual Teensy path, not just mocked or contract-level flow.

## Continuation Order

Active queue position: `1 of 4`

Why this is first:
- This is the closest remaining hardware workflow to closure.
- The contract, handoff, UI, and integration-test surfaces are already in place; the main missing piece is real-board proof.

## Next Action To Continue

- Run one real Teensy flash and post-flash verification session from the current toolkit flow.
- Record the exact board, serial port, firmware artifact, and verification outcome in this issue.
- Only after that, check off the remaining hardware-proof acceptance item and close the ticket.

Historical note: the original plan sections below are retained for design context. Use the audit status, continuation order, and acceptance criteria above as the current source of truth.

# Problem Statement
The NeuroCNL Studio UI currently suggests a workflow of:

`write network -> parse -> validate -> generate -> simulate -> deploy`

That promise is not yet true if interpreted as "NeuroCNL alone performs all hardware deployment steps."

However, this repository is a toolkit, not a single-app product. A truthful and useful goal is:

`author in NeuroCNL -> validate/simulate in NeuroCNL -> package/flash through Neurochip -> verify runtime behavior through Neuro-Dream-Hand or a toolkit smoke test`

Today, the repository contains several useful pieces:
- NeuroCNL can parse, validate, generate, and simulate a network.
- NeuroCNL advertises a conservative `teensy` capability profile.
- Neuro-Dream-Hand contains a real `SerialBridge` and manual Teensy HITL scripts.
- Neurochip can generate Teensy firmware archives and can flash them through PlatformIO.
- NMTK can act as the orchestrating launcher for module-to-module workflows.

What is missing is not "NeuroCNL must do everything itself," but a coherent toolkit handoff and UX that moves this multi-module flow from narrow experimentation to a usable deployment workflow.

# What Exists Today
1. NeuroCNL can honestly support `parse`, `validate`, `generate`, and `simulate` on the core Nengo path.
2. Neurochip can generate a Teensy firmware project and has a flash service.
3. Neuro-Dream-Hand can talk to a real Teensy through a binary serial protocol.
4. The Teensy capability model in NeuroCNL is intentionally narrow and does not support arbitrary multi-population topologies.
5. NMTK can already describe module installation and dependency relationships.

# Gaps Blocking the Goal
1. There is no canonical toolkit handoff contract from NeuroCNL IR/Nengo output to Neurochip's Teensy firmware generator.
2. Neurochip and Neuro-Dream-Hand solve adjacent but different Teensy problems:
   - Neurochip handles compile/package/flash.
   - Neuro-Dream-Hand handles runtime HITL closed-loop control.
   These roles are not yet composed into one user-facing deployment story.
3. The NeuroCNL frontend has no target-specific "Deploy via Toolkit" panel for Teensy.
4. There is no toolkit-level deployment readiness gate that confirms a NeuroCNL network fits the Teensy contract before passing work to Neurochip.
5. There is no shared post-deploy verification story:
   - firmware flashed successfully
   - serial port reachable
   - expected protocol alive
   - optional Dream-Hand HITL check succeeds
6. NMTK does not yet expose this as a guided cross-module workflow.

# Proposed Solution
## Phase 1: Define a Toolkit Teensy Deployment Contract
Create a single source of truth for what a "Teensy-deployable NeuroCNL network" means across NeuroCNL, Neurochip, and NMTK.

This contract should include:
- supported neuron model subset
- supported topology subset
- max neurons/synapses
- supported bit widths
- required timestep and execution model
- allowed input/output mapping shape

Implementation targets:
- `neurocnl/contracts/`
- `neurocnl/planner.py`
- `neurocnl/layers/`
- `Neurochip/neurochip/schemas/`

## Phase 2: Add a Real NeuroCNL -> Neurochip Handoff
Implement a dedicated handoff that converts a validated NeuroCNL network into the payload expected by Neurochip's `generate_teensy_project()`.

That handoff should:
- fail closed for unsupported concepts
- explicitly map populations/connections into `NetworkInput`
- produce deterministic firmware artifacts
- attach provenance metadata back to the original CNL spec and validation report

## Phase 3: Use Neurochip as the Official Compile/Flash Module
Do not reimplement firmware generation or flashing in NeuroCNL. Make Neurochip the official toolkit module for:
- firmware generation
- serial port discovery
- flashing
- job polling
- compile/upload error reporting

NeuroCNL should invoke this through a stable API or shared package boundary.

## Phase 4: Use Neuro-Dream-Hand as the Optional Runtime Verification Module
For Teensy deployments intended for reflex/HITL use, the toolkit should be able to hand off to Neuro-Dream-Hand after flash for:
- protocol verification
- simple hardware demo
- sim-to-real comparison
- closed-loop reflex verification

This step is optional for generic firmware deploys, but first-class for the prosthetic workflow.

## Phase 5: Add a Toolkit-Aware Frontend Deployment Experience
Extend the NeuroCNL frontend so "Deploy" becomes "Deploy via Toolkit" and is target-aware.

For Teensy, the UI should show:
- deployment readiness verdict
- exact unsupported concepts, if any
- handoff destination: Neurochip
- firmware generation action
- serial port selection
- flash progress
- optional handoff destination: Neuro-Dream-Hand for runtime verification
- post-flash smoke test result

The UI must not imply "direct NeuroCNL hardware deployment." It should present a guided toolkit pipeline.

## Phase 6: Add End-to-End Toolkit Verification
After flashing, add a minimal verification step that confirms:
- the board responds on the selected port
- the expected protocol is live
- a simple command/telemetry roundtrip succeeds

Then optionally route into a Neuro-Dream-Hand verification workflow.

# Recommended Build Order and Agent Assignment
This issue is suitable for a mixed-agent implementation strategy.

Use the following agent tiers:
- **Top-tier agent**: `Opus 4.6` or `GPT-5.4 Pro`
- **Second-tier agent**: `GPT-5.4`, `Sonnet 4.6`, or `Gemini 3.1 Pro`

## Step 1: Define the shared Teensy deployment contract
- Scope:
  - supported topology subset
  - mapping constraints
  - deployability verdicts
  - failure semantics
- Recommended agent: **Top-tier**
- Why: this is the architectural backbone; a bad contract will create downstream rework across NeuroCNL, Neurochip, and NMTK.

## Step 2: Implement NeuroCNL planner/validator enforcement for Teensy
- Scope:
  - planner verdict updates
  - validation gating
  - rejected-network error reporting
- Recommended agent: **Second-tier**
- Review: **Top-tier review strongly recommended**

## Step 3: Implement NeuroCNL -> Neurochip payload handoff
- Scope:
  - IR/Nengo to `NetworkInput` mapping
  - provenance attachment
  - deterministic artifact handoff
- Recommended agent: **Top-tier**
- Why: this is the highest-risk integration seam for correctness.

## Step 4: Harden Neurochip as the official compile/flash module
- Scope:
  - firmware generation API usage
  - serial port listing
  - flash job invocation/polling
  - error surfacing
- Recommended agent: **Second-tier**

## Step 5: Build the NeuroCNL frontend "Deploy via Toolkit" panel
- Scope:
  - readiness display
  - handoff UI
  - serial port selection
  - flash progress
  - post-flash status
- Recommended agent: **Second-tier**

## Step 6: Add optional Neuro-Dream-Hand runtime verification handoff
- Scope:
  - post-flash verification trigger
  - protocol smoke check
  - optional HITL/sim-to-real continuation
- Recommended agent: **Second-tier**
- Review: **Top-tier review helpful if protocol assumptions change**

## Step 7: End-to-end integration, test tightening, and final review
- Scope:
  - happy-path toolkit flow
  - rejected-network flow
  - regression review across modules
- Recommended agent: **Top-tier**

## Suggested Parallelization
- After Step 1 is complete:
  - one second-tier agent can take Step 4
  - one second-tier agent can take Step 5
  - one second-tier agent can prepare Step 6
- Step 3 should stay on the critical path and should not be delegated to a weaker agent without strong review.

# Acceptance Criteria
- [x] A Teensy deployment contract exists and rejects unsupported NeuroCNL networks before export.
- [x] NeuroCNL can transform a validated network into the exact payload required by Neurochip's Teensy generator.
- [x] Neurochip is the official toolkit module for Teensy firmware generation and flashing.
- [x] The NeuroCNL frontend shows a target-specific toolkit deployment panel instead of the current generic export-only flow.
- [x] Users can generate firmware, pick a serial port, flash, and see job progress from the NeuroCNL/NMTK workflow.
- [ ] A post-flash smoke test confirms command/telemetry roundtrip with a connected Teensy.
- [x] For the prosthetic workflow, users can optionally continue into a Neuro-Dream-Hand runtime verification step.
- [x] End-to-end toolkit tests cover at least one deployable network and one rejected network.

# Out of Scope
- Full arbitrary-network deployment to Teensy.
- Replacing Neurochip's compile/flash role with NeuroCNL-only logic.
- Replacing the Neuro-Dream-Hand runtime HITL loop.
- Claiming that all simulated NeuroCNL networks are deployable to microcontroller hardware.
