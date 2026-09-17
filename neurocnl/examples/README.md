# Examples

These examples demonstrate how to use the neurocnl pipeline step by step. Run them from the repository root.

## Prerequisites

```bash
python3 -m venv neurocnl-env
source neurocnl-env/bin/activate
pip install -r requirements.txt
```

## Examples

Numbering starts at 3: `01_parse_spec.py` and `02_validate_spec.py` were removed —
both imported `cnl_parser`, a per-sentence legacy parser module deleted repo-wide
during the `nir_cnl` migration, so neither one ran anymore. Examples 3 and 4 below
cover parsing, validation, simulation, training, and export against the current
`nir_cnl` architecture end to end.

### 3. Generate a Notebook from CNL and Actually Train It

Runs the full pipeline end to end with no server, Docker, or Flutter app required:
CNL spec → `compile_to_nir` → `_build_v2_notebook` (real snnTorch codegen) → executed for
real against the bundled braille dataset (`paper/03_rnn/data/*.pt`). Trains a small
12-in/48-hidden/7-out feedforward SNN and asserts the loss actually drops and the held-out
accuracy clearly beats the 1/7 chance baseline.

```bash
cd neurocnl && PYTHONPATH=. .venv/bin/python3 examples/03_generate_and_train_braille.py
```

Requires a venv with `torch`, `snntorch`, `numpy`, `nir`, `fastapi`, `pydantic`,
`sse-starlette`, `slowapi`, `aiosqlite`, `structlog`, `prometheus-client`, `httpx`, and
`nengo` installed — `neurocnl/.venv` (gitignored) is set up this way; the repo's default
`.test-venv` does not include `torch`.

The generated notebook and its weight artifacts are written to `examples/output/`
(gitignored) and can also be opened directly in Jupyter.

### 4. Full Pipeline Proof-of-Concept

The simplest complete demonstration of every real nmtk pipeline stage in one script,
no server/Docker/Flutter required: **Compile** (`compile_to_nir`) → **Validate**
(`NIR_CNL_Parser` + Layer 1/2 `validate_nir_records`) → **Simulate** (a quick
fixed-weight sanity check via `generate_default_stimulus` +
`SnnTorchSimulatorAdapter`, proving the network isn't dead before spending time
training it) → **Train + Eval** (same real training as example 3) → **Export**
(`nir.write` + `NengoIO().from_nir`, a portable `.nir` file and generated Nengo
Python code). Hardware deploy (Teensy/PYNQ/Lava/Akida) is not reachable from this
NIR-native graph today — that deploy path only operates on the legacy grammar — so
export is this POC's deploy capstone instead.

```bash
cd neurocnl && PYTHONPATH=. .venv/bin/python3 examples/04_full_pipeline_poc.py
```

Same venv requirements as example 3 — no new packages needed. Writes the notebook,
a `.nir` file, generated Nengo code, and a `pipeline_report.json` summarizing every
step's results, all under `examples/output/` (gitignored).

## CNL Spec Files

- **`reflex_arc.cnl`** — Standard reflex arc specification using default sentence forms.
- **`custom_params.cnl`** — Alternative phrasing demonstrating grammar flexibility.

These `.cnl` files use the legacy, biological-style grammar (`MUST`/`WITH` sentences)
parsed by `neurocnl.pipeline.parse_spec_text` / `neurocnl.cnl.document` — a separate
pipeline from the `nir_cnl` dialect that `compile_to_nir`/examples 3 and 4 above use.
`compile_to_nir` rejects this grammar outright with an actionable `legacy_grammar`
error if you try to run one of these files through it. No script in this directory
currently drives these two files — they're kept as reference grammar samples.

## Full Simulation Pipeline (legacy grammar only)

`neurocnl/neurocnl/simulation/run_simulation.py` chains parse → Layer 1/2 validate →
simulate → assertion-check for the legacy `MUST`/`WITH` grammar, producing a
`simulation_report.json`. Its own docstring references a `neurocnl/simulation/reflex_arc.cnl`
that doesn't exist in this repo; point it at an existing legacy-grammar file instead, e.g.:

```bash
python neurocnl/simulation/run_simulation.py neurocnl/examples/reflex_arc.cnl
```

This is a different, older pipeline from examples 3/4 above — not a base to build on
for `nir_cnl` work.
