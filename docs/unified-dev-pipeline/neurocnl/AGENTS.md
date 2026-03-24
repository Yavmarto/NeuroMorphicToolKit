# Agent Rules for neurocnl

## Non-Negotiable

1. **NEVER modify `layers/layer1_invariants.py`** without explicit human approval. These are physics laws, not business rules.
2. **NEVER hard-code physics constants** — they come from contracts or invariant functions.
3. **ALWAYS run `pytest` and `mypy --strict`** before considering a task complete.
4. **ALWAYS check GUARDRAILS.md** before starting implementation.
5. **NEVER delete or weaken existing test assertions** — if a test fails, fix the code, not the test.
6. **NEVER modify CNL grammar patterns** in `cnl_parser.py` without human approval. Grammar changes affect all downstream modules.

## Domain Rules

7. All neuron parameters must validate against Layer 1 invariants before use.
8. All hardware exports must satisfy target-specific contracts (Loihi, SpiNNaker, Teensy).
9. Simulation results must be compared against golden baselines when available.
10. The CNL parser uses regex only — no LLM calls in the parse path.
11. Layer 3 assertions must test exactly one behavioral rule per test function.
12. Export code must produce files that compile/validate on the target platform.

## When to Stop and Ask

- Any change that affects Layer 1 invariants or their validator
- Any new CNL concept or grammar extension
- Any new hardware target not covered by existing contracts
- Any simulation result that deviates >10% from golden baseline
- Any change to the `pipeline.py` orchestration flow
- Any modification to the Anthropic API integration in assertion generator
