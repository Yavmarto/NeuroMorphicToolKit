---
title: "Move PYNQ-Z2 Deployment from Experimental to Usable Toolkit Workflow"
labels: ["enhancement", "frontend", "backend", "hardware", "pynq", "fpga", "integration", "toolkit"]
---

## Audit Status

Status as of 2026-04-13: `implemented with remaining board-ready artifact evidence`

What is already landed:
- The planner, contracts, and docs distinguish `exportable` from runtime `deployable`.
- Neurochip has a hardware-aware PYNQ backend with simulator fallback plus SITL verification support.
- NMTK has a PYNQ deployment screen, provider, and remote-board polling flow.
- NeuroCNL includes a PYNQ handoff layer and related tests.

What is still open:
- Real-board proof remains blocked on the missing synthesized `.bit` / `.hwh` overlay artifacts, so only simulator-backed deployment is evidenced today.
- The remaining open question is not the basic handoff shape anymore; it is whether the board-ready overlay package and acceptance evidence are present for a truthful deployable claim.
- Keep this issue open until either:
  - a real board-ready overlay package is available and validated, or
  - the repo explicitly narrows the accepted scope to simulator-backed deployment proof.

## Continuation Order

Active queue position: `2 of 4`

Why this is next:
- The planner/export contract, runtime artifact contract, Neurochip backend, and NMTK deploy flow are already present.
- The ticket is now mostly waiting on board-ready artifacts and closure evidence rather than another large architecture pass.

## Next Action To Continue

- Decide whether the closure target is real-board deployment or simulator-backed acceptance only.
- If real-board deployment is still the target, land the missing `.bit` / `.hwh` artifacts and record one successful configured-status run.
- If simulator-backed acceptance is acceptable for this phase, tighten the issue wording and close out the remaining UI/status proof explicitly.

Historical note: the original plan sections below are retained for design context. Use the audit status, continuation order, and acceptance criteria above as the current source of truth.

# Problem Statement
NeuroCNL already contains a `pynq` capability profile and a PYNQ exporter, which makes the Studio appear closer to FPGA deployment than it really is.

Today the codebase can:
- export a quantized overlay-style configuration
- describe PYNQ support as approximate
- simulate some PYNQ backend behavior in Neurochip
- run a Dream-Hand PYNQ SITL path using ZeroMQ and fallback logic

But it cannot yet honestly claim a complete Studio flow of:

`write network -> parse -> validate -> generate -> simulate -> deploy to PYNQ-Z2`

As with Teensy, the right goal is not "NeuroCNL alone does everything," but:

`author in NeuroCNL -> export a valid PYNQ runtime package -> deploy/run through Neurochip -> optionally verify behavior through a Dream-Hand SITL/HITL path -> orchestrate through NMTK`

The missing pieces are cross-module contracts, real runtime configuration, and a target-specific toolkit UX that turns the current experimental path into a usable toolkit workflow.

# What Exists Today
1. NeuroCNL has a PYNQ exporter that emits overlay metadata and packed weights.
2. NeuroCNL capability planning already marks PYNQ as approximate and quantized.
3. Neurochip has a `PYNQBackend`, but its configuration path is still a placeholder and its execution path falls back to simulation when `pynq` is missing.
4. Neuro-Dream-Hand has a useful PYNQ SITL pattern, but not a productionized NeuroCNL Studio deploy path.
5. NMTK is the natural place to orchestrate module handoffs and status.

# Gaps Blocking the Goal
1. There is no stable toolkit artifact contract for a deployable PYNQ package:
   - overlay bitstream
   - hardware description
   - quantized weights
   - runtime register map
2. NeuroCNL export stops too early; it produces configuration, not a full toolkit deployment artifact lifecycle.
3. Neurochip's runtime backend does not yet perform real MMIO configuration or guaranteed DMA interaction.
4. The frontend does not distinguish between:
   - "exportable for future FPGA flow"
   - "deployable now to a connected PYNQ board"
5. The Dream-Hand SITL pattern is not formally connected to NeuroCNL/Neurochip deployment outputs.
6. There is no remote-board orchestration model exposed through NMTK or the NeuroCNL UI.

# Proposed Solution
## Phase 1: Split PYNQ "Exportable" from "Deployable"
Define two explicit states in planner and UI:
- `exportable`: NeuroCNL can emit a quantized overlay config
- `deployable`: a valid overlay package and runtime endpoint are available

This prevents the Studio from implying that config export equals hardware deployment.

## Phase 2: Define a Toolkit PYNQ Runtime Artifact Contract
Create a concrete artifact bundle shared by NeuroCNL and Neurochip that includes:
- `overlay_config.json`
- quantized `weights.bin`
- overlay metadata (`.bit`, `.hwh`, register map)
- target board metadata
- deployment manifest

This contract should be consumable by:
- Neurochip runtime deployment
- optional Dream-Hand SITL verification
- NMTK job/status orchestration

## Phase 3: Implement Real Neurochip Runtime Configuration
Expand Neurochip's `PYNQBackend` from placeholder behavior into real board logic:
- overlay load
- MMIO register writes
- weight/config upload
- DMA or register-driven inference
- structured runtime errors

Add a board-simulator interface for CI so this path is testable without physical FPGA hardware.

## Phase 4: Add NeuroCNL -> Neurochip PYNQ Handoff
Build a stable toolkit integration so NeuroCNL can:
- validate PYNQ compatibility
- export the runtime artifact bundle
- submit deployment to Neurochip
- trigger remote inference checks

This should be an explicit target integration, not an incidental file download.

## Phase 5: Reuse Neuro-Dream-Hand for Optional PYNQ Verification
Where applicable, allow the toolkit to use Dream-Hand's PYNQ SITL path as an optional verification stage:
- start ARM-side service
- feed known stimuli
- compare expected outputs
- validate loop timing at a coarse level

This is not a universal requirement for all PYNQ uses, but it is valuable for the prosthetic/control workflow already present in the toolkit.

## Phase 6: Add a Truthful Toolkit Deployment UX
For the PYNQ target, the NeuroCNL frontend should show:
- whether the network is only exportable or truly deployable
- quantization and topology warnings
- handoff destination: Neurochip
- artifact generation status
- remote board endpoint configuration
- deployment and inference verification status
- optional verification destination: Neuro-Dream-Hand SITL

## Phase 7: Add NMTK Orchestration
Expose the PYNQ pipeline as a toolkit workflow:
- prepare package
- deploy via Neurochip
- monitor status
- optionally verify via Neuro-Dream-Hand

NMTK should surface this as one guided task even though multiple modules participate.

## Phase 8: Add Remote Deployment and Verification
Support a realistic model where Neurochip runs on the PYNQ board or talks to it remotely.

The minimum deploy verification should confirm:
- the target board is reachable
- the overlay loads successfully
- quantized weights are applied
- a known input produces a valid output

# Recommended Build Order and Agent Assignment
This issue has more architectural risk than the Teensy path. Use stronger agents for the contract and runtime-core pieces.

Use the following agent tiers:
- **Top-tier agent**: `Opus 4.6` or `GPT-5.4 Pro`
- **Second-tier agent**: `GPT-5.4`, `Sonnet 4.6`, or `Gemini 3.1 Pro`

## Step 1: Define `exportable` vs `deployable` semantics
- Scope:
  - planner statuses
  - UI semantics
  - artifact-state definitions
- Recommended agent: **Top-tier**
- Why: this is the truthfulness boundary for the whole product flow.

## Step 2: Define the shared PYNQ runtime artifact contract
- Scope:
  - package contents
  - board/runtime metadata
  - register-map assumptions
  - deployment manifest
- Recommended agent: **Top-tier**

## Step 3: Align NeuroCNL export with that contract
- Scope:
  - exporter outputs
  - quantization expectations
  - artifact validation
- Recommended agent: **Second-tier**
- Review: **Top-tier review recommended**

## Step 4: Implement real Neurochip PYNQ runtime behavior
- Scope:
  - overlay load
  - MMIO writes
  - DMA/register run path
  - structured runtime errors
  - simulator/test double for CI
- Recommended agent: **Top-tier**
- Why: this is the hardest technical implementation in the PYNQ plan.

## Step 5: Implement NeuroCNL -> Neurochip deployment handoff
- Scope:
  - deploy request submission
  - remote endpoint configuration
  - deployment status handling
- Recommended agent: **Second-tier**
- Review: **Top-tier review helpful**

## Step 6: Add optional Neuro-Dream-Hand SITL verification path
- Scope:
  - consume deployed artifact/runtime endpoint
  - run known stimuli through the PYNQ loop
  - capture coarse correctness/timing signals
- Recommended agent: **Second-tier**

## Step 7: Build the NeuroCNL/NMTK frontend workflow
- Scope:
  - readiness UX
  - deployment orchestration UI
  - remote board endpoint forms
  - verification status
- Recommended agent: **Second-tier**

## Step 8: Final cross-module integration and review
- Scope:
  - export-only path
  - deployable path
  - rejected-network path
  - runtime verification path
- Recommended agent: **Top-tier**

## Suggested Parallelization
- After Steps 1 and 2 are complete:
  - one second-tier agent can work on Step 3
  - one second-tier agent can prepare Step 7
  - one second-tier agent can prepare Step 6
- Step 4 should stay with a top-tier agent.

# Acceptance Criteria
- [x] Planner and UI clearly distinguish PYNQ `exportable` from `deployable`.
- [x] A shared PYNQ deployment artifact contract exists across NeuroCNL and Neurochip and can be reused for optional Dream-Hand verification.
- [x] Neurochip `PYNQBackend` performs real configuration and run steps instead of placeholder-only logic.
- [x] NeuroCNL can hand off a validated network to Neurochip for PYNQ deployment through a stable API or shared package boundary.
- [ ] The NeuroCNL frontend includes a PYNQ-specific toolkit deployment panel with readiness, warnings, deployment status, and verification results.
- [x] The toolkit can optionally route a successfully deployed artifact into a Dream-Hand SITL verification path.
- [x] NMTK can present the multi-module PYNQ flow as one guided operation.
- [x] End-to-end tests cover successful artifact export, rejected unsupported networks, and simulated runtime verification.

# Out of Scope
- Full FPGA synthesis from arbitrary NeuroCNL graphs inside the Studio.
- Requiring NeuroCNL alone to own board runtime logic.
- Pretending a JSON export alone is equivalent to deployment.
- Supporting every possible PYNQ overlay architecture in the first version.
