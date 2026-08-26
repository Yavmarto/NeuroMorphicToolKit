# ADR 0005: Temporary hardware-data exception

## Status

Accepted

## Context

`nmtk_ui_core` now owns reusable presentation primitives only. PYNQ and Akida
deployment values are still consumed by both the launcher and NeuroCNL, so
moving them into either application would reverse that dependency direction.

## Decision

Keep `pynq_deployment_model.dart`, `akida_deployment_model.dart`, and their
supporting trained-weight model in `nmtk_ui_core` as a temporary typed-data
exception. They must remain value and conversion types only: no routing,
network access, persistence, Riverpod, or widget state belongs in them.

## Exit criterion

Before the API-ownership and physical-package-merge work completes, move these
hardware contracts to a dedicated contract boundary used by both root and
feature packages. That move must preserve the public payload shapes and update
all launcher and NeuroCNL consumers together.
