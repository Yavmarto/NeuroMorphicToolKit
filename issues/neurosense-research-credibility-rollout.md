---
title: "Move NeuroSense from Prototype Breadth to Research-Credible Real Data and Hardware Workflow"
labels: ["enhancement", "planning", "neurosense", "biosignals", "hardware", "integration", "benchmarking"]
---

## Audit Status

Status as of 2026-04-13: `partially implemented`

What is already landed:
- The flagship workflow is documented and now anchors repo claims.
- The canonical HDF5 session artifact contract is implemented, versioned, and exercised by fixture-backed tests.
- Downstream bridge code exists for NeuroCNL and Neurobench consumption of the canonical artifact.
- Support levels are documented more truthfully across the README and workflow docs.

What is still open:
- The real `OpenBCI Cyton` path is still not physically validated end to end, so the real-board credibility gap remains.
- Benchmark evidence and regression thresholds for the signal-to-spike path are still open.
- UI alignment for support levels and the final truthful end-to-end demo remain unfinished.
- Keep the issue focused on converting the current credibility foundation into recorded real-hardware proof and measured performance evidence.

# Purpose
This file is the ordered issue list for turning `NeuroSense` into a more credible module for neuromorphic researchers, hardware engineers, and applied edge-AI teams.

The goal is not to maximize feature count.

The goal is to make the module:
- honest about what is real vs simulated
- useful with real biosignal data
- reusable across the wider toolkit
- credible to people working in neuromorphic computing

# Recommended Execution Order
1. Define the flagship real-data use case and success metrics
2. Validate one real acquisition hardware path end to end
3. Produce a canonical recorded-session artifact and replay workflow
4. Benchmark the full signal-to-spike pipeline
5. Tighten pipeline integration with NeuroCNL and Neurobench
6. Downgrade experimental hardware claims and document support levels
7. Add one truthful end-to-end demo and acceptance script

# Ordered Issues

## 1. Define a Flagship NeuroSense Workflow

### Problem Statement
`NeuroSense` currently covers many ideas at once: biosignal acquisition, spike encoding, replay, event cameras, PYNQ ingestion, export, and pipeline integration.

That breadth is useful, but it makes the project hard to evaluate.

Without one narrow flagship workflow, the module risks looking broad but unproven.

### Proposed Scope
Choose one primary workflow and treat it as the default credibility target:

`2-channel forearm EMG -> filter -> spike encoding -> record -> replay -> toolkit integration`

This workflow should define:
- target hardware
- expected sampling rate
- expected latency budget
- expected file outputs
- expected downstream consumers

### Acceptance Criteria
- [x] A single flagship workflow is documented in the `NeuroSense` docs and README.
- [x] The workflow names the exact supported hardware, presets, and outputs.
- [x] The workflow defines concrete success metrics for latency, data integrity, and replay correctness.
- [x] All later `NeuroSense` claims are phrased relative to this workflow first.

## 2. Validate One Real Acquisition Hardware Path

### Problem Statement
The code already supports BrainFlow-style device management, but much of the current confidence comes from mocks and synthetic paths rather than one fully validated real hardware route.

This makes the hardware story weaker than the code surface suggests.

### Proposed Scope
Pick one real acquisition path and validate it properly:
- preferred candidates: `OpenBCI Cyton` or `OpenBCI Ganglion`
- acquisition
- connect/disconnect
- channel count
- sampling rate
- signal capture
- replay from saved session

Avoid broadening hardware support until one path is reliable.

### Acceptance Criteria
- [x] One real board family is marked as the primary supported acquisition target.
- [ ] A hardware validation script succeeds on that board without mocks.
- [ ] Real recordings from that board are checked into a safe sample-data location or documented as reproducible fixtures.
- [ ] Errors and unsupported conditions are reported clearly in API and UI.
- [ ] Other device paths are labeled `experimental` until similarly validated.

## 3. Create a Canonical Session Artifact Contract

### Problem Statement
`NeuroSense` already records, replays, and exports data, but the project still needs one canonical artifact contract for recorded sessions that other toolkit modules can trust.

Without that, replay and export remain useful features rather than ecosystem infrastructure.

### Proposed Scope
Define one canonical session artifact containing:
- raw analog data
- filtered data
- spike data
- timestamps
- markers
- channel labels
- preset and encoding metadata
- hardware provenance

This should be the source of truth for:
- replay
- export
- downstream benchmarking
- cross-module integration

### Acceptance Criteria
- [x] A documented session artifact contract exists for HDF5-backed recordings.
- [x] Replay uses the same artifact contract as live-recorded sessions.
- [x] Exporters preserve enough metadata for reproducible downstream use.
- [x] At least one sample artifact is used in automated tests.
- [ ] NeuroCNL and Neurobench integration points consume this artifact without ad hoc conversion logic.

## 4. Benchmark the Signal-to-Spike Pipeline

### Problem Statement
The spec makes claims about responsive streaming and real-time use, but the module still needs a benchmark story that measures the actual path from acquisition through filtering and encoding.

Without measurements, the project cannot make strong real-time claims.

### Proposed Scope
Benchmark the end-to-end pipeline for the flagship workflow:
- acquisition to raw frame availability
- filtering time
- encoding time
- websocket delivery time
- replay throughput

Record results for realistic batch sizes and channel counts.

### Acceptance Criteria
- [ ] A benchmark script exists for the flagship workflow.
- [ ] Measured latency is reported for raw, filtered, and spike streams.
- [ ] Results are documented with hardware/software environment details.
- [ ] The README and module docs use measured numbers rather than aspirational claims.
- [ ] Regression thresholds are added for critical latency-sensitive paths.

## 5. Tighten Integration with NeuroCNL and Neurobench

### Problem Statement
`NeuroSense` becomes much more relevant to the neuromorphic space when its outputs are first-class inputs to the rest of the toolkit, not just files or isolated UI views.

At the moment, integration exists in principle, but the strongest reusable workflow still needs to be made explicit and reliable.

### Proposed Scope
Make the flagship `NeuroSense` artifact usable directly by:
- `NeuroCNL` for simulation/input routing
- `Neurobench` for replay-based evaluation and comparison

Focus on one clean path first rather than many partial integrations.

### Acceptance Criteria
- [ ] A saved `NeuroSense` session can be replayed into a documented `NeuroCNL` workflow.
- [ ] A saved `NeuroSense` artifact can be used in at least one `Neurobench` benchmark flow.
- [ ] Integration docs describe the exact handoff format and steps.
- [ ] End-to-end tests cover at least one cross-module replay workflow.

## 6. Make Hardware Support Levels Explicit

### Problem Statement
`NeuroSense` currently reaches toward event cameras, PYNQ edge nodes, and biosignal hardware, but not all of those paths are equally mature.

If the project presents all of them as equivalent, it weakens credibility.

### Proposed Scope
Introduce explicit support levels such as:
- `validated`
- `prototype`
- `experimental`
- `planned`

Apply them to:
- biosignal acquisition boards
- replay/export paths
- Prophesee/event-camera paths
- PYNQ-related paths

### Acceptance Criteria
- [x] Every major hardware or data-ingestion path has an explicit support level.
- [ ] README, docs, and UI use the same support labels.
- [x] PYNQ and event-camera features are described truthfully relative to their current implementation state.
- [x] No workflow is implied to be hardware-ready unless it has a real validation path and acceptance script.

## 7. Add One Truthful End-to-End Demo

### Problem Statement
Even with good internals, the module will still feel abstract unless there is one repeatable demo showing exactly what a user can do with real data today.

### Proposed Scope
Build one end-to-end demo around the flagship workflow:
- connect supported device or use a documented real recording
- stream filtered data
- encode spikes
- record a session
- replay it
- hand it off into one downstream toolkit flow

This should be runnable by a new contributor without reverse-engineering the system.

### Acceptance Criteria
- [ ] A single demo script or runbook exists for the flagship workflow.
- [ ] The demo uses truthful prerequisites and does not depend on hidden setup.
- [ ] The demo is validated manually with a documented acceptance checklist.
- [ ] The demo is the primary reference when describing current `NeuroSense` capability.

# Parallelization Guidance
Use this order when splitting the work into implementation tickets:

1. Issue 1 must happen first.
2. Issue 2 and Issue 3 can proceed in parallel once the flagship workflow is fixed.
3. Issue 4 should begin after enough of Issues 2 and 3 exist to measure real behavior.
4. Issue 5 should start only after the artifact contract is stable.
5. Issue 6 can run in parallel with all implementation work and should be updated continuously.
6. Issue 7 should happen near the end, once the validated path is real.

# Definition of Done
Treat this rollout as complete only when all of the following are true:
- one flagship workflow is clearly defined
- one real hardware path is validated
- one canonical session artifact is stable
- one downstream integration path is proven
- one benchmark report exists
- one truthful demo is documented
- support levels are honest across code, docs, and UI

# Progress Update

## Current Status Snapshot

Overall status: the foundation is in place, but the rollout is still midstream.

Current standing by issue:
- Issue 1 is complete.
- Issue 2 is partially complete: `OpenBCI Cyton` is now the primary real-board target and the acceptance-prep path exists, but a no-mock validation run and real sample capture are still open.
- Issue 3 is mostly complete: the canonical HDF5 session artifact is documented, versioned, tested, and used by recording/replay/export, but downstream `NeuroCNL` and `Neurobench` consumption is still open.
- Issue 4 has not started yet.
- Issue 5 has not started yet.
- Issue 6 is partially complete: docs now use explicit support levels, but UI alignment is still open.
- Issue 7 has started in prep form through the Cyton acceptance script and runbook, but the truthful end-to-end demo is not complete until it is run successfully without mocks.

What this means in practice:
- The repo now has a credible foundation for the flagship EMG workflow.
- The biggest remaining credibility gap is still real hardware validation.
- After that, the next major work is cross-module integration, benchmarks, UI label alignment, and a final truthful demo.

## 2026-04-07

Completed in this slice:
- Defined the flagship workflow in the README and dedicated docs around the
  `2-channel forearm EMG -> filter -> spike encoding -> record -> replay`
  path.
- Added canonical HDF5 session artifact schema `1.0` with explicit metadata for
  `artifact_schema_version`, `signal_type`, `capture_mode`, `channel_labels`,
  `hardware_provenance`, and `support_level`.
- Updated recording, session loading, replay, and export to use the same
  artifact contract.
- Added checked-in fixture artifact coverage for session metadata, replay, and
  export tests.
- Added support-level labeling in the README, hardware docs, and the PYNQ /
  Prophesee integration docs.

Still open:
- Real-board validation of the `OpenBCI Cyton` flagship path
- UI alignment on support labels
- NeuroCNL and Neurobench artifact consumption
- benchmark measurements and thresholds
- truthful end-to-end demo/runbook

# Next Handoff

Recommended next ticket:
- Start Issue 2 with an `OpenBCI Cyton` acceptance path.
- Keep scope narrow:
  connect/disconnect,
  confirm 2-channel EMG capture at the expected sampling rate,
  save one real session artifact,
  replay that artifact without mocks,
  and document every unsupported condition encountered.

## 2026-04-07 Cyton Prep Update

Completed in this slice:
- Reworked the hardware acceptance flow around `OpenBCI Cyton` as the only active real-board validation target.
- Replaced the broad validation script with a Cyton-first acceptance-prep script that supports `--mock`, `--serial-port`, canonical artifact creation, replay, disconnect, and pass/fail checklist output.
- Hardened device discovery so the synthetic board is always available and Cyton is only shown when explicitly configured.
- Extended the device connect route to accept an optional `serial_port` without changing the existing route shape.
- Improved operator-facing error detail for missing Cyton configuration, missing serial port, already-connected state, and BrainFlow prepare/start failures.
- Added a dedicated Cyton runbook with prerequisites, mock and real command examples, expected output, and troubleshooting guidance.
- Updated touched docs so they no longer imply broad real-board readiness beyond the experimental Cyton path.

Still open:
- Run the Cyton acceptance script on a real board without mocks.
- Capture one real flagship EMG session artifact from Cyton hardware.
- Confirm the current API and UI messaging is clear enough when real-board connection fails for common operator mistakes.
- Finish UI support-label alignment so docs and UI use the same labels.

Recommended next ticket:
- Execute the Cyton acceptance-prep script against a real `OpenBCI Cyton` device, record the outcome, and only then check off the remaining Issue 2 acceptance items that are actually proven.

Completed in this slice:
- Narrowed device discovery so the synthetic board is always available and
  `OpenBCI Cyton` is the only active real-board validation target when
  explicitly configured.
- Added optional `serial_port` support to the device connect endpoint.
- Replaced the old broad validation script with a Cyton-first acceptance-prep
  flow that supports `--mock`, records a flagship EMG artifact, replays it, and
  prints an operator checklist.
- Added a dedicated Cyton acceptance-prep runbook and updated API/device docs to
  stop implying broad real-board discovery support.

Still open from Issue 2:
- Real no-mock Cyton execution on hardware
- real recording fixture or documented capture artifact from a physical board
- UI-side error/support-label alignment for hardware-specific failures

Recommended next ticket:
- Execute the new Cyton acceptance-prep script on a real board and capture the
  first hardware-backed artifact plus acceptance notes.
