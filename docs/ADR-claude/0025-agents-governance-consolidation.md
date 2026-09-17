# ADR-0025: Consolidation of AGENTS.md Governance Documents

**Status:** Accepted  
**Date:** 2026-06-03

## Context

The repository suffered from significant documentation redundancy and fragmentation regarding AI agent governance files (`AGENTS.md`). A repository scan revealed 25 distinct `AGENTS.md` files distributed across the five main modules (`Neurohub`, `Neurosim`, `Neurochip`, `Neurosense`, `Neurobench`), `neurocnl`, and `Neuro-Dream-Hand`.

This fragmentation presented several risks:
1.  **Exact Duplicates:** Entire pipeline guidelines were duplicated identically in `docs/unified-dev-pipeline/` and `docs/Opus-dev-pipeline/`.
2.  **Pointer Files:** Dozens of 1-line dummy files existed only to point agents back to a parent directory (e.g., `Neurochip/neurochip/AGENTS.md`).
3.  **Governance Drift:** Modules had their primary UI/API constraints defined in their root `AGENTS.md` and a separate, overlapping set of tech-stack and test guidelines in their pipeline documents. If one was updated and the other was not, AI agents might act on contradictory instructions.

## Decision

We have adopted a **Single Source of Truth** model for agent governance:
1.  **Consolidation:** The pipeline-specific tech stack directives (formerly in `unified-dev-pipeline`) were merged into the root module `AGENTS.md` files.
2.  **Elimination of Redundancy:** We deleted 14 redundant dummy pointer files and identically copied Opus pipeline files.
3.  **Resulting Architecture:** The repository now contains exactly 11 definitive governance files: 1 Global Suite Router at the root, and 10 module-specific guides located strictly at the top-level of their respective module directories.

## Rationale

- Ensures that AI agents parsing the repository always find a single, comprehensive guide for any given module.
- Prevents architectural drift caused by maintaining parallel documentation in `unified-dev-pipeline` and `Opus-dev-pipeline`.
- Reduces filesystem noise by eliminating 1-2 line dummy files.

## Consequences

- Human developers and AI agents alike must now refer strictly to the root `ModuleName/AGENTS.md` file for all governance, UI constraints, and testing commands.
- Future modifications to agent behavior, tech stack constraints, or test pipelines must be made to these definitive files. The `docs/unified-dev-pipeline` and `docs/Opus-dev-pipeline` directories will no longer house separate `AGENTS.md` files.
