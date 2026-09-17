# ADR 0005: SITL Verification

## Status
Accepted

## Context
Physical neuromorphic hardware is expensive, scarce, and unavailable in CI environments. Engineers need to verify deployment artifacts (firmware, bitstreams) without physical chips to maintain development velocity. Waiting for hardware access creates bottlenecks in the development cycle.

## Decision
Implement a Software-In-The-Loop (SITL) verifier that feeds known stimulus spike vectors through simulated hardware backends, compares outputs against expected values, and reports timing and correctness metrics. This enables CI pipelines to validate deployment artifacts without hardware.

## Consequences
- **Positive:** Enables continuous integration without hardware dependencies; catches deployment regressions before they reach physical devices.
- **Negative:** SITL fidelity diverges from real hardware behavior over time; false confidence if stimulus cases are not representative.
