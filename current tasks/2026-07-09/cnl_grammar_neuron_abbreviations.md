# CNL grammar: abbreviate neuron-model names

## What
The NIR-native CNL grammar (in the `neurocnl` submodule) spelled out neuron-model
primitives in full English in every generated sentence, e.g.:

> Define a leaky integrate-and-fire neuron named hidden with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.

Changed the six neuron-model primitives to use their standard short names instead:

| Class | Old phrase | New phrase |
|---|---|---|
| `IF` | integrate-and-fire neuron | IF neuron |
| `LIF` | leaky integrate-and-fire neuron | LIF neuron |
| `LI` | leaky integrator neuron | LI neuron |
| `CubaLIF` | current-based leaky integrate-and-fire neuron | CubaLIF neuron |
| `CubaLI` | current-based leaky integrator neuron | CubaLI neuron |
| `I` | integrator neuron | I neuron |

Sentence structure, parameter phrases, and all non-neuron primitives (Linear, Conv2d,
Affine, etc.) are unchanged. Hard cutover — parser no longer accepts the old spelled-out
phrases.

## Where
- Grammar core: `neurocnl/neurocnl/nir_cnl/grammar_tables.py` (source of truth), plus
  docstring-only touch-ups in `renderer.py`/`parser.py`/`validator.py`.
- Functional fix: `neurocnl/backend/app/services/neurocnl_bridge.py` had a hardcoded
  copy of the old phrase in two provenance messages — updated to match.
- Product-facing `.cnl` templates: all 16 files under `neurocnl/backend/app/templates/`.
- Product-facing component/template JSON: `neurocnl/neurosim/components/neurons/*.json`,
  `neurocnl/neurosim/templates/{cpg_oscillator,reflex_arc}.json`.
- ~45 files total changed (see `git status` in the `neurocnl` submodule); the rest are
  test fixtures/goldens updated to match.

## Verification
- `neurocnl/tests/nir_native_cnl`, `test_nir_to_cnl.py`, `test_compile.py`,
  `test_array_serialisation.py`: green except 6 pre-existing, unrelated failures (a
  vector round-trip bug where non-uniform arrays >1 element lose values — exists on
  main, confirmed via `git stash` bisection before touching anything).
- `backend/tests/*`: green except 8 pre-existing failures (missing `snntorch` module,
  missing test-fixture `.nir` data file, a `voltages` attribute bug on a Lava mock, a
  backend-count drift in `/api/simulators/capabilities`).
- `neurosim/tests`: green except 9 pre-existing failures (a `PortType` pydantic
  validation bug in `validation_service.py`, missing optional `nmtk_sdk` dependency,
  same vector round-trip inconsistency as above).
- `ruff check` and `mypy` clean on all touched source files.
- Full repo grep for the old phrases returns zero hits except one docstring in
  `neurocnl/runtime/cnl_nodes.py` that describes the LIF neuron model in prose
  (not a rendered grammar phrase) — left as is intentionally.

## Not done (out of scope, pre-existing)
The vector round-trip / `PortType` pydantic / missing-dependency failures above are
unrelated bugs discovered during verification, not touched by this change.
