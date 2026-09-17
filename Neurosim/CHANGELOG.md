# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-03-20

### Added
- Initialized directory structure for FastAPI backend and Flutter web frontend.
- Implemented core data models and Pydantic schemas for the NeuroSim module.
- Added components API to load JSON manifests for neurons, synapses, encoders, and patterns.
- Implemented templates API for starter circuits.
- Added validation API for Layer 1 invariants.
- Implemented bidirectional CNL (Conceptual Neural Language) generation and parsing.
- Added simulation preview functionality using the Nengo simulator.
- Implemented parameter sweep runner for iterative simulations.
- Added project management API with SQLite persistence.
- Configured CORS with support for `ALLOWED_ORIGINS` environment variable.
- Added `SECURITY.md` with vulnerability reporting process.
- Added `CHANGELOG.md` with version history.
- Added `.env.example` with documented environment variables.
