# ADR-0026: Canvas-Driven Notebook Generation — Empty Canvas Means No Code

**Status:** Accepted  
**Date:** 2026-06-21

## Context

The `generate-v2` notebook endpoint (`POST /api/notebook/generate-v2`) in `neurocnl/backend/app/routers/notebook.py` contained a flat-config fallback that fired whenever `pipeline_phases` was `None`. This produced hundreds of lines of hardcoded training, evaluation, and inference boilerplate regardless of whether the user had drawn anything on the pipeline phases canvas. The result: a notebook full of guessed code the user never configured, including:

- A hardcoded training loop (surrogate-gradient, BPTT, or rate-coding) per framework
- A hardcoded evaluation cell keyed on `cfg.run_evaluation`
- A hardcoded infer/export cell
- An unconditional `_nmtk_emit` helper function
- An unconditional NMNIST/N-TIDIGITS dataset loading cell (which silently added `torchneuromorphic` as a juv dependency for any NIR file regardless of whether training was configured)

Additionally, NIR node names starting with digits (e.g. `"0"`, `"1"`) produced invalid Python identifiers (`0 = nn.Linear(…)`) and the snnTorch architecture cell emitted loose variable assignments rather than a proper `nn.Module`, causing `net.parameters()` to NameError in downstream cells.

## Decision

1. **Empty canvas = no code.** The entire flat-config `else` branch was deleted. When `pipeline_phases is None`, no train/eval/infer cells are emitted. The notebook contains only: juv deps, title, config, architecture CNL cell, framework Net class.

2. **Dataset loading and `_nmtk_emit` are phase-conditional.** Both cells are now emitted only inside the `if pipeline_phases:` block, keeping them absent when no phases are configured.

3. **`torchneuromorphic` dep is phase-conditional.** Added to juv deps only when `pipeline_phases` has train or eval nodes AND `cfg.dataset` is NMNIST or N-TIDIGITS.

4. **`_generate_snntorch_code` emits a proper `nn.Module`.** The function was rewritten to produce a `class Net(nn.Module)` with layers as `self.layer_x` attributes and a `forward(x, num_steps)` method derived from graph edges. `net = Net()` is emitted at the end so all downstream cells can call `net.parameters()`, `net.train()`, and `net.eval()`.

5. **`_node_var()` helper guards against digit-starting identifiers.** A central `_node_var(name)` function prefixes `"layer_"` when the slugified name starts with a digit. Used consistently across all code generators.

## Rationale

The pipeline phases canvas is the user's explicit specification of what training/eval/infer code they want. Generating content the user has not configured violates the principle that the notebook should reflect the actual canvas state. The flat-config fallback was a legacy path predating the DAG-based pipeline and has no place in a canvas-driven workflow.

## Consequences

- Notebooks generated from an Architecture-only workflow (no pipeline phases) are minimal and runnable: architecture + Net class only.
- Users who want training cells must draw them on the pipeline phases canvas. There is no auto-generated fallback.
- The flat-config training/eval/infer generators (~500 lines) are removed. Per-framework training scaffolds must be added as DAG node types if needed in future.
- `_nmtk_emit` is never emitted into notebooks without training phase nodes, eliminating dead-code cells.

## Status Update (2026-07-16 audit)

The helper this ADR names, `_node_var()`, does not exist in current code. The actual guard function is `_python_identifier()` at `neurocnl/backend/app/routers/notebook.py` (around lines 452-459), which prefixes `n_` for identifiers starting with a digit — not `layer_` as this ADR states. Behavior and intent are unchanged; only the function name and prefix string differ from what is documented above.
