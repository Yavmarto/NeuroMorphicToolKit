# Implementation Plan: weight-init-option-b

## Overview

Add Xavier (Glorot) uniform and Kaiming (He) uniform weight initialisation to the CNL → NIR
compiler's parameter materialisation stage. The change is confined to
`neurocnl/neurocnl/nir_cnl/compiler.py` (two function signatures + new sampling logic) and two
new test files. No parser, grammar-table, or downstream-surface changes are required.

## Tasks

- [x] 1. Extend `_resolve_tensor` signature and thread `record` through `_resolve_param`
  - Add `record: NIRNodeRecord` as a keyword-only parameter to `_resolve_tensor` in
    `neurocnl/neurocnl/nir_cnl/compiler.py`
  - Update the single call site in `_resolve_param` (`kind == "tensor"` branch) to pass
    `record=record` to `_resolve_tensor`
  - Leave all other call sites (`_resolve_vector`, `_resolve_int_tuple`, etc.) and all
    per-Primitive builders untouched — `record` is already available in every builder that
    calls `_resolve_param`
  - _Requirements: 5.1_

- [x] 2. Implement weight initialisation logic in the `ArraySpec` branch of `_resolve_tensor`
  - [x] 2.1 Read and normalise `weight_init` from `record.metadata`
    - After the existing shape-rank and shape-dims validation calls, read
      `record.metadata.get("weight_init", "")`, strip whitespace, and lowercase
    - If the result is empty or falsy, return `np.zeros(shape, dtype=float)` immediately
      (backward-compatible zero-fill path preserved)
    - _Requirements: 1.1, 1.2, 5.1_

  - [x] 2.2 Validate `weight_init` string and raise `CompileError` on unknown values
    - After confirming the value is non-empty, check it is in `{"xavier", "kaiming"}`
    - If not, call `_raise_single(code="invalid_value", ...)` including the raw pre-normalisation
      value and listing `"xavier"` and `"kaiming"` as accepted alternatives; include `line=line`
    - This check MUST occur before any seed or rank validation (Requirement 6.5)
    - _Requirements: 2.6, 5.6, 6.1, 6.5_

  - [x] 2.3 Validate `seed` from `record.metadata` and raise `CompileError` on bad values
    - Read `record.metadata.get("seed", 42)`; attempt `int(raw_seed)` inside a try/except
    - Reject negative integers and non-integer types with
      `_raise_single(code="invalid_value", ...)` including the offending raw value; include
      `line=line`
    - _Requirements: 4.7, 6.2, 6.3, 6.4_

  - [x] 2.4 Add rank guard for `weight_init` on tensors with rank < 2
    - After seed validation, check `len(shape) < 2`; raise `CompileError` with
      `code="invalid_value"` indicating rank >= 2 is required
    - _Requirements: 2.7, 3.6_

  - [x] 2.5 Derive `fan_in` / `fan_out` and compute the distribution bound
    - For rank-2 tensors: `fan_in = shape[1]`, `fan_out = shape[0]`,
      `receptive_field_size = 1`
    - For rank > 2: `receptive_field_size = int(np.prod(shape[2:]))`,
      `fan_in = shape[1] * receptive_field_size`,
      `fan_out = shape[0] * receptive_field_size`
    - Guard `fan_in == 0` with `_raise_single(code="invalid_value", ...)` before division
      (Requirement 3.7)
    - Xavier: `limit = np.sqrt(6.0 / (fan_in + fan_out))`; guard `fan_in + fan_out == 0`
    - Kaiming: `limit = np.sqrt(3.0 / fan_in)`
    - _Requirements: 2.1, 2.2, 2.3, 3.1, 3.2, 3.3, 3.7_

  - [x] 2.6 Sample with an isolated `numpy.random.default_rng` and return `float64`
    - Instantiate `rng = np.random.default_rng(seed=seed)` — one new instance per call, never
      reused or stored at class/module level
    - Return `rng.uniform(-limit, limit, size=shape).astype(np.float64)`
    - Do NOT touch `np.random.seed()`, `np.random.RandomState()`, or Python `random` module
    - _Requirements: 1.2, 1.3, 4.1, 4.2, 4.5, 7.1, 7.2, 7.3_

- [x] 3. Checkpoint — compiler changes complete
  - Ensure all existing tests still pass: `PYTHONPATH=. pytest neurocnl/tests/`
  - Run `ruff check .` and `mypy .` and fix any issues before proceeding
  - Ask the user if questions arise.

- [x] 4. Write unit tests in `test_compiler_weight_init.py`
  - Create `neurocnl/neurocnl/tests/nir_native_cnl/test_compiler_weight_init.py`
  - Use `NIRNodeRecord` directly (no CNL text round-trip) to exercise compiler logic in
    isolation, following the pattern in existing compiler tests
  - [x] 4.1 Implement `TestDefaultZeroFill`
    - `test_no_weight_init_produces_zeros` — no `weight_init` key → all zeros (Req 1.1)
    - `test_empty_weight_init_produces_zeros` — `weight_init: ""` → all zeros (Req 1.1)
    - `test_whitespace_weight_init_produces_zeros` — `weight_init: "  "` → all zeros (Req 1.1)
    - `test_zero_fill_dtype_is_float64` — zero-fill result dtype is `float64` (Req 1.2)
    - _Requirements: 1.1, 1.2_

  - [x] 4.2 Implement `TestXavierInitialisation`
    - `test_xavier_rank2_bound_small_matrix` — all weights in `[-a, a]` for small shape (Req 2.4)
    - `test_xavier_rank2_bound_large_matrix` — variance within 5 % of `a²/3` for shape
      `(100, 100)` (Req 2.5)
    - `test_xavier_rank3_bound` — rank-3 tensor, fan derivation correct (Req 2.3)
    - `test_xavier_case_insensitive` — `"XAVIER"` accepted (Req 5.2)
    - `test_xavier_whitespace_trimmed` — `"  xavier  "` accepted (Req 5.2)
    - `test_xavier_dtype_is_float64` — result dtype is `float64` (Req 1.2)
    - _Requirements: 1.2, 2.1, 2.3, 2.4, 2.5, 5.2_

  - [x] 4.3 Implement `TestKaimingInitialisation`
    - `test_kaiming_rank2_bound_small_matrix` — all weights in `[-a, a]` (Req 3.4)
    - `test_kaiming_rank2_bound_large_matrix` — variance within 5 % of `a²/3` for shape
      `(100, 100)` (Req 3.5)
    - `test_kaiming_rank3_bound` — rank-3 tensor, fan_in derivation correct (Req 3.3)
    - `test_kaiming_case_insensitive` — `"KAIMING"` accepted (Req 5.3)
    - `test_kaiming_dtype_is_float64` — result dtype is `float64` (Req 1.2)
    - _Requirements: 1.2, 3.1, 3.3, 3.4, 3.5, 5.3_

  - [x] 4.4 Implement `TestDeterminism`
    - `test_same_seed_produces_equal_arrays` — compile same record twice, assert
      `numpy.array_equal(w1, w2)` (Req 4.3)
    - `test_default_seed_42_is_deterministic` — absent seed key uses 42, result reproducible
      (Req 4.2)
    - `test_different_seeds_produce_different_arrays` — seeds 42 vs 43, assert not equal (Req 4.4)
    - _Requirements: 4.1, 4.2, 4.3, 4.4_

  - [x] 4.5 Implement `TestRNGIsolation`
    - `test_global_numpy_state_unchanged_xavier` — snapshot `np.random.get_state()` before/after,
      assert equal (Req 7.3)
    - `test_global_numpy_state_unchanged_kaiming` — same for kaiming (Req 7.3)
    - `test_concurrent_same_seed` — two threads compile the same record concurrently, both
      produce identical arrays (Req 7.4)
    - _Requirements: 1.3, 7.2, 7.3, 7.4_

  - [x] 4.6 Implement `TestDiagnosticErrors`
    - `test_invalid_weight_init_raises` — e.g. `"normal"` raises `CompileError` with
      `code="invalid_value"` (Req 2.6)
    - `test_invalid_weight_init_message_content` — diagnostic message includes raw value and
      accepted alternatives (Req 6.1)
    - `test_invalid_seed_string_raises` — `seed: "abc"` raises `CompileError` (Req 4.7, 6.2)
    - `test_invalid_seed_negative_raises` — `seed: -1` raises `CompileError` (Req 4.7)
    - `test_invalid_seed_float_raises` — `seed: 1.5` raises `CompileError` (Req 4.7)
    - `test_weight_init_checked_before_seed` — invalid `weight_init` + invalid `seed`: only
      `weight_init` error raised (Req 6.5)
    - `test_rank1_xavier_raises` — shape `(5,)` + xavier raises `CompileError` (Req 2.7)
    - `test_rank1_kaiming_raises` — shape `(5,)` + kaiming raises `CompileError` (Req 3.6)
    - `test_zero_fan_in_kaiming_raises` — degenerate shape with `shape[1]=0` raises (Req 3.7)
    - `test_line_number_in_diagnostic` — `record.line = 7`, diagnostic carries `line=7` (Req 6.3)
    - _Requirements: 2.6, 2.7, 3.6, 3.7, 4.7, 6.1, 6.2, 6.3, 6.5_

  - [x] 4.7 Implement `TestArrayValuesPassthrough`
    - `test_arrayvalues_not_overridden_by_weight_init` — `ArrayValues` with `weight_init`
      metadata set is returned as-is without modification (Req 5.5)
    - _Requirements: 5.5_

- [x] 5. Write property-based tests in `test_weight_init_properties.py`
  - Create `neurocnl/neurocnl/tests/nir_native_cnl/test_weight_init_properties.py`
  - Use `from hypothesis import given, settings` and `hypothesis.strategies` following the
    pattern in `test_shape_properties.py`; minimum `max_examples=100, deadline=None` per test
  - Define `_make_linear_record(M, N, scheme, seed=None)` helper that builds a `NIRNodeRecord`
    with `ArraySpec(shape=(M, N))` directly (no CNL text)

  - [x] 5.1 Write property test for Property 1: Xavier bound invariant
    - `@given(M=st.integers(1,512), N=st.integers(1,512), seed=st.integers(0, 2**32-1))`
    - Assert every element `w` satisfies `-a <= w <= a` where `a = sqrt(6.0 / (M + N))`
    - **Property 1: Xavier bound invariant**
    - **Validates: Requirements 2.1, 2.4, 9.1**

  - [x] 5.2 Write property test for Property 2: Kaiming bound invariant
    - `@given(M=st.integers(1,512), N=st.integers(1,512), seed=st.integers(0, 2**32-1))`
    - Assert every element `w` satisfies `-a <= w <= a` where `a = sqrt(3.0 / N)`
    - **Property 2: Kaiming bound invariant**
    - **Validates: Requirements 3.1, 3.4, 9.2**

  - [x] 5.3 Write property test for Property 3: Determinism under same seed
    - `@given(M=st.integers(1,512), N=st.integers(1,512), seed=st.integers(0, 2**32-1), scheme=st.sampled_from(["xavier","kaiming"]))`
    - Compile same record twice, assert `numpy.array_equal(w1, w2)`
    - **Property 3: Determinism under same seed**
    - **Validates: Requirements 4.1, 4.3, 7.1, 9.3**

  - [x] 5.4 Write property test for Property 4: dtype is always float64
    - `@given(M=st.integers(1,64), N=st.integers(1,64), scheme=st.sampled_from(["xavier","kaiming"]))`
    - Assert `result.dtype == np.float64`
    - **Property 4: dtype is always float64**
    - **Validates: Requirements 1.2, 9.4**

  - [x] 5.5 Write property test for Property 5: Global numpy random state not mutated
    - `@given(M=st.integers(1,64), N=st.integers(1,64), scheme=st.sampled_from(["xavier","kaiming"]), seed=st.integers(0, 2**32-1))`
    - Snapshot `np.random.get_state()` before/after, assert name and state array are unchanged
    - **Property 5: Global numpy random state not mutated**
    - **Validates: Requirements 1.3, 7.3, 9.5**

- [x] 6. Checkpoint — unit and property tests pass
  - Run `PYTHONPATH=. pytest neurocnl/neurocnl/tests/nir_native_cnl/test_compiler_weight_init.py neurocnl/neurocnl/tests/nir_native_cnl/test_weight_init_properties.py -v`
  - Run full suite: `PYTHONPATH=. pytest neurocnl/tests/`
  - Fix any failures before proceeding. Ask the user if questions arise.

- [x] 7. Write integration test for non-zero downstream activity
  - Add `TestIntegrationSnnTorchActivity` to
    `neurocnl/neurocnl/tests/nir_native_cnl/test_compiler_weight_init.py` (or to
    the existing `test_run_simulation.py` if the snnTorch fixture is already established there)
  - [x] 7.1 Implement `test_xavier_weights_produce_nonzero_spikes`
    - Compile CNL topology: `Input(4)` → `Linear(4×4, weight_init="xavier", seed=1)` → `LIF`
      via `compile_to_nir`
    - Run `snntorch_sim` with `timesteps=100, firing_rate=0.3, seed=1`
    - Assert spike map for LIF node is non-empty
    - _Requirements: 8.1_

  - [x] 7.2 Implement `test_zero_weights_produce_empty_spikes`
    - Same topology without any `weight_init` annotation (zero weights)
    - Assert spike map for LIF node is empty
    - _Requirements: 8.2_

- [x] 8. Final checkpoint — full suite and static analysis clean
  - `PYTHONPATH=. pytest neurocnl/tests/`
  - `ruff check .`
  - `mypy .`
  - `python3 -m pytest tests/integration/test_cross_module.py`
  - Ensure all checks pass with zero errors. Ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- All code must pass `ruff check .` and `mypy .` before each checkpoint
- The `record` parameter added to `_resolve_tensor` is keyword-only to preserve
  backward compatibility with any internal callers; the only call site is `_resolve_param`
- Validation order inside `_resolve_tensor` is strict: weight_init string → seed → rank →
  fan_in → bound computation (Requirement 6.5); never reorder these checks
- The `ArrayValues` branch in `_resolve_tensor` is left completely unchanged (Requirement 5.5)
- `_resolve_vector` is intentionally NOT changed — weight_init semantics apply only to
  `"tensor"` kind parameters
- Use `NIRNodeRecord` directly in all tests — no CNL text round-trip — to keep tests isolated
  to compiler logic
- Integration test (Task 7) depends on `snntorch_sim` being available in the test environment;
  mark with `pytest.importorskip("snntorch")` if the dependency may be absent

## Task Dependency Graph

```json
{
  "waves": [
    { "id": 0, "tasks": ["1"] },
    { "id": 1, "tasks": ["2.1"] },
    { "id": 2, "tasks": ["2.2"] },
    { "id": 3, "tasks": ["2.3"] },
    { "id": 4, "tasks": ["2.4"] },
    { "id": 5, "tasks": ["2.5"] },
    { "id": 6, "tasks": ["2.6"] },
    { "id": 7, "tasks": ["4.1", "4.2", "4.3", "4.4", "4.5", "4.6", "4.7", "5.1", "5.2", "5.3", "5.4", "5.5"] },
    { "id": 8, "tasks": ["7.1", "7.2"] }
  ]
}
```
