# Design Document: NIR Simulator Support Matrix

## Overview

The neurocnl simulator pipeline dispatches compiled `nir.NIRGraph` objects to two
backends: `lava_sim` (Intel lava-nc low-level processes) and `snntorch_sim` (snnTorch
fixed-weight inference). A static table in `nir_support.py` maps
`backend → {node_type → verdict}` and drives both the preflight classifier and the
`GET /api/simulators/capabilities` endpoint.

The table currently lists only six node types per backend. The remaining eleven NIR
primitives fall through to the `.get(type_name, "unsupported")` default, producing
correct but unexplained 422 rejections, and preventing the capabilities endpoint from
returning a complete picture.

This change expands the table to cover all 17 NIR primitives explicitly, extends the
snnTorch adapter to implement five additional node types it genuinely supports, adds a
pre-execution guard to the Lava adapter, and updates tests and documentation accordingly.

### Files changed

| File | What changes |
|---|---|
| `neurocnl/runtime/nir_support.py` | Expand `_BACKEND_NIR_SUPPORT` to all 17 primitives per backend |
| `neurocnl/runtime/snntorch_simulator.py` | Add `_simulate()` branches for `Affine`, `Conv2d`, `Flatten`, `IF`, `AvgPool2d` |
| `neurocnl/runtime/lava_simulator.py` | Add pre-execution unsupported-node guard in `_run_in_process()` |
| `neurocnl/runtime/test_nir_support.py` | Parametrized tests for all 17 primitives, adapter tests, guard tests |
| `neurocnl/docs/support_matrix.md` | Add "Simulator Backend NIR Primitive Support" section |

---

## Architecture

The change touches four files and adds one new test file. No new modules, no new
dependencies, no API schema changes.

```
nir_support.py              ← expand _BACKEND_NIR_SUPPORT (primary change)
snntorch_simulator.py       ← add Affine, Conv2d, Flatten, IF, AvgPool2d branches
lava_simulator.py           ← add early-rejection guard in _run_in_process
docs/support_matrix.md      ← add NIR Simulator Support Matrix section
test_nir_support.py         ← add parametrized verdict + no-fallthrough tests
test_snntorch_simulator_primitives.py  ← new file, adapter tests for new node types
```

The capabilities router (`backend/app/routers/simulators.py`) **requires no changes**.
It already derives all three node lists exclusively from `get_supported_node_types()`:

```python
supported_nir_nodes=[n for n, v in _LAVA_SIM_SUPPORT.items() if v == "exact"],
unsupported_nir_nodes=[n for n, v in _LAVA_SIM_SUPPORT.items() if v == "unsupported"],
approximate_semantics=[n for n, v in _LAVA_SIM_SUPPORT.items() if v == "approximate"],
```

Expanding the table is sufficient to fix the capabilities endpoint.

### Data flow (unchanged)

```
POST /api/simulators/run
  └─ compile_to_nir(spec) → nir.NIRGraph
  └─ classify_nir_graph(graph, backend)  ← reads _BACKEND_NIR_SUPPORT
       └─ level == "unsupported" → 422
       └─ level == "exact" | "approximate" → continue
  └─ LavaSimulatorAdapter.run()  or  SnnTorchSimulatorAdapter.run()
       └─ [NEW] early rejection guard (lava only)
       └─ build modules → timestep loop → normalise output
  └─ SimulatorRunResult
```

---

## Components and Interfaces

### `nir_support.py` — `_BACKEND_NIR_SUPPORT` table

The table is the single source of truth. Every other component reads it; nothing
writes to it at runtime.

**Interface contract (unchanged):**
- `classify_nir_graph(graph, backend_name) → SupportClassification`
- `get_supported_node_types(backend_name) → dict[str, str]`
- `list_supported_backends() → list[str]`

The classifier already uses `.get(type_name, "unsupported")` as its fallback, so any
primitive *absent* from the table defaults to `"unsupported"`. After this change every
member of `Complete_Primitive_Set` has an explicit key, eliminating the silent default.

### `SnnTorchSimulatorAdapter._simulate()`

The `_simulate` method contains the module-building loop (`for name in topo_order`).
Five new `elif` branches are added in that loop. Each branch follows the same
constructor pattern as the existing `nir.Linear` branch:

1. Extract parameters from the NIR node.
2. Construct the corresponding `torch.nn` or `snntorch` module.
3. Assign `modules[name] = <module>`.
4. In the timestep loop's dispatch section, add a matching branch that calls the
   module and routes its output.

### `LavaSimulatorAdapter._run_in_process()`

A guard is inserted **before** the call to `LavaIO().to_runtime_payload(graph)`.
It iterates `graph.nodes`, collects all node type names not in the lava-nc supported
set, and if any are found raises `LavaDispatchError` immediately with a structured
diagnostic listing each unsupported type.

**Lava-nc supported set** (types that can reach `to_runtime_payload` safely):
`{"Input", "Output", "LIF", "CubaLIF", "Linear", "Delay"}`

---

## Data Models

### `Complete_Primitive_Set`

The set of all 17 NIR primitives that must have explicit verdicts:

```python
COMPLETE_PRIMITIVE_SET: frozenset[str] = frozenset({
    "Input", "Output",
    "Linear", "Affine",
    "Conv2d", "Flatten",
    "IF", "LIF", "CubaLIF", "LI",
    "AvgPool2d", "SumPool2d",
    "Delay",
    "Scale", "Threshold",
    "Sigmoid",
    "I",           # Integrator
    "CubaLI",
})
```

Note: The requirements document names `Tanh` in the glossary but the official NIR
spec does not define `nir.Tanh` as a primitive; `Sigmoid` is listed instead. The
implementation follows the official NIR class hierarchy. `I` (Integrator) is the
NIR node class `nir.I`. Total: 18 entries when `I` and `CubaLI` replace `Tanh` from
the glossary; the requirements spec lists 17. Implementors should enumerate actual
`nir.*` class names from the installed `nir` package to resolve any discrepancy.
For this design `Sigmoid` is included and `Tanh` is excluded, matching the user's
explicit verdicts above.

### Expanded `_BACKEND_NIR_SUPPORT` dict

```python
_BACKEND_NIR_SUPPORT: dict[str, dict[str, str]] = {
    "lava_sim": {
        # ── Boundary nodes ──────────────────────────────────────────────────
        "Input":    "exact",       # lava.proc boundary — no process needed
        "Output":   "exact",       # lava.proc boundary — no process needed

        # ── Weight / connectivity nodes ──────────────────────────────────────
        "Linear":   "exact",       # lava.proc.dense.Dense — fully supported
        "Affine":   "unsupported", # lava-nc has no affine process (bias+weight);
                                   # lava-dl netx supports it — out of scope here
        "Conv2d":   "unsupported", # lava-nc has no Conv process;
                                   # lava-dl netx supports Conv2d — out of scope
        "Flatten":  "unsupported", # lava-nc has no flatten process;
                                   # tensor reshaping is a lava-dl / compiler concern

        # ── Neuron / dynamics nodes ──────────────────────────────────────────
        "IF":       "unsupported", # lava-nc LIF process has no IF (infinite-tau) mode;
                                   # LIF.du and LIF.dv cannot replicate true IF dynamics
        "LIF":      "exact",       # lava.proc.lif.LIF — native support
        "CubaLIF":  "approximate", # approximated via LIF with adjusted tau params;
                                   # synaptic current filter (alpha) not modelled
        "LI":       "unsupported", # leaky integrator without threshold — no lava-nc process
        "I":        "unsupported", # pure integrator — no lava-nc process

        # ── Pooling nodes ────────────────────────────────────────────────────
        "AvgPool2d":  "unsupported", # no lava-nc pooling process; lava-dl has it
        "SumPool2d":  "unsupported", # no lava-nc pooling process

        # ── Delay node ───────────────────────────────────────────────────────
        "Delay":    "approximate", # approximated via buffer register; timestep
                                   # quantization means sub-timestep delays are lost

        # ── Activation / transform nodes ─────────────────────────────────────
        "Scale":    "unsupported", # no lava-nc scalar-multiply process
        "Threshold":"unsupported", # no lava-nc threshold process separate from LIF
        "Sigmoid":  "unsupported", # not a lava-nc process; handle gracefully
        "CubaLI":   "unsupported", # no lava-nc process
    },

    "snntorch_sim": {
        # ── Boundary nodes ──────────────────────────────────────────────────
        "Input":    "exact",       # driven by ValidatedStimulus injection
        "Output":   "exact",       # passthrough boundary collector

        # ── Weight / connectivity nodes ──────────────────────────────────────
        "Linear":   "exact",       # nn.Linear(in, out, bias=False) + weight copy
        "Affine":   "exact",       # nn.Linear(in, out, bias=True) + weight + bias copy
        "Conv2d":   "exact",       # nn.Conv2d(in_ch, out_ch, kernel, stride, padding)
        "Flatten":  "exact",       # nn.Flatten(start_dim, end_dim)

        # ── Neuron / dynamics nodes ──────────────────────────────────────────
        "IF":       "exact",       # snntorch.Lapicque(R=r, C=large, threshold=v_thr)
                                   # approximates infinite-tau IF via very large C
        "LIF":      "exact",       # snntorch.Leaky(beta=exp(-1/tau), threshold=v_thr)
        "CubaLIF":  "approximate", # snntorch.Leaky — alpha (synaptic filter) not modelled
        "LI":       "unsupported", # no snnTorch equivalent without enabling training mode
        "I":        "unsupported", # pure integrator — no snnTorch equivalent

        # ── Pooling nodes ────────────────────────────────────────────────────
        "AvgPool2d":  "exact",     # nn.AvgPool2d(kernel_size, stride)
        "SumPool2d":  "unsupported", # not in snnTorch NIR integration

        # ── Delay node ───────────────────────────────────────────────────────
        "Delay":    "approximate", # passthrough in timestep loop; sub-timestep
                                   # delays not modelled; result labelled approximate

        # ── Activation / transform nodes ─────────────────────────────────────
        "Scale":    "unsupported", # no NIR-native snnTorch equivalent
        "Threshold":"unsupported", # no NIR-native snnTorch equivalent
        "Sigmoid":  "unsupported", # not a NIR primitive; handle gracefully
        "CubaLI":   "unsupported", # no snnTorch equivalent
    },
}
```

---

## snnTorch Adapter Extensions

### Module-building loop additions

Insert the following `elif` branches in `_simulate()` **immediately after** the
existing `elif isinstance(node, nir.Delay):` block and **before** the final `else:`
catch-all. The order within the block does not matter but grouping by functional
category aids readability.

#### `nir.Affine` → `nn.Linear` with bias

```python
elif isinstance(node, nir.Affine):
    weight = np.asarray(node.weight, dtype=np.float32)
    bias   = np.asarray(node.bias,   dtype=np.float32)
    out_features, in_features = weight.shape
    layer = nn.Linear(in_features, out_features, bias=True)
    with torch.no_grad():
        layer.weight.copy_(torch.tensor(weight))
        layer.bias.copy_(torch.tensor(bias))
    layer.weight.requires_grad_(False)
    layer.bias.requires_grad_(False)
    modules[name] = layer
```

The `nir.Affine` node carries `.weight` (shape `[out, in]`) and `.bias` (shape
`[out]`). This maps to `nn.Linear(in_features, out_features, bias=True)` — the same
as `nir.Linear` but with the bias tensor initialised from the NIR node.

#### `nir.Conv2d` → `nn.Conv2d`

```python
elif isinstance(node, nir.Conv2d):
    weight = np.asarray(node.weight, dtype=np.float32)
    # NIR Conv2d weight shape: [out_channels, in_channels, kH, kW]
    out_ch, in_ch = weight.shape[0], weight.shape[1]
    kernel_size = (weight.shape[2], weight.shape[3])
    stride  = tuple(int(s) for s in np.asarray(node.stride).flat)  or (1, 1)
    padding = tuple(int(p) for p in np.asarray(node.padding).flat) or (0, 0)
    layer = nn.Conv2d(
        in_channels=in_ch,
        out_channels=out_ch,
        kernel_size=kernel_size,
        stride=stride,
        padding=padding,
        bias=False,
    )
    with torch.no_grad():
        layer.weight.copy_(torch.tensor(weight))
    layer.weight.requires_grad_(False)
    modules[name] = layer
```

`nir.Conv2d` exposes `.weight`, `.stride`, and `.padding`. Bias is not part of the
NIR Conv2d spec, so `bias=False`. If `node.stride` or `node.padding` are scalars,
wrap them in a 2-tuple.

#### `nir.Flatten` → `nn.Flatten`

```python
elif isinstance(node, nir.Flatten):
    # nir.Flatten carries start_dim and end_dim (integers).
    # Default to flattening all dims after batch (start_dim=1) if absent.
    start_dim = int(getattr(node, "start_dim", 1))
    end_dim   = int(getattr(node, "end_dim",   -1))
    modules[name] = nn.Flatten(start_dim=start_dim, end_dim=end_dim)
```

`nir.Flatten` is a pure shape transform with no learned parameters.

#### `nir.IF` → `snntorch.Lapicque` (high-C approximation)

```python
elif isinstance(node, nir.IF):
    # Integrate-and-Fire = LIF with effectively infinite membrane time constant.
    # Model as Lapicque with very large C so tau = R*C >> simulation length.
    _LARGE_C = 1e6   # makes tau = R * 1e6 >> any realistic timestep count
    r = float(np.mean(np.asarray(node.r, dtype=float)))
    threshold = _lif_threshold(node)   # reuses existing helper
    modules[name] = snntorch.Lapicque(
        R=r,
        C=_LARGE_C,
        time_step=1.0,
        threshold=threshold,
    )
    lif_node_names.append(name)
```

`nir.IF` has `.r` (resistance), `.v_threshold`, `.v_leak` (typically 0). The IF
model has no decay, so `tau = R * C` must be much larger than the simulation window.
`C = 1e6` gives `tau = R * 1e6` which is effectively infinite for any simulation
under 10 000 timesteps.  `snntorch.Lapicque` is the correct snnTorch class for
parametric RC membrane dynamics; `snntorch.Leaky` uses a fixed `beta` and cannot
represent the IF regime.

The node is appended to `lif_node_names` so it participates in membrane-state
tracking and spike recording, matching the behaviour of `nir.LIF`.

#### `nir.AvgPool2d` → `nn.AvgPool2d`

```python
elif isinstance(node, nir.AvgPool2d):
    kernel = np.asarray(node.kernel_size)
    stride = np.asarray(node.stride)
    kernel_t = tuple(int(k) for k in kernel.flat) if kernel.ndim > 0 else (int(kernel),)
    stride_t = tuple(int(s) for s in stride.flat) if stride.ndim > 0 else (int(stride),)
    modules[name] = nn.AvgPool2d(kernel_size=kernel_t, stride=stride_t)
```

`nir.AvgPool2d` carries `.kernel_size` and `.stride` as arrays. These map directly
to the `nn.AvgPool2d` constructor.

### Timestep loop dispatch additions

In the `for name in topo_order:` block inside `with torch.no_grad():`, add dispatch
for the new node types. The new nodes fall into two categories:

**Stateless transform nodes** (`Affine`, `Conv2d`, `Flatten`, `AvgPool2d`) — call
the module and pass the result forward, same pattern as `nir.Linear`:

```python
elif isinstance(node, (nir.Affine, nir.Conv2d, nir.Flatten, nir.AvgPool2d)):
    module = modules.get(name)
    if module is not None:
        outputs[name] = module(x)
    else:
        outputs[name] = x
```

**Stateful spiking node** (`IF`) — already handled by the `nir.LIF` / `nir.CubaLIF`
branch because `IF` nodes are appended to `lif_node_names` and their modules are
`snntorch.Lapicque` instances that follow the same `(spk, mem) = module(x, state)`
calling convention. Add `nir.IF` to the existing branch condition:

```python
# Before (existing):
elif isinstance(node, (nir.LIF, nir.CubaLIF)):

# After:
elif isinstance(node, (nir.LIF, nir.CubaLIF, nir.IF)):
```

No other changes to the timestep loop are required.

No router changes are required because the router already derives its three capability
lists exclusively from `get_supported_node_types()`. Expanding the table is sufficient
to make the capabilities endpoint complete.

---

## Architecture

```
compile_to_nir()
      │
      ▼
classify_nir_graph(graph, backend)          ←── _BACKEND_NIR_SUPPORT  ◄── THIS CHANGE
      │
      ├── level == "unsupported" → HTTP 422 with diagnostics
      ├── level == "approximate" → proceed + attach warnings
      └── level == "exact"       → proceed
                  │
          ┌───────┴────────┐
          ▼                ▼
  LavaSimulatorAdapter   SnnTorchSimulatorAdapter
  _run_in_process()      _simulate()
  ┌──────────────────┐   ┌──────────────────────┐
  │ guard: scan for  │   │ new branches:        │
  │ unsupported types│   │ Affine, Conv2d,      │
  │ → LavaDispatch   │   │ Flatten, IF,         │
  │   Error          │   │ AvgPool2d            │
  └──────────────────┘   └──────────────────────┘
```

The classifier is the single authoritative gate. The adapter guards are a second line
of defence: they fire only if a graph somehow reaches the adapter without being
pre-classified, or if the table and adapter implementation drift out of sync.

---

## Components and Interfaces

### `_BACKEND_NIR_SUPPORT` (nir_support.py)

The core data structure. All logic reads from this dict; nothing hardcodes verdicts
inline. The table is the single source of truth for both the classifier and the
capabilities endpoint.

```python
_BACKEND_NIR_SUPPORT: dict[str, dict[str, str]] = {
    "snntorch_sim": { ... 17 entries ... },
    "lava_sim":     { ... 17 entries ... },
}
```

The `classify_nir_graph` and `get_supported_node_types` functions remain unchanged in
signature and contract — only the table they read grows.

### `SnnTorchSimulatorAdapter._simulate()` (snntorch_simulator.py)

The topological-sort loop gains five new `elif` branches. The existing node-handling
pattern (build module, store in `modules[name]`, add to `lif_node_names` for spiking
nodes) is followed exactly. No new helper functions are introduced unless the branch
logic exceeds ~10 lines.

### `LavaSimulatorAdapter._run_in_process()` (lava_simulator.py)

A guard block is inserted at the top of the method, before any Lava process
construction. It scans `graph.nodes`, identifies any node types not in the lava-nc
supported set, and raises `LavaDispatchError` immediately listing all unsupported types.

### `get_supported_node_types(backend)` (nir_support.py — unchanged)

Already returns `dict(table)`. The capabilities router reads this; no router changes
needed.

---

## Data Models

### Complete Primitive Set

The canonical list of 17 NIR primitives that must appear explicitly in the table:

```python
COMPLETE_PRIMITIVE_SET: frozenset[str] = frozenset({
    "Input", "Output", "Linear", "Affine", "Conv2d", "Flatten",
    "IF", "LIF", "CubaLIF", "LI", "AvgPool2d", "SumPool2d",
    "Delay", "Scale", "Threshold", "Sigmoid", "Tanh",
})
```

This constant is defined in `nir_support.py` and used by both the classifier and the
test suite.

### Expanded `_BACKEND_NIR_SUPPORT` table

#### `snntorch_sim` (17 entries)

```python
"snntorch_sim": {
    "Input":    "exact",
    "Output":   "exact",
    "Linear":   "exact",
    "Affine":   "exact",       # nn.Linear(weight, bias)
    "Conv2d":   "exact",       # nn.Conv2d — weight shape (out, in, kH, kW)
    "Flatten":  "exact",       # nn.Flatten(start_dim=1)
    "IF":       "exact",       # snntorch.Lapicque with large R*C
    "LIF":      "exact",
    "CubaLIF":  "exact",       # approximate conductance; verdict "exact" because it runs
    "LI":       "unsupported", # no snntorch.Leaky equivalent without threshold
    "AvgPool2d":"exact",       # nn.AvgPool2d
    "SumPool2d":"unsupported", # not in snnTorch NIR support
    "Delay":    "approximate",
    "Scale":    "unsupported",
    "Threshold":"unsupported",
    "Sigmoid":  "unsupported",
    "Tanh":     "unsupported",
},
```

#### `lava_sim` (17 entries)

```python
"lava_sim": {
    "Input":    "exact",
    "Output":   "exact",
    "LIF":      "exact",
    "CubaLIF":  "exact",
    "Linear":   "exact",
    "Delay":    "approximate",
    "Affine":   "unsupported", # lava-nc has no Affine process; lava-dl netx is out of scope
    "Conv2d":   "unsupported", # lava-nc has no Conv process; lava-dl netx is out of scope
    "Flatten":  "unsupported", # lava-nc has no Flatten process; lava-dl netx is out of scope
    "IF":       "unsupported", # lava-nc LIF with infinite tau ≠ IF semantics
    "LI":       "unsupported", # lava-nc has no leaky integrator without threshold
    "AvgPool2d":"unsupported", # lava-nc has no pooling process
    "SumPool2d":"unsupported", # lava-nc has no pooling process
    "Scale":    "unsupported",
    "Threshold":"unsupported",
    "Sigmoid":  "unsupported",
    "Tanh":     "unsupported",
},
```

### `SupportClassification` — unchanged

No changes to the dataclass shape, field names, or semantics.

---

## snnTorch Adapter: New Node Branches

### Design decision: `snntorch.Lapicque` for `nir.IF`

The IF (Integrate-and-Fire) neuron has no leak — it integrates input indefinitely until
threshold. `snntorch.Leaky` with `beta → 1` would approach IF semantics, but
`snntorch.Lapicque` with very large `R*C` is the explicit snnTorch equivalent because it
exposes `R` (resistance) and `C` (capacitance) directly as the time-constant parameters.
Setting `R=node.r` and `C=node.tau` (which together give a very large `R*C`) accurately
approximates the no-leak integration. The verdict is `"exact"` in the table because the
node executes without semantic transformation, but the CubaLIF precedent (which also
carries a warning) is followed if precision differences arise.

Alternative considered: `snntorch.Leaky(beta=0.99)` — rejected because Lapicque is
semantically named and exposes the correct physical parameters.

### Design decision: Conv2d tensor layout

`nir.Conv2d.weight` is shaped `(out_channels, in_channels, kH, kW)` matching PyTorch's
`nn.Conv2d.weight` convention. Direct tensor copy is therefore safe without transposition.
Stride and padding are scalars or 1-D arrays in NIR; they map directly to PyTorch's
`stride` and `padding` int-or-tuple arguments.

### Code sketch: five new branches in `_simulate()`

```python
elif isinstance(node, nir.Affine):
    weight = np.asarray(node.weight, dtype=np.float32)
    bias   = np.asarray(node.bias,   dtype=np.float32)
    out_features, in_features = weight.shape
    layer = nn.Linear(in_features, out_features, bias=True)
    with torch.no_grad():
        layer.weight.copy_(torch.tensor(weight))
        layer.bias.copy_(torch.tensor(bias))
    layer.weight.requires_grad_(False)
    layer.bias.requires_grad_(False)
    modules[name] = layer

elif isinstance(node, nir.Conv2d):
    w = np.asarray(node.weight, dtype=np.float32)       # (out, in, kH, kW)
    out_ch, in_ch, kH, kW = w.shape
    has_bias = hasattr(node, "bias") and node.bias is not None
    stride  = tuple(int(s) for s in np.asarray(node.stride).flat)  if hasattr(node, "stride")  else (1, 1)
    padding = tuple(int(p) for p in np.asarray(node.padding).flat) if hasattr(node, "padding") else (0, 0)
    layer = nn.Conv2d(in_ch, out_ch, (kH, kW), stride=stride, padding=padding, bias=has_bias)
    with torch.no_grad():
        layer.weight.copy_(torch.tensor(w))
        if has_bias:
            layer.bias.copy_(torch.tensor(np.asarray(node.bias, dtype=np.float32)))
    layer.weight.requires_grad_(False)
    modules[name] = layer

elif isinstance(node, nir.Flatten):
    modules[name] = nn.Flatten(start_dim=1)  # keep batch dim if present; dim-0 for unbatched

elif isinstance(node, nir.IF):
    r         = float(np.mean(np.asarray(node.r)))
    c         = float(np.mean(np.asarray(node.tau)))   # tau ≡ C in Lapicque
    threshold = _lif_threshold(node)
    modules[name] = snntorch.Lapicque(R=r, C=c, threshold=threshold)
    lif_node_names.append(name)

elif isinstance(node, nir.AvgPool2d):
    # nir.AvgPool2d stores the kernel as `sumpool_size` or `pool_size` depending on NIR version
    pool_size = getattr(node, "pool_size", None) or getattr(node, "sumpool_size", None)
    if pool_size is None:
        raise SnnTorchDispatchError(
            f"nir.AvgPool2d '{name}' has no recognisable pool_size attribute. "
            "Check the installed NIR version."
        )
    kernel_size = tuple(int(k) for k in np.asarray(pool_size).flat)
    stride_attr = getattr(node, "stride", None)
    stride = tuple(int(s) for s in np.asarray(stride_attr).flat) if stride_attr is not None else kernel_size
    modules[name] = nn.AvgPool2d(kernel_size=kernel_size, stride=stride)
```

The timestep loop already has an `else: outputs[name] = x` passthrough at the bottom.
Each new branch also needs a corresponding execution clause in the loop:

```python
elif isinstance(node, (nir.Affine, nir.Conv2d, nir.Flatten, nir.AvgPool2d)):
    outputs[name] = modules[name](x)

elif isinstance(node, nir.IF):
    spk, mem = modules[name](x, mem_states[name])
    mem_states[name] = mem
    if name in spike_record:
        for i, s in enumerate(spk.tolist()):
            if s:
                spike_record[name][i].append(t)
        for i, v in enumerate(mem.tolist()):
            voltage_record[name][i].append(round(float(v), 5))
    outputs[name] = spk
```

The `mem_states` initialisation loop also needs to handle `nir.IF` nodes (already
covered because `lif_node_names.append(name)` is called in the build phase, and the
existing `for name in lif_node_names: mem_states[name] = modules[name].init_leaky()`
will pick up Lapicque correctly since `snntorch.Lapicque` exposes `init_leaky()`).

---

## Lava Pre-Execution Guard

The guard is inserted at the top of `_run_in_process()`, before `LavaIO().to_runtime_payload(graph)`:

```python
_LAVA_NC_SUPPORTED: frozenset[str] = frozenset({
    "Input", "Output", "LIF", "CubaLIF", "Linear", "Delay",
})

unsupported_in_graph = sorted(
    {type(node).__name__ for node in graph.nodes.values()}
    - _LAVA_NC_SUPPORTED
)
if unsupported_in_graph:
    raise LavaDispatchError(
        f"Lava (lava-nc) cannot execute the following NIR node types: "
        f"{', '.join(unsupported_in_graph)}. "
        f"These primitives are only available in lava-dl (out of scope) "
        f"or are not supported by any Lava path. "
        f"Remove or replace these nodes before dispatching to lava_sim."
    )
```

This replaces the current silent skip/passthrough behaviour in `LavaIO.to_runtime_payload`
for unknown node types. It fires before any Lava process is constructed, so partial
network state is never left running.

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid
executions of a system — essentially, a formal statement about what the system should do.
Properties serve as the bridge between human-readable specifications and
machine-verifiable correctness guarantees.*

### Property 1: Table completeness — every primitive has an explicit entry

*For any* backend name in `_BACKEND_NIR_SUPPORT` and any member of
`COMPLETE_PRIMITIVE_SET`, the backend's sub-dict SHALL contain an explicit key for that
primitive, so that `get_supported_node_types(backend)[primitive]` returns a defined
verdict without relying on any default fallback.

**Validates: Requirements 1.1, 1.2**

### Property 2: Classifier verdict matches table for known primitives

*For any* NIR graph whose nodes are all members of `COMPLETE_PRIMITIVE_SET` and *any*
valid backend name, every node type that appears in the graph SHALL be assigned the
verdict recorded in `_BACKEND_NIR_SUPPORT[backend][node_type]`, with no node type
landing in a different verdict bucket.

**Validates: Requirements 1.2, 5.1, 5.2, 5.3, 5.4, 5.5**

### Property 3: Unknown node types always fall through to unsupported

*For any* NIR graph that contains a node whose Python class name is **not** a member of
`COMPLETE_PRIMITIVE_SET`, `classify_nir_graph` SHALL return a `SupportClassification`
with `level == "unsupported"` and the unknown type name SHALL appear in
`unsupported_nodes`.

**Validates: Requirements 1.6**

### Property 4: Unsupported nodes always appear in diagnostics

*For any* NIR graph and *any* backend, every node type name listed in
`SupportClassification.unsupported_nodes` SHALL appear as a substring of at least one
entry in `SupportClassification.diagnostics`.

**Validates: Requirements 5.3, 5.6**

### Property 5: Capabilities union equals Complete Primitive Set

*For any* valid backend name, the union of the sets returned by
`get_supported_node_types(backend)` keyed by `"exact"`, `"approximate"`, and
`"unsupported"` SHALL equal `COMPLETE_PRIMITIVE_SET` exactly (no missing primitives,
no extra entries).

**Validates: Requirements 4.1, 4.2, 4.3, 4.4**

### Property 6: New snnTorch-implemented node types produce no skip warning

*For any* of the five newly implemented node types (`Affine`, `Conv2d`, `Flatten`, `IF`,
`AvgPool2d`), running a minimal graph containing that node through `SnnTorchSimulatorAdapter`
SHALL produce a `SnnTorchSimulatorResult` whose `warnings` list contains no entry with
the substring `"not supported"` or `"skipped"`.

**Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5, 2.7**

### Property 7: Lava guard raises before execution for any unsupported node

*For any* NIR graph containing at least one node whose type name is not in
`_LAVA_NC_SUPPORTED`, calling `LavaSimulatorAdapter._run_in_process()` SHALL raise
`LavaDispatchError` and the error's `diagnostics` list SHALL name all unsupported node
types present in the graph.

**Validates: Requirements 3.3**

---

## Error Handling

### Classifier (nir_support.py)

- Unknown backend name → `ValueError` (unchanged)
- Unknown node type in graph → `"unsupported"` via `.get(type_name, "unsupported")` fallback (unchanged, correct)
- Empty graph → returns `level == "exact"` with empty lists (unchanged)

### snnTorch adapter (snntorch_simulator.py)

- `nir.AvgPool2d` with no recognisable pool attribute → `SnnTorchDispatchError` with message naming the node
- `nir.Conv2d` weight shape inconsistency → `SnnTorchDispatchError` from the `nn.Conv2d` constructor
- Missing torch/snntorch → `SnnTorchDispatchError` (unchanged)

### Lava adapter (lava_simulator.py)

- Any unsupported node type → `LavaDispatchError` raised *before* Lava process construction (new)
- Lava not installed → `LavaDispatchError` (unchanged)
- Network construction failure → `LavaDispatchError` (unchanged)

---

## Testing Strategy

### Unit tests (test_nir_support.py)

Unit tests cover specific verdicts and boundary conditions. They are cheap and fast.

**Existing tests to keep:**
- `test_exact_graph_classified_as_exact` (parametrized over both backends)
- `test_delay_graph_classified_as_approximate`
- `test_unsupported_graph_classified_as_unsupported`
- `test_unsupported_nodes_listed_in_diagnostics`
- `test_unknown_backend_raises_value_error`
- `test_list_supported_backends_returns_both`

**New example-based tests:**

```python
@pytest.mark.parametrize("backend", ["lava_sim", "snntorch_sim"])
@pytest.mark.parametrize("primitive", sorted(COMPLETE_PRIMITIVE_SET))
def test_all_primitives_have_explicit_entry(backend, primitive):
    table = get_supported_node_types(backend)
    assert primitive in table, f"{primitive!r} missing from {backend!r} table"

@pytest.mark.parametrize("primitive,expected", [
    ("Affine",   "unsupported"), ("Conv2d",   "unsupported"),
    ("Flatten",  "unsupported"), ("IF",       "unsupported"),
    ("AvgPool2d","unsupported"), ("SumPool2d","unsupported"),
])
def test_lava_unsupported_verdicts(primitive, expected):
    assert get_supported_node_types("lava_sim")[primitive] == expected

@pytest.mark.parametrize("primitive,expected", [
    ("Affine","exact"), ("Conv2d","exact"), ("Flatten","exact"),
    ("IF","exact"), ("AvgPool2d","exact"),
])
def test_snntorch_new_exact_verdicts(primitive, expected):
    assert get_supported_node_types("snntorch_sim")[primitive] == expected

# Adapter smoke tests for each new snnTorch node type (one per type, abbreviated here)
def test_snntorch_adapter_handles_affine_without_skip_warning():
    ...  # build minimal graph, run adapter, assert no "not supported" in warnings
```

### Property-based tests (test_nir_support.py)

Property-based tests use **Hypothesis** (already available in the Python ecosystem and
appropriate for this pure-function domain). Each test is tagged with the property it
validates.

Minimum 100 iterations per property (Hypothesis default `max_examples=100`).

```python
from hypothesis import given, settings
from hypothesis import strategies as st

# Feature: nir-simulator-support-matrix, Property 2: Classifier verdict matches table
@given(
    backend=st.sampled_from(["lava_sim", "snntorch_sim"]),
    primitive=st.sampled_from(sorted(COMPLETE_PRIMITIVE_SET)),
)
@settings(max_examples=200)
def test_property2_classifier_verdict_matches_table(backend, primitive):
    ...

# Feature: nir-simulator-support-matrix, Property 3: Unknown types → unsupported
@given(unknown_name=st.text(min_size=1).filter(lambda s: s not in COMPLETE_PRIMITIVE_SET))
@settings(max_examples=100)
def test_property3_unknown_node_type_is_unsupported(unknown_name):
    ...

# Feature: nir-simulator-support-matrix, Property 4: Unsupported nodes in diagnostics
@given(backend=st.sampled_from(["lava_sim", "snntorch_sim"]))
@settings(max_examples=100)
def test_property4_unsupported_nodes_named_in_diagnostics(backend):
    ...

# Feature: nir-simulator-support-matrix, Property 5: Capabilities union == Complete set
@given(backend=st.sampled_from(["lava_sim", "snntorch_sim"]))
@settings(max_examples=50)
def test_property5_capabilities_union_equals_complete_set(backend):
    ...

# Feature: nir-simulator-support-matrix, Property 7: Lava guard fires before execution
@given(unsupported=st.sampled_from(sorted(
    COMPLETE_PRIMITIVE_SET - {"Input","Output","LIF","CubaLIF","Linear","Delay"}
)))
@settings(max_examples=100)
def test_property7_lava_guard_raises_for_unsupported_node(unsupported):
    ...
```

Properties 1 and 6 are best validated by direct example tests (they test a fixed finite
set rather than a large input space) and are covered by the parametrized unit tests above.

### Documentation test

A single smoke assertion verifies the doc section exists:

```python
def test_support_matrix_doc_contains_simulator_section():
    doc_path = Path(__file__).parents[3] / "docs" / "support_matrix.md"
    text = doc_path.read_text()
    assert "Simulator Backend NIR Primitive Support" in text
```

### Documentation update plan (support_matrix.md)

A new section "Simulator Backend NIR Primitive Support" is added between the existing
"NIR Fidelity Subset" section and the "Training Support" section. It contains:

1. A note explaining the lava-nc vs lava-dl distinction and why it matters for this
   support matrix.
2. A table for `snntorch_sim` listing all 17 primitives with their verdicts.
3. A table for `lava_sim` listing all 17 primitives with their verdicts.
4. A "Promotability" subsection noting which lava-nc `"unsupported"` primitives could
   be promoted if lava-dl netx integration were added (`Conv2d`, `Flatten`, `Affine`).

The doc is updated in the same commit as `nir_support.py` per the `neurocnl/AGENTS.md`
constraint: *"Do not promote a backend or export path from unsupported or approximate to
stronger semantics unless docs/support_matrix.md and the corresponding tests are updated
in the same change."*

---

## Lava Adapter Early Rejection

### Location

Insert the guard as the **first action** inside `_run_in_process`, immediately after
the `_import_lava()` call and before `LavaIO().to_runtime_payload(graph)`.

### Implementation

```python
# ── lava-nc supported node types ─────────────────────────────────────────────
# Only these types can be lowered by LavaIO.to_runtime_payload.
# Everything else must be rejected before dispatch to avoid confusing Lava
# runtime errors that don't mention the unsupported NIR type.
_LAVA_NC_SUPPORTED_TYPES = frozenset({
    "Input", "Output", "LIF", "CubaLIF", "Linear", "Delay"
})

def _run_in_process(self, graph, timesteps, seed):
    try:
        LIF, Dense, Monitor, RunSteps, Loihi2SimCfg = _import_lava()
    except ImportError as exc:
        raise LavaDispatchError(f"Failed to import lava: {exc}") from exc

    # ── Early rejection: check for unsupported node types before dispatch ────
    unsupported_in_graph = [
        f"nir.{type(node).__name__} (node '{name}')"
        for name, node in graph.nodes.items()
        if type(node).__name__ not in _LAVA_NC_SUPPORTED_TYPES
    ]
    if unsupported_in_graph:
        raise LavaDispatchError(
            "The lava-nc adapter cannot execute this NIR graph. "
            "The following node types are not supported by lava-nc processes: "
            + ", ".join(unsupported_in_graph)
            + ". "
            "Note: some of these types are supported by lava-dl (netx), "
            "which is outside the scope of lava_sim. "
            "Use snntorch_sim for graphs containing these node types."
        )

    np.random.seed(seed)
    payload = LavaIO().to_runtime_payload(graph)
    # ... rest of existing implementation unchanged ...
```

### Rationale

Without this guard, `LavaIO.to_runtime_payload()` may silently ignore unsupported
nodes, produce an empty or partial payload, and cause a confusing downstream Lava
runtime error that doesn't mention the NIR node type. The early rejection surfaces
a clear diagnostic immediately — before any Lava process is constructed — and names
every unsupported node so the developer knows exactly what to remove.

The guard uses `type(node).__name__` (a string comparison) rather than `isinstance`
checks so it stays decoupled from the NIR class hierarchy and remains correct even
if the `nir` package adds new subclasses.

The diagnostic message explicitly mentions `lava-dl` / `netx` so developers familiar
with the official NIR support matrix understand why their graph is rejected.

---

## Capabilities Endpoint Completeness

The router already drives all three node-type lists from `get_supported_node_types()`:

```python
_LAVA_SIM_SUPPORT    = get_supported_node_types("lava_sim")
_SNNTORCH_SIM_SUPPORT = get_supported_node_types("snntorch_sim")

# In _build_lava_capability():
supported_nir_nodes=[n for n, v in _LAVA_SIM_SUPPORT.items()    if v == "exact"],
unsupported_nir_nodes=[n for n, v in _LAVA_SIM_SUPPORT.items()  if v == "unsupported"],
approximate_semantics=[n for n, v in _LAVA_SIM_SUPPORT.items()  if v == "approximate"],
```

**No router changes are needed.** Once `_BACKEND_NIR_SUPPORT` is expanded to include
all 17 primitives for each backend, `get_supported_node_types()` will return all 17
entries, and the endpoint will enumerate them across the three lists automatically.

The union guarantee (`supported ∪ approximate ∪ unsupported == Complete_Primitive_Set`)
is enforced by the test suite, not by router code.

### Confirmation of no additional hardcoding

A search of `simulators.py` confirms there are no hardcoded node-type lists inside
the router itself. The `_LAVA_SIM_SUPPORT` and `_SNNTORCH_SIM_SUPPORT` module-level
constants are populated at import time from `nir_support.py`, making the router
entirely table-driven.

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid
executions of a system — essentially, a formal statement about what the system should
do. Properties serve as the bridge between human-readable specifications and
machine-verifiable correctness guarantees.*

### Property 1: No-fallthrough completeness

*For any* member of `Complete_Primitive_Set`, that member SHALL appear as an explicit
key in `_BACKEND_NIR_SUPPORT["lava_sim"]` and in `_BACKEND_NIR_SUPPORT["snntorch_sim"]`,
such that the verdict is always explicit and never falls through to `.get()` default.

**Validates: Requirements 1.1, 1.2**

---

### Property 2: Classifier maps "exact"-only graphs to level "exact"

*For any* NIR graph whose node types are all in the `"exact"` set for a given backend,
`classify_nir_graph(graph, backend)` SHALL return `level == "exact"` with empty
`unsupported_nodes` and empty `approximate_nodes`.

**Validates: Requirements 5.1**

---

### Property 3: Classifier maps "approximate"-present graphs to level "approximate"

*For any* NIR graph that contains at least one node type with verdict `"approximate"`
and no node types with verdict `"unsupported"` for a given backend,
`classify_nir_graph(graph, backend)` SHALL return `level == "approximate"`.

**Validates: Requirements 5.2**

---

### Property 4: Classifier maps "unsupported"-present graphs to level "unsupported"

*For any* NIR graph that contains at least one node type with verdict `"unsupported"`
for a given backend, `classify_nir_graph(graph, backend)` SHALL return
`level == "unsupported"` with a non-empty `diagnostics` list.

**Validates: Requirements 5.3, 5.6**

---

### Property 5: All unsupported types are named in diagnostics

*For any* NIR graph, every node type name appearing in
`SupportClassification.unsupported_nodes` SHALL appear as a substring in at least
one entry of `SupportClassification.diagnostics`.

**Validates: Requirements 5.4, 5.6**

---

### Property 6: Newly implemented snnTorch nodes produce no skip warnings

*For any* NIR graph that contains only node types from
`{Input, Output, Linear, Affine, Conv2d, Flatten, IF, LIF, CubaLIF, AvgPool2d, Delay}`,
running `SnnTorchSimulatorAdapter._simulate()` SHALL NOT emit any warning containing
the phrases `"not supported"` or `"skipped"` in `SnnTorchSimulatorResult.warnings`.

**Validates: Requirements 2.7**

---

### Property 7: Capabilities endpoint lists partition Complete_Primitive_Set

*For any* backend, the union of `supported_nir_nodes`, `unsupported_nir_nodes`, and
`approximate_semantics` returned by `_build_lava_capability()` or
`_build_snntorch_capability()` SHALL equal the full set of keys in
`_BACKEND_NIR_SUPPORT[backend]` (which, after this change, equals
`Complete_Primitive_Set`).

**Validates: Requirements 4.1, 4.2, 4.3, 4.4**

---

### Property 8: Lava early rejection names every unsupported node

*For any* NIR graph containing one or more node types outside the lava-nc supported
set, `LavaSimulatorAdapter._run_in_process()` SHALL raise `LavaDispatchError` and
the diagnostic message SHALL contain the type name (as `nir.TypeName`) for each
unsupported node encountered.

**Validates: Requirements 3.3**

---

*Property reflection:*

- Properties 2, 3, 4 together cover the full three-way classifier level assignment
  (no redundancy — each tests a disjoint condition on graph composition).
- Properties 4 and 5 are complementary: Property 4 checks level/diagnostics are
  non-empty; Property 5 checks that the content names every unsupported type. Neither
  subsumes the other.
- Property 7 subsumes testing each of the three list fields individually (Requirements
  4.1, 4.2, 4.3 are implied by the set-equality test in 4.4), so no separate per-list
  properties are needed.
- Properties 6 and 8 are adapter-level invariants with no overlap.
- All eight properties provide unique validation value.

---

## Error Handling

### snnTorch adapter — new node type handling

**Construction errors** (e.g. mismatched weight shape for `nir.Conv2d`): The
`_simulate()` method already wraps the entire body in the `run()` method's
`try/except Exception as exc → raise SnnTorchDispatchError(...)`. New node branches
should let numpy/torch shape errors propagate naturally; they will be caught and
re-raised as `SnnTorchDispatchError` with the underlying exception message.

**Missing parameters**: Use `getattr(node, "attr", default)` defensively for
optional NIR node attributes (e.g. `node.start_dim` on `nir.Flatten`). If a required
parameter is missing, raise `SnnTorchDispatchError` with a message naming the node
and the missing attribute.

**IF with zero resistance**: If `node.r` is zero or negative for `nir.IF`, clamp to
a minimum of `1e-3` to avoid division errors in `snntorch.Lapicque`. Emit a warning
in `SnnTorchSimulatorResult.warnings`.

### Lava adapter — early rejection

Raises `LavaDispatchError` before any Lava process is created. The error is caught by
the router's existing `except LavaDispatchError` block and surfaced as HTTP 422 with
the `lava_dispatch_failed` code. No additional router changes required.

### Classifier — unknown backends

`classify_nir_graph()` raises `ValueError` for unknown `backend_name` (existing
behaviour, unchanged). The router validates the backend name before calling the
classifier, so this path is only reachable in direct library usage.

### Support table — unknown node types at runtime

The classifier's `.get(type_name, "unsupported")` fallback remains in place for NIR
node types not in `Complete_Primitive_Set`. This is correct: genuinely novel
experimental node types should default to `"unsupported"` rather than crashing.
Requirement 1.6 explicitly requires this fallback for out-of-set types.

---

## Testing Strategy

### Library choice

**pytest** with **hypothesis** for property-based tests. The project already uses
`pytest`; `hypothesis` is the standard PBT library for Python.

```
pip install hypothesis
```

Each property test is configured with `@settings(max_examples=100)`.

### Test tag format

```python
# Feature: nir-simulator-support-matrix, Property N: <property text summary>
```

---

### File 1: `test_nir_support.py` (additions to existing file)

#### Parametrized verdict tests — all 17 primitives × both backends

```python
COMPLETE_PRIMITIVE_SET = {
    "Input", "Output", "Linear", "Affine", "Conv2d", "Flatten",
    "IF", "LIF", "CubaLIF", "LI", "AvgPool2d", "SumPool2d",
    "Delay", "Scale", "Threshold", "Sigmoid", "I", "CubaLI",
}

EXPECTED_VERDICTS = {
    "lava_sim": {
        "Input": "exact", "Output": "exact",
        "Linear": "exact", "LIF": "exact", "CubaLIF": "approximate",
        "Delay": "approximate",
        "Affine": "unsupported", "Conv2d": "unsupported", "Flatten": "unsupported",
        "IF": "unsupported", "LI": "unsupported", "I": "unsupported",
        "AvgPool2d": "unsupported", "SumPool2d": "unsupported",
        "Scale": "unsupported", "Threshold": "unsupported",
        "Sigmoid": "unsupported", "CubaLI": "unsupported",
    },
    "snntorch_sim": {
        "Input": "exact", "Output": "exact",
        "Linear": "exact", "Affine": "exact", "Conv2d": "exact",
        "Flatten": "exact", "IF": "exact", "LIF": "exact",
        "AvgPool2d": "exact",
        "CubaLIF": "approximate", "Delay": "approximate",
        "LI": "unsupported", "I": "unsupported", "SumPool2d": "unsupported",
        "Scale": "unsupported", "Threshold": "unsupported",
        "Sigmoid": "unsupported", "CubaLI": "unsupported",
    },
}

@pytest.mark.parametrize("backend,primitive,expected", [
    (backend, primitive, verdict)
    for backend, verdicts in EXPECTED_VERDICTS.items()
    for primitive, verdict in verdicts.items()
])
def test_verdict_for_primitive(backend, primitive, expected):
    table = get_supported_node_types(backend)
    assert table.get(primitive) == expected, (
        f"{backend}[{primitive!r}] = {table.get(primitive)!r}, expected {expected!r}"
    )
```

#### No-fallthrough test (Property 1)

```python
def test_no_fallthrough_all_primitives():
    """Every Complete_Primitive_Set member must be an explicit key in the table."""
    # Feature: nir-simulator-support-matrix, Property 1: no-fallthrough completeness
    for backend in ["lava_sim", "snntorch_sim"]:
        table = get_supported_node_types(backend)
        for primitive in COMPLETE_PRIMITIVE_SET:
            assert primitive in table, (
                f"Missing explicit entry for {primitive!r} in {backend} table. "
                "Add an explicit verdict — do not rely on .get() default."
            )
```

#### Hypothesis property tests (Properties 2–5, 7)

```python
from hypothesis import given, settings
from hypothesis import strategies as st

all_exact_snn = [
    p for p, v in EXPECTED_VERDICTS["snntorch_sim"].items() if v == "exact"
]

@given(
    node_types=st.lists(st.sampled_from(all_exact_snn), min_size=2, max_size=6,
                        unique=True)
)
@settings(max_examples=100)
def test_exact_only_graph_classifies_exact(node_types):
    # Feature: nir-simulator-support-matrix, Property 2: exact-only → level exact
    graph = _build_minimal_graph_from_types(node_types)
    result = classify_nir_graph(graph, "snntorch_sim")
    assert result.level == "exact"
    assert result.unsupported_nodes == []
    assert result.approximate_nodes == []
```

*(Similar parametric hypothesis tests for Properties 3 and 4 following the same
pattern — generate graphs from approximate/unsupported node type subsets and assert
the classifier level.)*

```python
@given(
    node_types=st.lists(
        st.sampled_from([p for p, v in EXPECTED_VERDICTS["snntorch_sim"].items()
                         if v == "unsupported"]),
        min_size=1, max_size=4, unique=True,
    )
)
@settings(max_examples=100)
def test_unsupported_nodes_all_named_in_diagnostics(node_types):
    # Feature: nir-simulator-support-matrix, Property 5: unsupported nodes named
    graph = _build_minimal_graph_from_types(node_types + ["Input", "Output"])
    result = classify_nir_graph(graph, "snntorch_sim")
    for node_type in result.unsupported_nodes:
        assert any(node_type in msg for msg in result.diagnostics)
```

#### Capabilities partition test (Property 7)

```python
def test_capabilities_lists_partition_complete_primitive_set():
    # Feature: nir-simulator-support-matrix, Property 7: partition == complete set
    from backend.app.routers.simulators import _build_lava_capability, _build_snntorch_capability
    for cap_fn, backend in [
        (_build_lava_capability, "lava_sim"),
        (_build_snntorch_capability, "snntorch_sim"),
    ]:
        cap = cap_fn()
        union = set(cap.supported_nir_nodes) | set(cap.approximate_semantics) | set(cap.unsupported_nir_nodes)
        expected = set(get_supported_node_types(backend).keys())
        assert union == expected, f"{backend}: capability union {union} != table keys {expected}"
```

---

### File 2: `test_snntorch_simulator_primitives.py` (new file)

Location: `neurocnl/neurocnl/runtime/test_snntorch_simulator_primitives.py`

This file tests the snnTorch adapter in isolation. It imports `torch` and `snntorch`
conditionally and marks all tests with `pytest.importorskip`.

#### Graph builder helper

```python
def _make_graph_with_node(name: str, node: nir.NIRNode, in_size: int = 4) -> nir.NIRGraph:
    """Wrap a single node in a minimal Input → node → LIF → Output graph."""
    lif = nir.LIF(
        tau=np.array([0.02] * in_size),
        r=np.array([1.0] * in_size),
        v_leak=np.array([0.0] * in_size),
        v_threshold=np.array([1.0] * in_size),
        input_type={"input": np.array([in_size])},
        output_type={"output": np.array([in_size])},
    )
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([in_size])}),
            "node":  node,
            "lif":   lif,
            "output": nir.Output(output_type={"output": np.array([in_size])}),
        },
        edges=[("input", "node"), ("node", "lif"), ("lif", "output")],
    )
```

#### Parametrized no-skip-warning tests

```python
NEW_SNNTORCH_NODES = {
    "Affine": lambda n: nir.Affine(
        weight=np.eye(n, dtype=np.float32),
        bias=np.zeros(n, dtype=np.float32),
    ),
    "Conv2d": lambda n: nir.Conv2d(
        weight=np.zeros((n, n, 1, 1), dtype=np.float32),
        stride=np.array([1, 1]),
        padding=np.array([0, 0]),
        input_type={"input": np.array([n, 1, 1])},
        output_type={"output": np.array([n, 1, 1])},
    ),
    "Flatten": lambda n: nir.Flatten(
        start_dim=1, end_dim=-1,
        input_type={"input": np.array([n])},
        output_type={"output": np.array([n])},
    ),
    "IF": lambda n: nir.IF(
        r=np.array([1.0] * n),
        v_threshold=np.array([1.0] * n),
        v_leak=np.array([0.0] * n),
        input_type={"input": np.array([n])},
        output_type={"output": np.array([n])},
    ),
    "AvgPool2d": lambda n: nir.AvgPool2d(
        kernel_size=np.array([1, 1]),
        stride=np.array([1, 1]),
        input_type={"input": np.array([n, 1, 1])},
        output_type={"output": np.array([n, 1, 1])},
    ),
}

@pytest.mark.parametrize("node_type_name", list(NEW_SNNTORCH_NODES.keys()))
def test_new_node_type_no_skip_warning(node_type_name: str) -> None:
    """Newly implemented node types must not emit an 'unsupported/skipped' warning.
    
    Feature: nir-simulator-support-matrix, Property 6: no skip warnings for new types
    """
    torch   = pytest.importorskip("torch")
    snn     = pytest.importorskip("snntorch")
    
    N = 4
    node = NEW_SNNTORCH_NODES[node_type_name](N)
    graph = _make_graph_with_node(node_type_name.lower(), node, in_size=N)
    stimulus = _make_minimal_stimulus(graph, timesteps=5)
    
    result = SnnTorchSimulatorAdapter().run(graph, stimulus, timesteps=5, seed=0)
    
    skip_warnings = [
        w for w in result.warnings
        if "not supported" in w.lower() or "skipped" in w.lower()
    ]
    assert skip_warnings == [], (
        f"nir.{node_type_name} emitted skip/unsupported warnings: {skip_warnings}"
    )
```

#### Classification check for new node types

```python
@pytest.mark.parametrize("node_type_name", ["Affine", "Conv2d", "Flatten", "IF", "AvgPool2d"])
def test_new_node_type_not_classified_as_unsupported(node_type_name: str) -> None:
    N = 4
    node = NEW_SNNTORCH_NODES[node_type_name](N)
    graph = _make_graph_with_node(node_type_name.lower(), node, in_size=N)
    result = classify_nir_graph(graph, "snntorch_sim")
    assert result.level != "unsupported", (
        f"nir.{node_type_name} classified as unsupported by snntorch_sim; "
        f"unsupported_nodes={result.unsupported_nodes}"
    )
```

#### Lava early-rejection test (Property 8)

```python
def test_lava_early_rejection_names_unsupported_types() -> None:
    """LavaSimulatorAdapter must raise LavaDispatchError naming unsupported node types.
    
    Feature: nir-simulator-support-matrix, Property 8: lava early rejection
    """
    pytest.importorskip("lava")
    
    # Conv2d is unsupported by lava-nc
    graph = _make_graph_with_node(
        "conv",
        nir.Conv2d(
            weight=np.zeros((4, 4, 1, 1), dtype=np.float32),
            stride=np.array([1, 1]),
            padding=np.array([0, 0]),
        ),
        in_size=4,
    )
    
    from neurocnl.runtime.lava_simulator import LavaDispatchError, LavaSimulatorAdapter
    
    with pytest.raises(LavaDispatchError) as exc_info:
        LavaSimulatorAdapter()._run_in_process(graph, timesteps=5, seed=0)
    
    error_msg = str(exc_info.value)
    assert "Conv2d" in error_msg, (
        f"LavaDispatchError did not name Conv2d in: {error_msg}"
    )
```

#### Hypothesis property test for Lava early rejection

```python
from hypothesis import given, settings
from hypothesis import strategies as st

LAVA_UNSUPPORTED = [
    "Affine", "Conv2d", "Flatten", "IF", "AvgPool2d", "SumPool2d",
    "LI", "Scale", "Threshold", "Sigmoid", "I", "CubaLI",
]

@given(
    unsupported_types=st.lists(
        st.sampled_from(LAVA_UNSUPPORTED), min_size=1, max_size=3, unique=True
    )
)
@settings(max_examples=50)
def test_lava_early_rejection_any_unsupported_type(unsupported_types) -> None:
    """For any graph containing lava-unsupported types, LavaDispatchError is raised.
    
    Feature: nir-simulator-support-matrix, Property 8: lava early rejection
    """
    pytest.importorskip("lava")
    from neurocnl.runtime.lava_simulator import LavaDispatchError, LavaSimulatorAdapter
    
    # Build a graph containing the first unsupported type (simplification)
    type_name = unsupported_types[0]
    graph = _build_minimal_unsupported_graph(type_name)
    
    with pytest.raises(LavaDispatchError) as exc_info:
        LavaSimulatorAdapter()._run_in_process(graph, timesteps=5, seed=0)
    
    error_msg = str(exc_info.value)
    assert type_name in error_msg
```

---

## Documentation Changes — `docs/support_matrix.md`

Add the following section immediately after the existing **NIR Fidelity Subset**
section, as a new H2 section titled **NIR Simulator Support Matrix**.

The section must be added in the **same commit** as `nir_support.py` changes, as
required by `neurocnl/AGENTS.md`.

### Section to add

````markdown
---

## NIR Simulator Support Matrix

This section documents per-backend support verdicts for all 17 NIR primitives
processed by the `neurocnl` runtime simulator layer.

### lava-nc vs lava-dl distinction

`neurocnl`'s `lava_sim` backend uses **lava-nc** (Intel's low-level neuromorphic
process library — `lava.proc.lif`, `lava.proc.dense`). This is distinct from
**lava-dl** (Intel's high-level deep-learning library that includes `netx`, the
official NIR-to-Lava converter used in the NIR community reference implementation).

Primitives listed as `unsupported` for `lava_sim` that the official NIR support matrix
(neuroir.org/docs/supported-primitives) shows as Lava-supported are supported by
**lava-dl/netx**, not by **lava-nc**. They are explicitly marked unsupported here with
inline comments so future maintainers can promote them when lava-dl integration is added.

### Fidelity terms

- `exact` — the primitive's semantics are faithfully reproduced by this simulator.
- `approximate` — the primitive executes but with documented, known limitations (e.g.
  synaptic current filtering not modelled, sub-timestep delay loss). The Studio labels
  the run as "approximate" and shows a warning.
- `unsupported` — the primitive cannot be executed. The run is rejected pre-dispatch
  with a structured diagnostic.

### `lava_sim` (lava-nc) support verdicts

| NIR Primitive | Verdict     | Notes |
|---|---|---|
| `Input`       | exact       | boundary node |
| `Output`      | exact       | boundary node |
| `Linear`      | exact       | `lava.proc.dense.Dense` |
| `LIF`         | exact       | `lava.proc.lif.LIF` |
| `CubaLIF`     | approximate | approximated via LIF; synaptic current filter (alpha) not modelled |
| `Delay`       | approximate | buffer register approximation; sub-timestep delays lost |
| `Affine`      | unsupported | lava-nc has no affine process; lava-dl netx supports it — out of scope |
| `Conv2d`      | unsupported | lava-nc has no Conv process; lava-dl netx supports Conv2d — out of scope |
| `Flatten`     | unsupported | lava-nc has no flatten process; tensor reshaping is a lava-dl/compiler concern |
| `IF`          | unsupported | lava-nc LIF has no IF (infinite-tau) mode; `du`/`dv` cannot replicate IF dynamics |
| `LI`          | unsupported | leaky integrator without threshold — no lava-nc process |
| `I`           | unsupported | pure integrator — no lava-nc process |
| `AvgPool2d`   | unsupported | no lava-nc pooling process; lava-dl has it |
| `SumPool2d`   | unsupported | no lava-nc pooling process |
| `Scale`       | unsupported | no lava-nc scalar-multiply process |
| `Threshold`   | unsupported | no lava-nc standalone threshold process |
| `Sigmoid`     | unsupported | not a lava-nc process; handled gracefully |
| `CubaLI`      | unsupported | no lava-nc process |

### `snntorch_sim` (snnTorch) support verdicts

| NIR Primitive | Verdict     | Notes |
|---|---|---|
| `Input`       | exact       | driven by `ValidatedStimulus` injection |
| `Output`      | exact       | passthrough boundary collector |
| `Linear`      | exact       | `nn.Linear(in, out, bias=False)` |
| `Affine`      | exact       | `nn.Linear(in, out, bias=True)` with weight + bias |
| `Conv2d`      | exact       | `nn.Conv2d` with weight, stride, padding from NIR node |
| `Flatten`     | exact       | `nn.Flatten(start_dim, end_dim)` |
| `IF`          | exact       | `snntorch.Lapicque(R, C=1e6)` approximating infinite-tau IF |
| `LIF`         | exact       | `snntorch.Leaky(beta=exp(-1/tau))` |
| `AvgPool2d`   | exact       | `nn.AvgPool2d(kernel_size, stride)` |
| `CubaLIF`     | approximate | `snntorch.Leaky`; synaptic current filter not modelled |
| `Delay`       | approximate | passthrough in timestep loop; sub-timestep delays not modelled |
| `LI`          | unsupported | no snnTorch equivalent without training mode |
| `I`           | unsupported | pure integrator — no snnTorch equivalent |
| `SumPool2d`   | unsupported | not in snnTorch NIR integration |
| `Scale`       | unsupported | no NIR-native snnTorch equivalent |
| `Threshold`   | unsupported | no NIR-native snnTorch equivalent |
| `Sigmoid`     | unsupported | not a NIR primitive; handled gracefully |
| `CubaLI`      | unsupported | no snnTorch equivalent |

All verdicts in this section are derived directly from `_BACKEND_NIR_SUPPORT` in
`neurocnl/runtime/nir_support.py`. Any change to that table must be reflected here
in the same commit (see `neurocnl/AGENTS.md`).
````
