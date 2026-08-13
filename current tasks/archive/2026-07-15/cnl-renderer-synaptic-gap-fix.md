# Fix: CNL renderer/compiler never supported Synaptic/RSynaptic/Leaky/RLeaky neurons

## Problem
The earlier `spike_grad` threading fix (this morning's task) deployed correctly, but the user
kept hitting the same `loss_val.backward()` "does not require grad and does not have a grad_fn"
error on a freshly regenerated notebook. Ground truth from the actual generated notebook showed
the embedded `cnl_spec` text contained `# unsupported node type Synaptic for node cnl.Synaptic_...`
comments — the CNL renderer silently dropped both Synaptic neurons (and every edge touching them)
when serializing the canvas graph to CNL text, so `compile_to_nir(cnl_spec)` rebuilt a
disconnected 2-node graph and the generated `forward()` fell back to passing the raw input straight
through with no differentiable ops at all.

## Root cause
`neurocnl/neurocnl/nir_cnl/grammar_tables.py`'s `primitive_phrases`/`parameter_phrases` (the
single shared source of truth for the renderer AND parser) never had entries for `Synaptic`,
`RSynaptic`, `Leaky`, `RLeaky` — even though `notebook.py` codegen has always fully supported all
four. `NIR_Renderer.render()` comments out any node type missing from `primitive_phrases` instead
of erroring, silently violating `compile_to_nir`'s own documented "fail-closed" contract. The
construction-side gap was `nir_cnl/compiler.py`'s `_BUILDERS` dispatch dict, which also had no
entries for these four types.

## Fix
- `grammar_tables.py`: added `primitive_phrases`/`parameter_phrases` entries for all four types,
  covering `n_neurons`/`alpha`/`beta`/`threshold` (the fields every real instance always has a
  concrete value for). Deliberately did NOT expose `reset_mechanism` (string enum — no ParamKind
  exists for that yet), `use_bias`/`recurrent_weight` (RSynaptic/RLeaky-only, nullable — unlike
  every other field in the whole grammar) — these fall back to their dataclass defaults
  (`"subtract"`, `False`, `None`) on round-trip, an accepted, documented limitation since every
  workspace seen so far leaves them at those defaults anyway.
- `nir_cnl/compiler.py`: added `_build_synaptic`/`_build_rsynaptic`/`_build_leaky`/`_build_rleaky`
  (constructing real `neurocnl.runtime.cnl_nodes.*` instances, not `nir.*` — these are
  CNL-Studio's own extension types), registered in `_BUILDERS`. Added a `_scalar()` helper since
  `_resolve_param`'s "vector" kind always returns an `ndarray` (nir.* neuron fields are
  per-population arrays) but these dataclasses declare plain `float` fields.
- No changes needed to `renderer.py` or `parser.py` — both are fully data-driven off the shared
  tables.
- Updated `test_grammar_tables.py`'s hardcoded "exactly 18 primitives" invariant to 22.
- New tests: `test_render_synaptic`/`_rsynaptic`/`_leaky`/`_rleaky`, a
  "never marked unsupported" test covering all four together, a full render→reparse round-trip
  test (`test_renderer_examples.py`), and an end-to-end backend test going
  render→compile_to_nir→`_generate_snntorch_code` and asserting `forward()` actually calls the
  neuron layers, not a passthrough (`backend/tests/test_notebook_codegen.py`).

## Verification
- Manually confirmed against the user's exact architecture
  (`Input→Linear→Synaptic(40)→Linear→Synaptic(7)→Output`): renders with zero `unsupported` lines,
  round-trips through `compile_to_nir` to the same 6 nodes / 5 edges.
- `neurocnl/neurocnl`: `pytest -p no:nengo tests/nir_native_cnl/` — 136 passed (up from 130
  baseline + my 6 new tests), same 6 pre-existing/unrelated failures as baseline (confirmed via
  `git stash` comparison: 3 tensor-value round-trip bugs in `Affine`/`IF` fixtures, 2 pre-existing
  hypothesis property-test failures — none touch Synaptic/RSynaptic/Leaky/RLeaky).
- `neurocnl/backend`: `pytest -p no:nengo tests/test_notebook_codegen.py
  tests/test_notebook_generate_v2.py` — 137 passed, same 3 pre-existing/unrelated failures as this
  morning's baseline.
- `ruff check`/`ruff format` clean on all touched files.
- Not yet verified against the actual running remote deploy (no SSH access from this session) —
  user should `make docker-ex-m REMOTE_HOST=moosebun2@192.168.2.90`, regenerate the notebook, and
  confirm `loss_val.backward()` no longer raises.
