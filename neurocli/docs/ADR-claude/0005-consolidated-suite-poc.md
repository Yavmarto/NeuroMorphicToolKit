# ADR 0005: Consolidated Suite Proof of Concept

## Status

Accepted

## Context

The first implementation expanded beyond scaffolding before the suite completed
its move to one Suite API. Per-module ports and uvicorn targets now describe a
retired runtime, and `neuro deploy` reported success without producing an
artifact.

## Decision

The proof of concept keeps every top-level command but narrows each to a
truthful supported path. Lifecycle commands manage the canonical Compose stack,
status consumes aggregated Suite API health, the verified scaffold is
NIR+snnTorch, and deployment produces a validated offline PYNQ ZIP from a CNL
spec plus trained NIR graph.

Other scaffolds require explicit `--experimental` opt-in. Hardware programming,
Akida packaging, package-index publication, and production deployment remain
out of scope.

## Consequences

The CLI now has one end-to-end acceptance path and can be used safely from CI.
The `install` and `run` positional module arguments are intentionally removed
because standalone module services no longer exist.
