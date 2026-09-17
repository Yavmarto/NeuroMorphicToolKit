# ADR 0001: Initial Architecture of nmtk

## Status
Accepted

## Context
NMTK seeks to unify several multi-disciplinary tools (NeuroCNL, Neurosim, etc.) into a cohesive application experience, preventing the user from juggling a variety of different code bases and build systems.

## Decision
We will architect `nmtk` as the core Flutter-based Desktop App acting as the unified "Launcher" for the toolkit. It will wrap complex background container workflows (using Docker and virtual environments) and present modular features via self-hosted embedded micro-services.

## Consequences
- **Positive:** Provides a clean, modern, single-entry UI. Eliminates the need for end-users to understand containerization.
- **Negative:** UI to daemon communication via micro-services adds latency and complex inter-process state management.
