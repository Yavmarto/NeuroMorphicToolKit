# ADR 0002: Multi-Stage Translation Pipeline

## Status
Accepted

## Context
NeuroCNL's primary function is translating plain-English specifications into verified Spiking Neural Networks. This process involves complex natural language understanding, which if delegated entirely to a single large LLM prompt, results in frequent hallucinations, syntax errors, and invalid neurological models.

## Decision
We adopted a multi-stage translation pipeline separated into distinct discrete phases in `planner.py`:
1.  **Text Parse to IR:** An LLM extracts the English prompt into an Intermediate Representation (IR) consisting of discrete logic blocks.
2.  **Validation & Invariant Check:** The IR is passed through strict mathematical and programmatic bounds checking (not an LLM) to guarantee validity.
3.  **Target Code Generation:** The validated IR is translated mechanically into Nengo Python code or hardware-specific targets.

## Consequences
- **Positive:** Dramatically reduces code hallucinations and ensures that the generated pipeline is reproducible.
- **Negative:** Increased latency due to the multiple stages and internal state transfers, making quick iterations slower natively.

## Status Update (2026-07-16 audit)
This ADR attributes an LLM-based "Text Parse to IR" stage to `planner.py`. `planner.py` actually contains only backend-capability/deployability planning functions (`plan_backend_support`, `plan_teensy_deployability`, `plan_pynq_exportability`, `plan_akida_exportability`). The real parse→validate→generate orchestration lives in `pipeline.py`, and parsing is deterministic (tokenizer/regex-based `NIR_CNL_Parser`), not an LLM call. The one LLM usage in the core package is in `generation/assertion_generator.py` (Anthropic client for generating test assertions), unrelated to parsing.
