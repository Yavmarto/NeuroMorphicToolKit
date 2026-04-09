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
