# Playbook: making a CNLStudio-generated notebook match its reference notebook

Written after fixing `paper/02_cnn/gen_snn.ipynb` (was 9.8% accuracy, should be
~98%). That fix is done — this doc is the reusable *method*, for applying to
the other 4 notebooks: `01_lif/lif_snntorch.ipynb`,
`03_rnn/Braille_training_snntorch.ipynb`,
`03_rnn/snntorch_apply_subtract.ipynb`, `03_rnn/nengo_apply.ipynb`.

Background doc: `docs/current-tasks`-style analysis at
`neurocnl/docs/current-tasks` is NOT it — the relevant one is
`docs/current tasks/16 june/cnlstudio_notebook_analysis.md` (repo root), which
describes all 6 paper notebooks and why each is/isn't reproducible in
CNLStudio.

## The core idea

Every "reference" notebook in `paper/**` loads a pre-trained network from a
`.nir` file (or an equivalent framework export) using some **oracle**
importer — e.g. `snntorch.import_nir.import_from_nir`, or a Nengo/Norse
equivalent. CNLStudio's backend (`neurocnl/backend/app/routers/notebook.py`,
functions like `_generate_snntorch_code`) independently re-implements that
same NIR→framework mapping by hand, node type by node type. Every place where
CNLStudio's hand-rolled mapping diverges from what the oracle importer
actually does for the same NIR node type is a latent bug — usually a
hardcoded constant (a decay factor, a reset flag, a pooling divisor) that
looks reasonable in isolation but doesn't match the oracle's numeric
convention. These bugs are silent: the notebook runs fine, it just produces
wrong/degraded results.

**The fix is never "make the physics more correct" — it's "make the codegen
bit-match whatever the installed oracle library actually does."** Even if the
oracle's choice looks like an unmotivated hack (e.g. `beta=0.9` for a
supposedly-zero-leak IF neuron), match it anyway, because that's what the
weights were implicitly trained/exported against.

## Step-by-step method

### 0. Get a CNLStudio-generated notebook to compare against

For `paper/02_cnn`, `gen_snn.ipynb` already existed (the user had generated it
earlier via CNLStudio). For the other 4, no `gen_*.ipynb` exists yet — you
have to produce one first. You do **not** need the Flutter UI running for
this; call the backend codegen directly in Python:

```python
import sys
sys.path.insert(0, "neurocnl")            # repo root package
sys.path.insert(0, "neurocnl/backend")    # FastAPI app package
import nir
from app.routers.notebook import _generate_snntorch_code  # or the relevant _generate_*_code

graph = nir.read("paper/0X_.../whatever.nir")   # or compile_to_nir(cnl_spec) if no .nir file
code, weights = _generate_snntorch_code(graph)
```

If the target uses NIR-import (`.nir` file present, e.g. `lif_norse.nir`,
`braille_*.nir`), read that file directly with `nir.read(...)` — that gives
you the *real* trained weights/params, not shape-only placeholders. This
matters: `compile_to_nir(cnl_spec)` on a hand-typed CNL spec (like the one
embedded in `gen_snn.ipynb`) only encodes shapes, not real numeric values —
fine for checking generated *source code*, useless for checking *accuracy*.

Check `docs/current tasks/16 june/cnlstudio_notebook_analysis.md` for which
`.nir`/checkpoint file backs each target notebook (e.g. `lif_norse.nir` for
notebook 1, `braille_noDelay_noBias_subtract.nir` for notebooks 3-5 — verify
the exact filename exists in that notebook's directory before assuming).

For RNN/RSynaptic notebooks there may be no `.nir` export at all (weights come
from a `.pt` checkpoint instead) — in that case the "graph" comes from
whatever in-repo path already builds the `nir.NIRGraph`/CNL spec for that
architecture (check `neurocnl/backend/app/services/nir_graph_serializer.py`
for how `cnl.RSynaptic`/`cnl.Synaptic` round-trip).

### 1. Establish ground truth: run the reference notebook and log the real accuracy

Before touching any code, execute the actual reference notebook
(`lif_snntorch.ipynb`, `Braille_training_snntorch.ipynb`,
`snntorch_apply_subtract.ipynb`, `nengo_apply.ipynb`) end-to-end and record
what it actually gets *today*, in your actual environment. Don't trust a
number quoted in a stale doc or a cached notebook output — library versions
drift (see below) and can shift results by a percent or two. This run is your
target to match, and also your environment sanity check.

### 2. Find the oracle importer for this target's node types

- snnTorch targets: `snntorch/import_nir.py`, function
  `_nir_to_snntorch_module`. This is what you diff against for
  `lif_snntorch.ipynb`, `Braille_training_snntorch.ipynb`,
  `snntorch_apply_subtract.ipynb` (all snnTorch-based).
- Nengo target (`nengo_apply.ipynb`): there is **no** snnTorch oracle to
  compare against — it uses a NIR→Nengo converter (`nir_to_nengo`, see
  `paper/03_rnn/nengo_import.py` and the codegen's
  `neurocnl/backend/app/services/nengo_code_exporter.py`). Diff CNLStudio's
  Nengo codegen against `nir_to_nengo.py`'s actual per-node-type conversion
  logic instead of snntorch's.
- **Important gotcha discovered while fixing notebook 2**: multiple
  `snntorch`/`nir` versions are installed side-by-side on this machine
  (pyenv 3.11.9, python3.8, homebrew python3.11, anaconda python3.12), and
  they are NOT equivalent — e.g. `nir` 1.0.1 (paired with snntorch 0.9.1,
  `python3.8`) doesn't even have an `AvgPool2d` class, only `SumPool2d`; a
  newer `nir`/snntorch pair does have both, and its `import_nir.py` had
  silently dropped `SumPool2d` handling entirely. **Always check which
  snntorch/nir version pairing corresponds to the environment the reference
  notebook was actually written for** (usually the oldest one available,
  e.g. `python3.8` here — `paper/02_cnn/run_fixed_replication.py`'s header
  comment said so explicitly; look for a similar hint per notebook, or just
  try each environment and see which one's oracle behavior reproduces the
  documented/expected accuracy).

To find installed copies quickly:
```bash
find / -name "import_nir.py" -path "*snntorch*" 2>/dev/null
```
then `grep -n -i "pool\|isinstance(node, nir\." <that file>` to see every node
type it actually handles, and read each branch's exact `snn.<Neuron>(...)` or
`torch.nn.<Layer>(...)` call — constructor keyword by constructor keyword.

### 3. Diff CNLStudio's codegen against the oracle, node type by node type

In `neurocnl/backend/app/routers/notebook.py`, for the relevant `_generate_*_code`
function, find every `isinstance(node, nir.X)` branch relevant to this
notebook's architecture and compare it line-by-line against the oracle's
branch for the same `nir.X` type. Things that bit us in notebook 2 — check
all of these for every node type, not just the "obvious" ones:

- Decay/leak constants (`beta`, `alpha`, `tau`→`beta` conversion formula).
- Every keyword arg passed to the constructed module, **especially ones the
  oracle sets explicitly and the codegen omits** (defaults differ!). We
  missed `reset_delay=False` this way — `snn.Leaky` defaults to
  `reset_delay=True`, oracle overrides it, codegen didn't.
- Any post-processing the oracle applies (e.g. `divisor_override=1` to turn
  `nn.AvgPool2d` into a true sum — a plain "AvgPool2d with no scale" comment
  in the old code was simply wrong; verify by reading the *actual* code, not
  a comment claiming something is "pre-rescaled" elsewhere).
- Threshold/parameter extraction: does the codegen read the *real* value from
  the node (e.g. `node.v_threshold`), or silently substitute the CLI/UI
  default because the attribute lookup failed? (`_scalar()` helper — check
  its default value isn't masking a real value.)
- Calling convention consistency between `__init__` (module construction) and
  `forward()` (how the module is invoked in the loop) — e.g. `init_hidden=True`
  modules must be called with a single return value in the loop, not threaded
  external membrane state, or you get silent wrong results or a crash.

Don't stop at the first fix and declare victory — bugs compound. In notebook
2 there were **three** independent hardcoded-constant mismatches
(`beta`, `reset_delay`, pooling `divisor_override`), and fixing only one moved
accuracy from 9.8% → 79% → 88% → 97.97%, each fix looking like "solved" until
the next end-to-end run showed it wasn't. Re-run end-to-end after *every*
individual fix, not once at the end.

### 4. Patch, add a regression test, re-verify unit-level

- Edit the relevant `elif isinstance(node, nir.X):` block in `notebook.py`.
- Add a short comment explaining *why* the value must be that constant
  (cite the oracle file/function) — this is exactly the kind of non-obvious
  fact that isn't derivable from re-reading the diff later.
- Update/add a unit test in `neurocnl/backend/tests/test_notebook_generate_v2.py`
  (or `test_notebook_codegen.py`) asserting the exact generated source line.
  Small synthetic `nir.NIRGraph` fixtures are fine — you don't need real
  weights to check generated *code*, only to check *accuracy*.
- Run `ruff check` + the test file from inside `neurocnl/`:
  ```bash
  cd neurocnl
  ruff check backend/app/routers/notebook.py backend/tests/test_notebook_generate_v2.py
  python3 -m pytest backend/tests/test_notebook_generate_v2.py -q
  ```
  There is a large pre-existing unrelated diff/WIP already sitting in this
  submodule (150+ modified files, not yours) — don't touch it, and don't be
  alarmed if `git diff` on your two files shows extra unrelated-looking
  reformatting; that's the pre-existing state, not something you introduced.
  Confirm with `git stash`/`git stash pop` around a failing test if unsure
  whether a failure pre-dates your change.

### 5. Regenerate the actual notebook artifact and execute it end-to-end

`paper/**` is fully gitignored at the repo root (`.gitignore` line "paper") —
you can freely write `weights.npz`, download datasets, regenerate/execute
notebooks there without worrying about git noise. Nothing there needs to be
committed.

To regenerate a `gen_*.ipynb`'s architecture cell + weights after patching
`notebook.py`, call `_generate_snntorch_code(real_graph)` (or the relevant
generator) again and splice its output into the notebook JSON's code cell
(`json.load`/`json.dump` on the `.ipynb`, cell `source` is a list of lines).
Don't hand-edit only the `.ipynb` and skip the generator source — the
generator is the thing that must be fixed; the notebook file is just the
artifact you use to verify it end-to-end.

To actually execute a notebook (no Jupyter kernel is registered for the env
with all the SNN deps by default):
```bash
# 1. find an env with snntorch + tonic + nir + jupyter/nbconvert + ipykernel
for py in python3.8 /Users/yoshimartodihardjo/.pyenv/versions/3.11.9/bin/python3; do
  $py -c "import snntorch, tonic, torch, nir, jupyter" && echo "$py OK"
done

# 2. register a throwaway kernel for whichever env has the deps
<env-python> -m ipykernel install --user --name nmtk-fix-verify --display-name nmtk-fix-verify

# 3. execute (PYTHONPATH needed if neurocnl isn't pip-installed in that env)
cd paper/0X_whatever
PYTHONPATH=/Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl \
  <env-python> -m nbconvert --to notebook --execute --inplace \
  --ExecutePreprocessor.kernel_name=nmtk-fix-verify \
  --ExecutePreprocessor.timeout=1800 \
  the_notebook.ipynb

# 4. clean up the throwaway kernel when fully done with all 4 notebooks
jupyter kernelspec remove -f nmtk-fix-verify
```
Use `python3 -m nbconvert` (not `python3 -m jupyter nbconvert`) — the latter
can dispatch to a *different* Python's `jupyter-nbconvert` found on `$PATH`
(bit us: it silently ran under anaconda's Python even though we specified
pyenv). Long executions (full NMNIST eval took ~13 minutes under python3.8):
background the process and poll/monitor rather than blocking, since these
runs are slow enough to need it.

Then diff the notebook's final accuracy/metric cell against the reference
run's number from Step 1. They should match within normal statistical noise
(we saw 97.97% vs 97.99% — a rerun with different batch order/float rounding,
not a real discrepancy).

## Per-notebook notes

- **`01_lif/lif_snntorch.ipynb`**: single LIF neuron from `lif_norse.nir`
  (trained in Norse, not sinabs — the NIR node might be `nir.LIF` proper
  rather than `nir.IF`, so re-check the `nir.LIF` branch's `beta`/`tau`
  formula against the oracle, not just the `nir.IF` one we already fixed).
  Per the CNLStudio analysis doc this notebook also needs a Spike Generator
  + Spike Rate Logger to fully round-trip through the UI — those are
  UI/canvas features, separate from the codegen-correctness bug hunt this
  playbook is about. Focus only on: does the *snnTorch codegen* correctly
  reconstruct the LIF neuron's dynamics from `lif_norse.nir`.
- **`03_rnn/Braille_training_snntorch.ipynb`** and
  **`03_rnn/snntorch_apply_subtract.ipynb`**: these use `cnl.RSynaptic` /
  `cnl.Synaptic` (recurrent, 2-3 hidden states), a different code path in
  `notebook.py` than the plain `nir.IF`/`nir.LIF` branch (see
  `CnlRSynaptic`/`CnlSynaptic` handling and the "recurrent kinds" temporal
  loop). The oracle for these is `import_nir.py`'s `nir.CubaLIF`-in-subgraph
  branch (`_parse_rnn_subgraph`) — same method (diff constructor kwargs and
  the `hack_w_scale` weight-rescaling logic) applies, but the code shape is
  different from the conv/IF case. `reset_mechanism="subtract"` here (not
  "zero"/default) — double check the codegen doesn't hardcode the wrong
  reset mechanism, since notebook 2 didn't need this but these notebooks are
  named specifically for the "subtract" reset.
- **`03_rnn/nengo_apply.ipynb`**: different oracle entirely (Nengo, not
  snnTorch) — see the "Nengo target" bullet in Step 2. Also note this
  notebook's CNLStudio viability was rated only "MODERATE" in the analysis
  doc (the `nir_to_nengo` converter's `cnl.RSynaptic` handling was flagged as
  still-moderate-effort) — it may have a real missing-feature gap, not just
  a hardcoded-constant bug like the other three. Check whether the Nengo
  codegen path exists and runs at all before assuming it's a numeric
  mismatch.

## Non-goals / guardrails

- Don't touch the pre-existing large uncommitted diff already sitting in the
  `neurocnl` submodule — it's unrelated in-progress work, not yours to
  resolve or revert.
- Don't commit anything unless explicitly asked.
- Don't modify `neurocnl/neurocnl/nir_cnl/compiler.py`'s CNL grammar or
  `layers/layer1_invariants.py` — per `neurocnl/AGENTS.md` those require
  explicit human approval and are out of scope for this kind of codegen bug.
- Read `AGENTS.md` and `CODING_STYLE_GUIDE.md` (repo root) and
  `neurocnl/AGENTS.md` before editing, same as any other task in this repo.
