# ADR 0005: Separate Deployment Providers

## Status
Accepted

## Context
Hardware deployment to Teensy 4.1, PYNQ Z2, and BrainChip Akida requires target-specific workflows, serial protocols, state tracking, and error handling. A single polymorphic deployment abstraction would be overly complex given the fundamentally different deployment mechanisms.

## Decision
Implement three independent `ChangeNotifierProvider` deployment providers (TeensyDeployProvider, PynqDeployProvider, AkidaDeployProvider) each with its own screen, service layer, and state management. Each provider communicates with Neurochip's backend API for the actual deployment operations.

## Consequences
- **Positive:** Independent providers keep each deployment workflow focused and independently testable; adding a new hardware target means adding a new provider without modifying existing ones.
- **Negative:** Three separate providers duplicate common deployment patterns (progress tracking, error handling, status polling); no shared abstraction for cross-target deployment comparison.

## Status Update (2026-07-16 audit)

Superseded by ADR-0006 (state management) and ADR-0007 (deploy providers moved out of the launcher). Confirmed by grep: `AkidaDeployProvider`, `PynqDeployProvider`, and `TeensyDeployProvider` do not exist in `nmtk/neuro_toolkit/lib/providers/riverpod_providers.dart` or anywhere else under `nmtk/neuro_toolkit/lib/`. ADR 0006 and ADR 0007 already state they supersede this ADR's remaining launcher-side content; this note is the reciprocal pointer that was never added here.
