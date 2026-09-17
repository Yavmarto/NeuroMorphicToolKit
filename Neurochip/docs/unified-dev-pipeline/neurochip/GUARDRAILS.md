# GUARDRAILS.md - NeuroChip System Invariants and Constraints

This document defines the critical system invariants and constraints for the NeuroChip toolkit. All code modifications and additions must respect these boundaries.

## System Invariants

1.  **Quantization Accuracy Loss Limit**: The maximum accuracy loss allowed during quantization analysis is **25.0%**. Any configuration exceeding this must trigger a warning or validation error.
2.  **Fault Injection Rate Bound**: The fault injection rate (dead neurons, noise, etc.) for any test scenario must not exceed **0.3 (30%)**.
3.  **Hardware Memory Fit Invariant**: For any hardware target, the following relationship must hold:
    `neuron_capacity * 6 <= on_chip_memory_kb * 1024`
    (Each neuron requires at least 6 bytes of memory-equivalent space in the typical hardware profile).
4.  **Monotonic Latency Ordering**: Latency estimates must maintain a strict monotonic order:
    `best_case_us <= typical_us <= worst_case_us`.
5.  **Quantization Bit-Width Scope**: Support must be restricted to bit-widths between **2 and 32 bits**.

## Hardware Constraints (Valid Targets)

-   **Core Count**: Valid hardware target configurations must specify a core count between **1 and 128**.
-   **On-Chip Memory**: Memory capacity must be between **1 KB and 16,384 KB (16 MB)**.
-   **Clock Speed**: Target clock speeds must be between **1.0 MHz and 1,000.0 MHz**.

## Security & Reliability Guardrails

1.  **Filename Sanitization**: Any API endpoint that handles file input/output (e.g., NIR or firmware export) **MUST** sanitize filenames using `os.path.basename` to prevent path traversal vulnerabilities.
2.  **Pydantic Enforcement**: All functional schemas in `neurochip/app/schemas/` must import and use the core Pydantic contracts from `neurochip/contracts/` to ensure centralized invariant enforcement.
3.  **Strict Type Checking**: All Python code must pass `mypy --strict`. All Dart code must be free of `dynamic` types (except for initial JSON parsing).
4.  **Property-Based Testing (PBT)**: Critical system invariants must be protected by property-based tests (using `Hypothesis` in Python) in `neurochip/tests/properties/`.

## Prohibited Actions

-   Directly editing build artifacts (e.g., in `dist/`, `build/`, `target/`, or `frontend/lib/` if it's an artifact).
-   Introducing new dependencies without synchronizing the environment (e.g., `poetry lock && poetry install`).
-   Bypassing Pydantic validation for internal data flow between the API and business logic.
