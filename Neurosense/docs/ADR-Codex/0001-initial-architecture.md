# ADR 0001: Initial Architecture of Neurosense

## Status
Accepted

## Context
Neuromorphic pipelines need a credible path from analog biosignals to spike-based artifacts, but this domain is full of ways to overstate support. The codebase contains multiple device and modality surfaces, yet the current docs intentionally narrow the module around a credibility-first workflow:
`2-channel forearm EMG -> filter -> spike encoding -> record -> replay`

The repo structure supports that architecture:
- FastAPI backend in `neurosense/app/`
- Flutter frontend in `frontend/`
- signal and workflow routers for devices, presets, stream, encoding, recording, sessions, quality, export, NIR, Prophesee, and PYNQ
- services such as `device_manager.py`, `filter_pipeline.py`, `spike_encoder.py`, `recording_service.py`, `replay_service.py`, `session_artifact.py`, and `quality_analyzer.py`
- source adapters in `app/sources/`
- preset definitions in `neurosense/presets/`

The current docs explicitly classify support as validated, experimental, or prototype, and they identify the canonical session artifact as the primary durable output. That means the architecture must optimize for honest, durable recording and replay contracts before it optimizes for breadth of device claims.

## Decision
We will position Neurosense as the biosignal acquisition, filtering, encoding, recording, and replay layer of the toolkit, with a canonical session artifact at the center of the design.

### Core architectural model

The module is built around an end-to-end flow:
- connect to a device or synthetic source
- acquire samples
- apply filtering and quality analysis
- encode spike representations
- persist a canonical session artifact
- replay or export that artifact for downstream use

The artifact is not an optional byproduct. It is the stable handoff surface that lets acquisition, replay, export, and downstream modules share the same session truth.

### Ownership boundaries

Neurosense owns:
- device discovery and connection management
- signal acquisition and filtering
- spike encoding workflows
- signal quality analysis
- session recording, persistence, replay, and export
- encoding presets and modality-specific processing paths

Neurosense does not own:
- the semantics of SNN behavior
- hardware deployment
- benchmarking interpretation

Its job is to create honest, reusable spike-oriented signal artifacts and live streams that other modules can consume.

### Structural decomposition

Safe changes should preserve the current separation:
- routers define workflow and API surfaces
- services implement filtering, encoding, quality, recording, replay, and artifact management
- source adapters isolate hardware- or stream-specific input details
- presets remain explicit configuration assets
- the frontend visualizes and configures the workflow without becoming the place where acquisition or artifact logic lives

The `session_artifact` service is a key architectural seam. If artifact shape or provenance changes, replay, export, test fixtures, and downstream integrations are all affected.

### Architectural rules for safe change

Agents working in this repository should preserve these rules:
- Do not broaden support claims just because a router or source adapter exists.
- Do not bypass the canonical session artifact for "quick" recording or replay paths unless the architecture is intentionally being changed.
- Do not mix validated flagship behavior with prototype integrations in a way that blurs current support boundaries.
- Do not bury preset, channel-label, timing, or provenance metadata; those are part of the artifact contract.
- Do not move signal-processing truth into the UI layer or spread it across multiple unrelated services.

### Why it is built this way

The architecture favors credibility over breadth. A narrow, well-specified EMG workflow with durable artifacts is more valuable to the suite than many shallow hardware claims that cannot be replayed, exported, or trusted later.

## Consequences
- The module can make concrete, testable claims around one well-defined workflow instead of diffuse support across many unvalidated device paths.
- Recording and replay become first-class architecture, which increases artifact and metadata discipline requirements.
- Additional modalities and device paths can still exist, but they remain subordinate to the flagship contract until they are validated.
- Any change to filtering, artifact shape, replay semantics, or provenance fields can affect quality analysis, exports, fixtures, and downstream integrations all at once.
