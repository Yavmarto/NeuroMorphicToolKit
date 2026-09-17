# NeuroSim Progress Tracker

This document tracks the progress of features outlined in the `neurosim_spec.md`.

## Backend API Endpoints

| Method | Path | Status | Notes |
|---|---|---|---|
| GET | `/api/neurosim/components` | ✅ Completed | Reads JSON manifests |
| GET | `/api/neurosim/templates` | ✅ Completed | Reads JSON templates |
| GET | `/api/neurosim/templates/{id}` | ✅ Completed | Includes full spec |
| POST | `/api/neurosim/validate` | ✅ Completed | Validates graph against Layer 1 invariants |
| POST | `/api/neurosim/generate-cnl` | ✅ Completed | Converts canvas graph to CNL spec |
| POST | `/api/neurosim/parse-cnl` | ✅ Completed | Parses CNL spec to canvas graph |
| POST | `/api/neurosim/preview` | ✅ Completed | |
| POST | `/api/neurosim/sweep` | ✅ Completed | |
| POST | `/api/neurosim/export/{format}` | ✅ Completed | |
| POST | `/api/neurosim/projects` | ✅ Completed | |
| GET | `/api/neurosim/projects/{id}` | ✅ Completed | |
| GET | `/api/neurosim/projects` | ✅ Completed | |

## Frontend User Stories

### Design
- [ ] NS-D1 · Place neuron populations on canvas (Started)
- [ ] NS-D2 · Connect populations
- [ ] NS-D3 · Configure parameters via property panel
- [ ] NS-D4 · Use template starter circuits
- [ ] NS-D5 · Bidirectional CNL synchronization

### Simulation
- [ ] NS-S1 · Real-time simulation preview
- [ ] NS-S2 · Parameter sweep mode
- [ ] NS-S3 · Full simulation run

### Export
- [ ] NS-E1 · Export to multiple formats
- [x] NS-E2 · Keep hardware execution routing in Studio

### Collaboration
- [ ] NS-C1 · Save and load projects
- [ ] NS-C2 · Share via URL

## Milestones
- [x] Initialized Directory Structure (FastAPI and Flutter Web shell)
- [x] Implemented Base Data Models (Pydantic Schemas)
- [x] Implemented Components API
- [x] Implemented Validation API (Layer 1 invariants)
- [x] Implemented CNL Generation & Parsing (bidirectional graph <-> CNL)
