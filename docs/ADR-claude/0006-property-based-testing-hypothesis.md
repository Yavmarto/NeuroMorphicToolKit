# ADR 0006: Property-Based Testing with Hypothesis

## Status
Accepted

## Context
Traditional example-based tests only cover explicitly written cases and miss edge cases in complex domains like neuromorphic network specifications, hardware contracts, and simulation parameters. The NMTK codebase needs systematic exploration of input spaces to catch boundary conditions and invariant violations.

## Decision
Use Hypothesis for property-based testing across all major modules (neurocnl, Neurohub, Neurosim, Neurochip, Neuro-Dream-Hand). Property tests live in dedicated `tests/properties/` directories. A CI profile is configured via `conftest.py` with `hypothesis.settings(max_examples=200)` for thorough testing in CI, while local development uses the default (100 examples) for faster feedback. Test markers separate property tests from unit and integration tests.

## Consequences
- **Positive:** Property-based tests systematically discover edge cases that hand-written examples miss; the CI profile with 200 examples provides thorough coverage without excessive runtime.
- **Negative:** Property test failures can be difficult to reproduce due to randomized inputs; Hypothesis shrinking can produce minimal but non-obvious counterexamples that require domain expertise to interpret.
