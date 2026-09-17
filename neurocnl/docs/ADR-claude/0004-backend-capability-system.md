# ADR 0004: Backend Capability System

## Status
Accepted

## Context
Not all hardware backends support all CNL concepts equally. Some features are faithfully implemented, some are approximated, and some are entirely unsupported. Users need clear visibility into what their specification will look like on each target platform.

## Decision
Define a `BackendCapabilityProfile` dataclass per backend (nengo, loihi, akida, lava, rockpool, sinabs, spinnaker2) with concept-level fidelity claims categorized as `faithful`, `approximate`, or `unsupported`. The planner uses these profiles to generate warnings, select optimal backends, and drive export decisions. Backend modules are lazy-loaded to avoid importing unavailable hardware SDKs.

## Consequences
- **Positive:** Three-tier fidelity model gives users explicit expectations about backend behavior; lazy loading prevents import failures when optional hardware SDKs are not installed.
- **Negative:** Capability profiles must be manually updated as backend SDKs evolve; the approximate tier can mask significant behavioral differences between simulation and hardware.
