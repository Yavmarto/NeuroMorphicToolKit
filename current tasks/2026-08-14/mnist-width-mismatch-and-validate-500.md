# MNIST width mismatch, the Validate 500 that hid it, and two silent size bugs

**Reported.** Training `z2mnist-latest.nmtk` on snnTorch died with

```
RuntimeError: mat1 and mat2 shapes cannot be multiplied (128x784 and 32x4)
```

and the user's observation was exact: *"the resulting notebook does not seem to contain 128x784."*
It doesn't. `128` is the Data Loader's `batch_size`; `784` is read from the `.pt` file at runtime.

## What was actually wrong

The canvas was `Input(32) → LIF(32) → Linear(rows=4, cols=32) → LIF(4) → Output(4)` — verbatim the
PYNQ guide's *"Smallest useful shape — `32 → 4`"* table, which that guide introduces as **board
bring-up** and for which it names no dataset at all. The Data Loaders pointed at the MNIST guide's
`(N, 784)` files. The model and the data had never been compatible.

Three independent defects let that reach a traceback.

### 1. Nothing compared dataset width to model input width

`nir.Input` is an explicit no-op in codegen (`notebook.py`, `if isinstance(node, nir.Input | nir.Output): pass`)
— it emits no module, no assertion, no reshape. `nir.LIF` becomes `snn.Leaky`, which is elementwise
and takes no size argument, so 784 values pass a 32-neuron LIF untouched. The first width-bound
module is the `nn.Linear`, which is where it finally fails. The one helper that could have read the
declared width, `_endpoint_shape_literal`, had **zero callers** — dead since it was written.

`propagate_nir_sizes` already existed and raises a good message for layer-vs-layer disagreement, but
it is wired only into the deploy-IR builder and the canvas preview, and it would not have caught this
graph anyway: Input=32 and Linear `cols`=32 **agree**. The mismatch was external to the graph.

### 2. Validate answered a bare 500 for a perfectly legal spec

Five links, and the workspace had recorded the symptom itself
(`"Validate failed: ApiException(500): {"detail":"Internal Server Error"}"`):

1. Canvas-authored CNL declares LIF params shape-only — `with time constant shape (32,), …` — which
   parses to `ArraySpec`: a shape carrying **no values**.
2. `layer1_validator` flattened params by unwrapping `ArrayValues`, and passed `ArraySpec` through as
   the object.
3. `nir_lif_time_constant_positive` does `float(np.atleast_1d(tau)[0])` → `TypeError`.
4. A bare `except Exception` turned that into a failure dict keyed `invariant/node/primitive/reason` —
   **no `name`** — and `normalize_cnl_error_item` never synthesised one.
5. `InvariantResult(**f)` requires `name` → unhandled `pydantic.ValidationError` → HTTP 500.

**This was general, not `ArraySpec`-specific.** The ordinary violation branch and the Affine
all-zero warning branch also omitted `name`, so *any* layer-1 NIR failure 500'd. Layer 2 was safe
only because `ErrorDetail.name` happens to be optional.

### 3. Population sizes were looked up case-sensitively, so they never applied

Found while building the replacement workspaces. `import_ir_from_nir` keys populations lower-cased
(`nir.lif_1`); both the NIR graph and `propagate_nir_sizes` use the CNL's spelling (`nir.LIF_1`). A
plain `.get()` missed **every node with a capital letter — i.e. every node the canvas creates.** Two
silent consequences: propagated sizes were never written, and the canvas fell back to reading a LIF's
size off its scalar `tau`, reporting **1 neuron for a 784-neuron layer**.

`_apply_propagated_population_sizes`'s docstring claimed it kept the canvas consistent with deploy.
It had never done so for a canvas-authored network.

This also explains the shape-only workaround: declaring `time constant shape (784,)` is the only way
to get sizes right, and it discards tau/threshold values — the other known defect. With the lookup
fixed, the scalar form gives **both** real values and inferred sizes.

## What changed

| Area | Change |
|---|---|
| `neurocnl/training/dataset_loader.py` | New `pt_feature_width()` — shape-only probe of a `.pt` dataset, memory-mapped where PyTorch allows, mirroring `_load_pt_dataset`'s three layouts. Returns `None` rather than raising for anything unreadable. |
| `backend/app/routers/notebook.py` | New preflight `_check_input_width_against_datasets()` in `_generate_notebook_v2_inner`, before `_collect_uploaded_dataset_artifacts` rewrites paths. Reports the port-level mismatch first, then propagates the real arriving width to name the specific layer. Plus a runtime backstop emitted into `forward()` for the cases the probe must skip. |
| `backend/app/utils/cnl_errors.py` | `name` synthesised as `<node>/<invariant>`, matching the tag layer-1 already uses for passing invariants; `invariant` added to the `code` derivation so failures stop collapsing to `cnl_error`. |
| `neurocnl/layers/layer1_validator.py` | A valueless `ArraySpec` is dropped rather than forwarded — every invariant already skips a missing param. |
| `backend/app/routers/validate.py` | Wrapped so no unexpected failure can answer a bare 500 again. |
| `neurosim/app/services/canonical_editor_projection.py` | New `_population_for()` resolves populations case-insensitively; used by both the size fix-up and the canvas projection. |
| `current tasks/2026-08-13/GUIDE-pynq-z2-hardware.md` | §4b.2 now states that `32 → 4` is not for MNIST and that no 32-feature MNIST exists. |

**Deliberate non-goal: the guard never blocks on a failed probe.** Tonic datasets, `npy`, client-scope
paths and missing files all skip silently. A check that cannot see the data has nothing to say about
it, and turning a failed read into a refusal would break every run it cannot inspect. The in-notebook
assertion is what covers those.

## Two workspaces, not one

Akida and PYNQ cannot share a canvas:

- Akida fuses each LIF into the preceding `Linear` as its activation, so a port-fed LIF raises
  `AkidaConversionError`; its 256-neuron per-layer cap also rejects a 784-wide leading LIF.
- PYNQ needs that leading LIF, because a `Linear` fed from a port is the fixed DMA path.

So `workspaces/pynq-mnist-784-256-10.nmtk` (LIF-first, NIR Exporter) and
`workspaces/akida-mnist-784-256-10.nmtk` (Linear-first, Akida Exporter) were generated through the
app's own `canonical_from_cnl` projection. `z2mnist-latest.nmtk` was **left untouched** — `workspaces/`
is gitignored, so overwriting it would have destroyed the only copy.

Both also fix a methodology bug inherited from the template: the Validation Loop was fed
`mnist_test.pt`, selecting best checkpoints on the test set. It now gets `mnist_val.pt`.

**A trap worth remembering:** the Akida canvas *passes* PYNQ's Network fit, but reports 266 neurons
across 2 populations instead of 1050 across 3 — the 784×256 matrix silently read as the DMA path. A
green fit check does not mean the whole network is on the board.

## Verified

- The original spec that returned 500 now validates: layer1 overall `True`, 9 invariants passed, and
  every result constructs an `InvariantResult`.
- The reported bug is refused at generation with both numbers and both sources named; the emitted
  notebook additionally carries `if _x_seq.shape[-1] != 784:` with a message naming the Input port.
- No false blocks: tonic, `npy`, absent-file and unreadable-file cases all still generate. CNN graphs
  were an early false positive — width tracking now stops at any node that is not provably
  width-preserving, so `Conv2d → SumPool2d → Flatten → Linear` is left alone.
- Both workspaces validate clean, plan `exportable` for their own target, and generate
  `nn.Linear(784, 256)` / `nn.Linear(256, 10)`.
- Akida correctly refuses the PYNQ variant with `exceeds_np_size`.
- New tests: 5 in `test_notebook_generate_v2.py`, 2 in `test_validate_router.py`, 4 in
  `test_dataset_loader.py`, 2 in `test_canonical_editor_projection.py`.
- Suites compared against HEAD in a throwaway worktree: backend 3 failures at HEAD and 3 after,
  `neurosim` 5 and 5, `nir_native_cnl`+`layers` 12 and 12 — identical sets, no regressions.

## Left open

- **One canvas for both targets.** Teach the Akida path that a LIF whose only predecessor is
  `nir.Input` is input encoding rather than a layer: skip it in `nir_to_akida` and let
  `quantize_inputs` do that job, exempt it from `MAX_NEURONS_PER_NP`, and pass `exclude_ports=True`
  to the Akida synapse estimate as the PYNQ path already does. Requires rewriting the test that
  currently asserts the raise.
- **`weight_bits = 8`** converts locally and then fails the deploy gate, which allows only 1/2/4.
- **In-app dataset preparation**, to retire the terminal-only `prepare_mnist_pt.py`.
- **PYNQ bitstream** — still the one hard blocker; see the new guide's §6.
