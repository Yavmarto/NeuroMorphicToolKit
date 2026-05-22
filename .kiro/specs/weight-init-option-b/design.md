# Design Document: `weight-init-option-b`

## Overview

This feature adds Xavier (Glorot) uniform and Kaiming (He) uniform weight initialisation to the
CNL → NIR compiler's parameter materialisation stage. The change resolves the "zero-activity"
bug where every shape-only connection declaration (`ArraySpec`) compiles to a dense zero matrix,
causing downstream neuromorphic simulators to receive no synaptic current and produce silent
neuron populations.

The approach (Option B from the handoff) is entirely in-compiler: no CNL grammar or parser
changes are required. The initialisation scheme is conveyed through the existing metadata
annotation clause (`annotated with metadata weight_init equal to "xavier"`). An isolated
`numpy.random.default_rng(seed)` instance per call guarantees determinism and global-state
isolation.

**Scope of change:** one function signature change in `_resolve_tensor` (and its call site in
`_resolve_param`), plus the sampling logic inside the `ArraySpec` branch. Everything else in
the compiler, parser, renderer, and downstream surfaces is unchanged.

---

## Architecture

### Where the Change Lives in the Pipeline

```
CNL source text
      │
      ▼
  NIR_CNL_Parser              ← unchanged
  (grammar_tables, parser.py)
      │
      │  produces list of [NIRNodeRecord | NIREdgeRecord | NetworkContainer]
      │  NIRNodeRecord.metadata carries {"weight_init": "xavier", "seed": 42}
      ▼
  NIR_Compiler.compile()      ← Phase 4: per-node materialisation
      │
      ├─ _build_linear(record)
      │       │
      │       └─ _resolve_param(record, "weight", …, expected_rank=2)
      │               │
      │               └─ _resolve_tensor(value, …, record=record)   ← CHANGED
      │                       │
      │                       ├─ isinstance(value, ArraySpec)?  YES
      │                       │       │
      │                       │       ├─ validate shape rank / dims
      │                       │       ├─ read record.metadata["weight_init"]
      │                       │       ├─ validate weight_init string
      │                       │       ├─ read / validate record.metadata["seed"]
      │                       │       ├─ derive fan_in / fan_out from shape
      │                       │       ├─ compute bound a
      │                       │       └─ rng.uniform(-a, a, shape) → np.ndarray
      │                       │
      │                       └─ isinstance(value, ArrayValues)?  YES → as-is
      │
      ▼
  nir.NIRGraph
  (nodes carry initialized numpy arrays as weights)
      │
      ▼
  Downstream consumers
  (snntorch_sim, Lava, Akida, PyTorch)
```

The compiler is stateless; every call to `NIR_Compiler.compile()` is independent. No class-level
or module-level RNG state is created.

---

## Components and Interfaces

### Modified: `_resolve_tensor`

**Current signature:**
```python
def _resolve_tensor(
    value: Any,
    *,
    expected_rank: int,
    primitive: str,
    arg_name: str,
    line: int,
) -> np.ndarray:
```

**New signature:**
```python
def _resolve_tensor(
    value: Any,
    *,
    expected_rank: int,
    primitive: str,
    arg_name: str,
    line: int,
    record: NIRNodeRecord,
) -> np.ndarray:
```

The new `record` keyword-only parameter provides access to `record.metadata` (for `weight_init`
and `seed`) and to `record.line` (for diagnostic error reporting).

### Modified: `_resolve_param`

The `_resolve_param` function passes `record` down to `_resolve_tensor` and `_resolve_vector`:

```python
if kind == "tensor":
    rank = expected_rank if expected_rank is not None else (spec.rank or 2)
    return _resolve_tensor(
        raw,
        expected_rank=rank,
        primitive=primitive,
        arg_name=arg_name,
        line=line,
        record=record,       # NEW
    )
```

The `record` argument is already available in `_resolve_param` as its first positional parameter,
so no additional threading is needed.

### Unchanged: `_resolve_vector`

The `_resolve_vector` function handles `"vector"` kind parameters (per-neuron vectors like `tau`,
`r`, `v_threshold`). These do not carry `weight_init` semantics and are not changed. The
`_resolve_param` call site for `"vector"` is not modified.

### Unchanged: all per-Primitive builders

`_build_linear`, `_build_affine`, `_build_conv1d`, `_build_conv2d`, and all other builders
already pass `record` to `_resolve_param`. No changes are required in any builder function.

---

## Data Models

### `NIRNodeRecord` (no changes)

```python
@dataclass(slots=True)
class NIRNodeRecord:
    name: str
    primitive: str
    params: dict[str, int | float | ArraySpec | ArrayValues | tuple[int, ...]]
    metadata: dict[str, str | int | float]   # carries weight_init, seed
    line: int
```

The `metadata` field already accepts `str`, `int`, and `float` values. `weight_init` arrives as
a `str`; `seed` arrives as an `int` (when the user writes an integer literal in the CNL source).

### `ArraySpec` (no changes)

```python
@dataclass(frozen=True, slots=True)
class ArraySpec:
    shape: tuple[int, ...]
```

Shape-only declaration. The compiler's `_resolve_tensor` function is the only consumer that
gains new behaviour when an `ArraySpec` is present and `weight_init` metadata is set.

### Internal: weight initialisation parameters (not a new class)

The initialisation parameters are computed locally inside `_resolve_tensor`; they are not
persisted in a new dataclass. The compiled `nir.*` node receives the initialised `np.ndarray`
directly, which is then attached to the NIRGraph via the existing builder mechanism.

---

## Low-Level Design

### Complete pseudocode for the `ArraySpec` branch of `_resolve_tensor`

```python
if isinstance(value, ArraySpec):
    # ── 1. Structural validation (unchanged) ──────────────────────────
    _validate_shape_rank(value.shape, expected_rank,
                         primitive=primitive, arg_name=arg_name, line=line)
    _validate_shape_dims(value.shape,
                         primitive=primitive, arg_name=arg_name, line=line)
    shape = value.shape

    # ── 2. Read and normalise weight_init ─────────────────────────────
    raw_init = record.metadata.get("weight_init", "")
    weight_init = str(raw_init).strip().lower()

    # No init requested → backward-compatible zero-fill (Requirement 1.1)
    if not weight_init:
        return np.zeros(shape, dtype=float)

    # ── 3. Validate weight_init string (Requirement 2.6, 6.1) ─────────
    if weight_init not in ("xavier", "kaiming"):
        _raise_single(
            code="invalid_value",
            message=(
                f"Unsupported weight_init value {raw_init!r} on node "
                f"{record.name!r}. Accepted values are 'xavier' and "
                f"'kaiming'."
            ),
            line=line,
            hint="Use weight_init equal to \"xavier\" or \"kaiming\".",
        )

    # ── 4. Validate and resolve seed (Requirement 4.7, 6.2) ───────────
    raw_seed = record.metadata.get("seed", 42)
    try:
        seed = int(raw_seed)
        if seed < 0:
            raise ValueError("negative")
    except (ValueError, TypeError):
        _raise_single(
            code="invalid_value",
            message=(
                f"Metadata 'seed' on node {record.name!r} must be a "
                f"non-negative integer, got {raw_seed!r}."
            ),
            line=line,
            hint="Use an integer literal: annotated with metadata seed equal to 42.",
        )

    # ── 5. Rank guard for initialisation (Requirement 2.7, 3.6) ───────
    rank = len(shape)
    if rank < 2:
        _raise_single(
            code="invalid_value",
            message=(
                f"weight_init={weight_init!r} on {primitive!r} "
                f"parameter {arg_name!r} requires a tensor of rank >= 2, "
                f"got rank {rank} (shape={shape})."
            ),
            line=line,
            hint="Provide a shape with at least 2 dimensions.",
        )

    # ── 6. Fan-in / fan-out derivation (Requirement 2.2, 2.3, 3.2, 3.3)
    if rank == 2:
        receptive_field_size = 1
    else:  # rank > 2 (convolutional)
        receptive_field_size = int(np.prod(shape[2:]))

    fan_in  = shape[1] * receptive_field_size
    fan_out = shape[0] * receptive_field_size

    # ── 7. Guard against degenerate fan (Requirement 3.7) ─────────────
    if fan_in == 0:
        _raise_single(
            code="invalid_value",
            message=(
                f"Computed fan_in=0 for {primitive!r} parameter "
                f"{arg_name!r} (shape={shape}). Cannot compute "
                f"{weight_init!r} bound."
            ),
            line=line,
            hint="Ensure all shape dimensions are >= 1.",
        )

    # ── 8. Compute distribution bound ─────────────────────────────────
    if weight_init == "xavier":
        if fan_in + fan_out == 0:
            _raise_single(
                code="invalid_value",
                message=(
                    f"Computed fan_in + fan_out = 0 for {primitive!r} "
                    f"parameter {arg_name!r}. Cannot compute Xavier bound."
                ),
                line=line,
            )
        limit = np.sqrt(6.0 / (fan_in + fan_out))
    else:  # kaiming
        limit = np.sqrt(3.0 / fan_in)

    # ── 9. Sample using isolated RNG (Requirement 7.1, 7.3) ───────────
    rng = np.random.default_rng(seed=seed)
    return rng.uniform(-limit, limit, size=shape).astype(np.float64)
```

### Fan-in / Fan-out Derivation Reference

| Tensor rank | `receptive_field_size` | `fan_in`                      | `fan_out`                     |
|-------------|------------------------|-------------------------------|-------------------------------|
| 2 (Linear)  | 1                      | `shape[1]`                    | `shape[0]`                    |
| 3 (Conv1d)  | `shape[2]`             | `shape[1] * shape[2]`         | `shape[0] * shape[2]`         |
| 4 (Conv2d)  | `shape[2] * shape[3]`  | `shape[1] * shape[2] * shape[3]` | `shape[0] * shape[2] * shape[3]` |

### Initialisation Bound Formulae

| Scheme  | Bound formula                            | Distribution          |
|---------|------------------------------------------|-----------------------|
| Xavier  | `a = sqrt(6.0 / (fan_in + fan_out))`     | `U(-a, a)`            |
| Kaiming | `a = sqrt(3.0 / fan_in)`                 | `U(-a, a)`            |

For a uniform distribution `U(-a, a)`, the theoretical variance is `a² / 3`.

---

## Error Handling

Validation is performed in strict order inside the `ArraySpec` branch. A failure at any step
raises immediately without proceeding to subsequent steps. This matches Requirement 6.5.

```
ArraySpec detected
      │
      ▼
1. shape rank check        → shape_rank_mismatch
2. shape dims check        → invalid_shape
3. weight_init absent?     → return np.zeros (no error)
4. weight_init valid?      → invalid_value  ← weight_init checked FIRST (Req 6.5)
5. seed valid integer?     → invalid_value
6. rank < 2?               → invalid_value
7. fan_in == 0?            → invalid_value
8. compute limit, sample   → (no error path)
9. return float64 array
```

**Diagnostic fields for all weight-init errors:**

| Field     | Value                                                                |
|-----------|----------------------------------------------------------------------|
| `stage`   | `"materializer"`                                                     |
| `code`    | `"invalid_value"`                                                    |
| `message` | Includes the offending raw value and accepted alternatives           |
| `line`    | `record.line` when it is a non-negative integer; omitted otherwise   |
| `hint`    | Actionable suggestion (e.g., accepted values, integer requirement)   |

---

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a
system — essentially, a formal statement about what the system should do. Properties serve as the
bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Xavier bound invariant

*For any* rank-2 weight shape `(M, N)` with `1 <= M, N <= 512`, every element `w` of the
Xavier-initialised array produced by the Compiler SHALL satisfy `-a <= w <= a` (inclusive)
where `a = sqrt(6.0 / (M + N))`.

**Validates: Requirements 2.1, 2.4, 9.1**

---

### Property 2: Kaiming bound invariant

*For any* rank-2 weight shape `(M, N)` with `1 <= M, N <= 512`, every element `w` of the
Kaiming-initialised array produced by the Compiler SHALL satisfy `-a <= w <= a` (inclusive)
where `a = sqrt(3.0 / N)`.

**Validates: Requirements 3.1, 3.4, 9.2**

---

### Property 3: Determinism under same seed

*For any* valid rank-2 shape `(M, N)` with `1 <= M, N <= 512` and any seed `s` in
`[0, 2^32 - 1]`, compiling the same `NIRNodeRecord` twice with the same seed SHALL produce
arrays `w1` and `w2` satisfying `numpy.array_equal(w1, w2)`.

**Validates: Requirements 4.1, 4.3, 7.1, 9.3**

---

### Property 4: dtype is always float64

*For any* valid weight shape and any initialisation scheme (`"xavier"` or `"kaiming"`), the
returned array SHALL have `dtype` equal to `float64`.

**Validates: Requirements 1.2, 9.4**

---

### Property 5: Global numpy random state is not mutated

*For any* valid weight shape and any initialisation scheme, the value of
`numpy.random.get_state()` (both the name string and the state array) sampled after the
compilation call SHALL equal the value sampled before the call.

**Validates: Requirements 1.3, 7.3, 9.5**

---

*Property reflection:* Properties 1 and 2 are distinct because they have different bound
formulae (fan_in + fan_out vs. fan_in alone). Property 3 (determinism) is not subsumed by
Properties 1/2 because it tests the sequence relationship between two calls, not the per-element
value bound. Properties 4 and 5 are orthogonal to the bound properties — they test dtype and
side-effect invariants that hold regardless of which values are produced.

---

## Testing Strategy

### Property-Based Testing Library

The existing test suite uses **Hypothesis** (`from hypothesis import given, settings`). All new
property tests follow the same conventions established in
`neurocnl/neurocnl/tests/nir_native_cnl/test_shape_properties.py`:

- `@given(...)` decorators with `@settings(max_examples=100, deadline=None)`
- Strategies from `hypothesis.strategies`
- Compiler invoked directly via `NIRNodeRecord` construction (no CNL text parsing)
- Located in `neurocnl/neurocnl/tests/nir_native_cnl/` alongside existing compiler property tests

### Test File Layout

```
neurocnl/neurocnl/tests/
├── nir_native_cnl/
│   ├── test_compiler_weight_init.py      ← NEW: unit tests (examples + edge cases)
│   └── test_weight_init_properties.py   ← NEW: property-based tests (Properties 1–5)
```

### Unit Test Structure (`test_compiler_weight_init.py`)

Each test group targets a specific requirement. Tests use `NIRNodeRecord` directly to avoid
parser round-trip noise in compiler-specific tests.

```
TestDefaultZeroFill
  test_no_weight_init_produces_zeros          # Req 1.1
  test_empty_weight_init_produces_zeros       # Req 1.1
  test_whitespace_weight_init_produces_zeros  # Req 1.1

TestXavierInitialisation
  test_xavier_rank2_bound_small_matrix        # Req 2.1, 2.4
  test_xavier_rank2_bound_large_matrix        # Req 2.5 (variance)
  test_xavier_rank3_bound                     # Req 2.3
  test_xavier_case_insensitive                # Req 5.2
  test_xavier_whitespace_trimmed              # Req 5.2

TestKaimingInitialisation
  test_kaiming_rank2_bound_small_matrix       # Req 3.1, 3.4
  test_kaiming_rank2_bound_large_matrix       # Req 3.5 (variance)
  test_kaiming_rank3_bound                    # Req 3.3
  test_kaiming_case_insensitive               # Req 5.3

TestDeterminism
  test_same_seed_produces_equal_arrays        # Req 4.1, 4.3
  test_default_seed_42_is_deterministic       # Req 4.2
  test_different_seeds_produce_different_arrays  # Req 4.4

TestRNGIsolation
  test_global_numpy_state_unchanged_xavier    # Req 7.3
  test_global_numpy_state_unchanged_kaiming   # Req 7.3
  test_concurrent_same_seed                   # Req 7.4

TestDiagnosticErrors
  test_invalid_weight_init_raises             # Req 2.6, 6.1
  test_invalid_weight_init_message_content    # Req 6.1 (message includes raw value + alternatives)
  test_invalid_seed_string_raises             # Req 4.7, 6.2
  test_invalid_seed_negative_raises           # Req 4.7
  test_invalid_seed_float_raises              # Req 4.7
  test_weight_init_checked_before_seed        # Req 6.5
  test_rank1_xavier_raises                    # Req 2.7
  test_rank1_kaiming_raises                   # Req 3.6
  test_zero_fan_in_kaiming_raises             # Req 3.7
  test_line_number_in_diagnostic              # Req 6.3

TestArrayValuesPassthrough
  test_arrayvalues_not_overridden_by_weight_init  # Req 5.5

TestDtypeInvariant
  test_xavier_dtype_is_float64                # Req 1.2
  test_kaiming_dtype_is_float64               # Req 1.2
  test_zero_fill_dtype_is_float64             # Req 1.2
```

### Property Test Structure (`test_weight_init_properties.py`)

Each property maps to exactly one `@given`-decorated test function tagged with the design
document property number. Minimum 100 iterations per test.

```python
# Feature: weight-init-option-b, Property 1: Xavier bound invariant
@given(
    M=st.integers(min_value=1, max_value=512),
    N=st.integers(min_value=1, max_value=512),
    seed=st.integers(min_value=0, max_value=2**32 - 1),
)
@settings(max_examples=100, deadline=None)
def test_property_1_xavier_bound_invariant(M, N, seed): ...

# Feature: weight-init-option-b, Property 2: Kaiming bound invariant
@given(
    M=st.integers(min_value=1, max_value=512),
    N=st.integers(min_value=1, max_value=512),
    seed=st.integers(min_value=0, max_value=2**32 - 1),
)
@settings(max_examples=100, deadline=None)
def test_property_2_kaiming_bound_invariant(M, N, seed): ...

# Feature: weight-init-option-b, Property 3: Determinism under same seed
@given(
    M=st.integers(min_value=1, max_value=512),
    N=st.integers(min_value=1, max_value=512),
    seed=st.integers(min_value=0, max_value=2**32 - 1),
    scheme=st.sampled_from(["xavier", "kaiming"]),
)
@settings(max_examples=100, deadline=None)
def test_property_3_determinism_same_seed(M, N, seed, scheme): ...

# Feature: weight-init-option-b, Property 4: dtype is always float64
@given(
    M=st.integers(min_value=1, max_value=64),
    N=st.integers(min_value=1, max_value=64),
    scheme=st.sampled_from(["xavier", "kaiming"]),
)
@settings(max_examples=100, deadline=None)
def test_property_4_dtype_float64(M, N, scheme): ...

# Feature: weight-init-option-b, Property 5: Global numpy random state not mutated
@given(
    M=st.integers(min_value=1, max_value=64),
    N=st.integers(min_value=1, max_value=64),
    scheme=st.sampled_from(["xavier", "kaiming"]),
    seed=st.integers(min_value=0, max_value=2**32 - 1),
)
@settings(max_examples=100, deadline=None)
def test_property_5_global_state_unchanged(M, N, scheme, seed): ...
```

Each property test builds a `NIRNodeRecord` directly (bypassing the CNL parser) so it exercises
the compiler logic in isolation:

```python
def _make_linear_record(M: int, N: int, scheme: str, seed: int | None = None) -> NIRNodeRecord:
    metadata: dict = {"weight_init": scheme}
    if seed is not None:
        metadata["seed"] = seed
    return NIRNodeRecord(
        name="w1",
        primitive="Linear",
        params={"weight": ArraySpec(shape=(M, N))},
        metadata=metadata,
        line=1,
    )
```

### Integration Test (`snntorch_sim`)

Located in `neurocnl/neurocnl/tests/test_compiler_weight_init.py` or the existing
`test_run_simulation.py`. Validates Requirement 8 end-to-end:

```
TestIntegrationSnnTorchActivity
  test_xavier_weights_produce_nonzero_spikes    # Req 8.1
  test_zero_weights_produce_empty_spikes        # Req 8.2
```

The integration test compiles a minimal CNL topology (Input(4) → Linear(4×4, xavier) → LIF)
via `compile_to_nir`, then runs `snntorch_sim` with `timesteps=100, firing_rate=0.3, seed=1`,
and asserts the spike map is non-empty for the LIF node.

### Verification Commands

```bash
# Run all compiler weight-init tests
PYTHONPATH=. pytest neurocnl/neurocnl/tests/nir_native_cnl/test_compiler_weight_init.py \
    neurocnl/neurocnl/tests/nir_native_cnl/test_weight_init_properties.py -v

# Run full neurocnl test suite
PYTHONPATH=. pytest neurocnl/tests/

# Static analysis
ruff check .
mypy .

# Cross-module integration (required when compiler output shape changes)
python3 -m pytest tests/integration/test_cross_module.py
```
