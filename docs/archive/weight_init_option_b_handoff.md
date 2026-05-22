# Option B Handoff: In-Compiler Weight Initialization

This handoff document details the design, syntax, mathematical specification, architectural implementation plan, and verification strategy for **Option B: In-Compiler Weight Initialization**. 

By introducing Xavier (Glorot) and Kaiming (He) uniform weight initialization for shape-only declarations (`ArraySpec`) during CNL $\rightarrow$ NIR compilation, we resolve the "zero-activity" bug in downstream neuromorphic simulators where populations receive zero synaptic currents and never fire.

---

## 1. Context & Motivation

### The "Zero-Activity" Problem
When compiling a CNL template (such as an actuator or interneuron pathway) that defines shape-only connections:
```markdown
Create a linear transformation named lin1 with weight matrix shape (100, 200).
```
The compiler currently resolves this `ArraySpec` by returning a dense matrix of all zeros:
```python
# neurocnl/neurocnl/nir_cnl/compiler.py:355
return np.zeros(value.shape, dtype=float)
```
Because the compiled `nir.NIRGraph` carries weight matrices populated entirely with `0.0`, any downstream simulations (e.g. via `snntorch_sim` or Lava) fail to propagate activity. Neurons in downstream populations receive no input current, remaining completely silent.

### Option B: In-Compiler Weight Initialization
To solve this without forcing users to manually author massive numeric value arrays in CNL (which breaks abstraction), **Option B** implements standard statistical initializers directly inside the compiler's parameter materialization stage. This approach guarantees:
1. **Cross-Backend Compatibility:** Because weights are initialized directly in the compiled NIR graph, the statistical parameters are baked into the serialized representation, making them automatically available to all downstream runtimes (snnTorch, Lava, PyTorch, Akida) without backend-specific code.
2. **Determinism:** Random initialization uses a seed (either custom or a global fallback) to ensure that repeated compilation of the same CNL file yields the exact same weight matrix.

---

## 2. Syntax Design: Metadata vs. Grammar Keywords

We evaluate two distinct approaches for conveying the initialization scheme in the CNL source file:

| Criterion | Approach 1: Metadata Annotation (Recommended) | Approach 2: Grammar Keyword Extension |
| :--- | :--- | :--- |
| **Example Syntax** | `... with weight matrix shape (100, 200) annotated with metadata weight_init equal to "xavier".` | `... with weight matrix shape (100, 200) initialized with xavier.` |
| **Parser Impact** | **Zero changes required.** The parser already fully supports the metadata clause sub-rule and populates `record.metadata` dictionary. | **High impact.** Requires adding `initialized`, `with`, `xavier`, `kaiming` keywords, updating Lexer/Parser tables, and modifying `grammar_tables.py` and `parser.py`. |
| **Backward Compatibility** | Fully backward-compatible; older parsers ignore the metadata or treat it as passive payload, and existing files remain valid. | Potentially introduces syntax breaking changes or parser ambiguity. |
| **Durable Knowledge** | Simple to strip or skip during rendering and easily extensible for additional parameter configurations. | Rigid grammar that requires continuous parser refactoring for any new initialization method. |

> [!TIP]
> **Recommendation:** We proceed with **Approach 1 (Metadata Annotation)**. It achieves the exact desired functionality with zero modifications to the parser frontend, keeping the parsing phase simple, fast, and robust while isolating the weight generation logic entirely inside the compiler stage.

---

## 3. Mathematical Specification

The compiler will support two primary weight initialization strategies, drawing values from a uniform distribution $\mathcal{U}(-a, a)$ based on layer dimensions.

### Parameter Definitions
*   $R$: Rank of the parameter array (e.g. $R=2$ for `Linear`/`Affine`, $R=3$ for `Conv1d`, $R=4$ for `Conv2d`).
*   `shape`: Dimensions of the weight array.
    *   Linear/Affine: `(out_features, in_features)` (Rank 2).
    *   Conv1d: `(out_channels, in_channels_per_group, kT)` (Rank 3).
    *   Conv2d: `(out_channels, in_channels_per_group, kH, kW)` (Rank 4).
*   $\text{fan\_in}$: Number of input units to the layer.
*   $\text{fan\_out}$: Number of output units from the layer.

### Fan-In / Fan-Out Derivation
For any multi-dimensional tensor parameter of Rank $R \ge 2$:
*   **Linear/Affine ($R = 2$):**
    $$\text{fan\_in} = \text{shape}[1]$$
    $$\text{fan\_out} = \text{shape}[0]$$
*   **Convolutional ($R > 2$):**
    $$\text{receptive\_field\_size} = \prod_{i=2}^{R-1} \text{shape}[i]$$
    $$\text{fan\_in} = \text{shape}[1] \times \text{receptive\_field\_size}$$
    $$\text{fan\_out} = \text{shape}[0] \times \text{receptive\_field\_size}$$

---

### Initializer Bounds
#### 1. Xavier Uniform (Glorot Uniform)
Designed to keep the variance of activations and gradients consistent across layers.
*   **Uniform distribution range:** $[-a, a]$
*   **Bound formula:**
    $$a = \sqrt{\frac{6.0}{\text{fan\_in} + \text{fan\_out}}}$$

#### 2. Kaiming Uniform (He Uniform)
Optimal for layers with rectifier-like (or threshold-based spiking) activation functions.
*   **Uniform distribution range:** $[-a, a]$
*   **Bound formula:**
    $$a = \sqrt{\frac{3.0}{\text{fan\_in}}}$$

---

## 4. Seeding and Determinism

To ensure the compilation pipeline remains **100% deterministic** (a strict requirement for CI, regression testing, and neuromorphic chip configuration verification):
1.  **Deterministic RNG:** The compiler will use PyTorch/NumPy-style isolated generator instances:
    ```python
    rng = np.random.default_rng(seed=seed_value)
    ```
    Never use the shared global state `np.random.seed` or standard `random.seed`, which are prone to side effects from other threads or tasks.
2.  **Seed Hierarchy:**
    *   **Local Seed:** Look for `annotated with metadata seed equal to <int>` on the specific node.
    *   **Global Fallback Seed:** If no local seed is provided, fall back to a hardcoded constant default seed `42`. This ensures that compiling a CNL template always produces byte-identical weight matrices.

---

## 5. Architectural Implementation Plan in `compiler.py`

### Proposed Code Modifications
The parameter resolution function `_resolve_tensor` in `neurocnl/neurocnl/nir_cnl/compiler.py` currently receives only the raw parameter `value`. It must be extended to accept the entire node `record` so it can inspect `record.metadata`.

```diff
-def _resolve_tensor(
-    value: Any,
-    *,
-    expected_rank: int,
-    primitive: str,
-    arg_name: str,
-    line: int,
-) -> np.ndarray:
+def _resolve_tensor(
+    value: Any,
+    *,
+    expected_rank: int,
+    primitive: str,
+    arg_name: str,
+    line: int,
+    record: NIRNodeRecord,
+) -> np.ndarray:
```

Similarly, in `_resolve_param`:
```diff
     kind = spec.kind
     if kind == "vector":
         return _resolve_vector(
-            raw, primitive=primitive, arg_name=arg_name, line=line
+            raw, primitive=primitive, arg_name=arg_name, line=line, record=record
         )
     if kind == "tensor":
         return _resolve_tensor(
             raw,
             expected_rank=expected_rank if expected_rank is not None else spec.rank,
             primitive=primitive,
             arg_name=arg_name,
-            line=line,
+            line=line,
+            record=record,
         )
```

### In-Compiler Weight Generation Logic
Inside `_resolve_tensor` (and similarly for multidimensional `_resolve_vector` parameters if desired), we inject the initialization logic when resolving an `ArraySpec`:

```python
# Within _resolve_tensor when isinstance(value, ArraySpec)
shape = value.shape

# 1. Read metadata configuration
weight_init = str(record.metadata.get("weight_init", "")).strip().lower()
seed_val = record.metadata.get("seed", 42)

# If no initialization requested, retain current default (all zeros)
if not weight_init:
    return np.zeros(shape, dtype=float)

# Validate seed type
try:
    seed_val = int(seed_val)
except (ValueError, TypeError):
    _raise_single(
        code="invalid_value",
        message=f"Metadata parameter 'seed' must be an integer, got {seed_val!r}.",
        line=line,
    )

# 2. Extract fan-in and fan-out
rank = len(shape)
if rank < 2:
    # Fallback to standard Xavier/Kaiming 1D bounds, or warn/ignore
    fan_in = shape[0]
    fan_out = shape[0]
else:
    receptive_field_size = int(np.prod(shape[2:])) if rank > 2 else 1
    fan_in = shape[1] * receptive_field_size
    fan_out = shape[0] * receptive_field_size

# 3. Compute limits
if weight_init == "xavier":
    limit = np.sqrt(6.0 / (fan_in + fan_out))
elif weight_init == "kaiming":
    limit = np.sqrt(3.0 / fan_in)
else:
    _raise_single(
        code="invalid_value",
        message=(
            f"Unsupported weight initialization method {weight_init!r}. "
            f"Supported methods are 'xavier' or 'kaiming'."
        ),
        line=line,
    )

# 4. Generate values deterministically
rng = np.random.default_rng(seed=seed_val)
weights = rng.uniform(-limit, limit, size=shape)
return weights
```

---

## 6. Diagnostic Error Handling

The compiler must enforce strict validation to fail early and actionably if an invalid initialization configuration is provided. The following new errors must be handled:
1.  **Unsupported Init Method (`code="invalid_value"`):**
    *   *Trigger:* User provides `annotated with metadata weight_init equal to "normal"` or `"he"`.
    *   *Diagnostic Message:* `"Unsupported weight initialization method 'normal'. Supported methods are 'xavier' or 'kaiming'."`
2.  **Malformed Seed (`code="invalid_value"`):**
    *   *Trigger:* User provides `annotated with metadata seed equal to "abc"`.
    *   *Diagnostic Message:* `"Metadata parameter 'seed' must be an integer, got 'abc'."`

---

## 7. Verification & Testing Plan

To confirm the correctness, determinism, and performance of Option B, the following checks should be added to `neurocnl/neurocnl/tests/`:

### 1. Unit Tests for Compiler Initialization
Create `neurocnl/neurocnl/tests/test_compiler_weight_init.py` with tests verifying:
*   **Default Zero Fallback:** Assert that omitting `weight_init` continues to compile to a matrix containing exactly all `0.0`.
*   **Xavier Limits:** Assert that weights initialized with `"xavier"` lie strictly inside the theoretical bounds $[-a, a]$.
*   **Kaiming Limits:** Assert that weights initialized with `"kaiming"` lie strictly inside $[-a, a]$.
*   **Statistical Uniformity:** Generate a large matrix (e.g. `(500, 500)`) and assert that the computed variance and standard deviation match mathematical uniform distribution expectations:
    $$\text{Var} = \frac{(2a)^2}{12} = \frac{a^2}{3}$$
*   **100% Determinism:** Compile the same CNL program with seed `42` twice and assert `np.allclose(w1, w2)` is strictly true. Assert that changing the seed to `123` produces a different, yet valid, weight matrix.
*   **Diagnostic Failures:** Verify that `invalid_value` compile errors are correctly raised for unsupported string schemes or non-integer seeds.

### 2. Integration / Downstream Activity Verification
Verify the compilation through the standard simulator runtime:
*   Compile a CNL template featuring an `Input`, a `Linear` layer with Xavier-initialized weights, and a downstream `LIF` interneuron.
*   Run the compiled `NIRGraph` through the `snntorch_sim` simulation endpoint using the default Poisson input stimuli.
*   **Success Assertion:** Verify that the `LIF` interneuron successfully fires spikes (has a non-empty spike train), proving that synaptic current is flowing through the initialized weights.

---

## 8. Handoff Checklist for Next Engineer

When implementing this, make sure to execute the following steps in order:
- [ ] Read `CODING_STYLE_GUIDE.md` and `neurocnl/AGENTS.md` before making any code modifications.
- [ ] Edit `neurocnl/neurocnl/nir_cnl/compiler.py` to add `record` references to `_resolve_tensor` and `_resolve_vector`.
- [ ] Add the statistical Xavier and Kaiming uniform sampling logic inside the `ArraySpec` branch using an isolated `np.random.default_rng`.
- [ ] Add diagnostic checks and compile error raising for malformed metadata attributes.
- [ ] Implement and execute unit tests in `neurocnl/neurocnl/tests/test_compiler_weight_init.py`.
- [ ] Execute standard repository checks:
    ```bash
    PYTHONPATH=. pytest neurocnl/tests/
    ruff check .
    mypy .
    ```
- [ ] Verify suite-level safety by running:
    ```bash
    python3 -m pytest tests/integration/test_cross_module.py
    ```
- [ ] Update `open-brain` thoughts/KIs upon successful validation.
