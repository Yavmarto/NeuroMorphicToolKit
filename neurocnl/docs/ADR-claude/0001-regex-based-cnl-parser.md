# ADR 0001: Regex-Based CNL Parser

## Status
Accepted

## Context
A core decision is how to parse controlled natural language specifications into structured representations. Machine learning NLP models are non-deterministic and expensive; formal grammars (PEG/ANTLR) add external dependencies and are complex to maintain for a domain-specific language.

## Decision
Use compiled regex patterns to parse CNL sentences into typed `ParsedSentence` objects across 19 concept families (populations, connections, timing, plasticity, spatial connectivity, inhibition, homeostasis, neuromodulation, etc.). The parser produces structured `ParseResult` with error details via `ErrorDetail` objects, and the grammar specification is documented in `cnl_grammar.md`.

## Consequences
- **Positive:** Regex patterns are fast, dependency-free, and easy to extend for new concept families; deterministic parsing produces reproducible results.
- **Negative:** Complex sentence structures may require increasingly unwieldy regex patterns; lacks the composability and error recovery of a proper parser combinator or grammar toolkit.

## Status Update (2026-07-16 audit)
This describes a regex-pattern-matching parser across "19 concept families" documented in a `cnl_grammar.md`. That architecture was superseded — `neurocnl/neurocnl/cnl/__init__.py` now states the NIR-native parser replaced it and the old `neurocnl.nir_cnl.grammar` module was deleted. The real parser today is `NIR_CNL_Parser` in `neurocnl/neurocnl/nir_cnl/parser.py` (tokenizer + Define/Connect sentence dispatch); `neurocnl/neurocnl/pipeline.py`'s `parse_spec_text` (around line 206-249) is a thin backward-compat adapter over it. `cnl_grammar.md` no longer exists under `neurocnl/neurocnl/cnl/`, though several other docs (`sonnet-explains-cnl.md`, `cnl_expansion_plan.md`, `agent_execution_guide.md`, `cnl_hardware_semantics_plan.md`, `cnl_explained.md`) still reference it as current — those are a separate, larger doc-drift problem outside this audit's scope, flagged only, not fixed here.
