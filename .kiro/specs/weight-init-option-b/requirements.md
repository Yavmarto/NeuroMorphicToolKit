# Requirements Document

## Introduction

The CNL → NIR compiler currently materialises shape-only connection declarations (`ArraySpec`) as
dense zero matrices. Because downstream neuromorphic simulators (snnTorch, Lava, Akida) derive
synaptic current directly from these weight matrices, an all-zero initialisation causes every
downstream neuron population to remain completely silent — the "zero-activity" bug.

This feature adds Xavier (Glorot) uniform and Kaiming (He) uniform weight initialisation directly
inside the compiler's parameter materialisation stage. The chosen scheme is conveyed to the
compiler via a `weight_init` metadata annotation on the CNL node, keeping zero parser changes and
full backward compatibility. A `seed` metadata key provides deterministic initialisation suitable
for CI, regression testing, and neuromorphic chip configuration verification.

## Glossary

- **Compiler**: `NIR_Compiler` in `neurocnl/neurocnl/nir_cnl/compiler.py` — the materialisation
  stage that converts `NIRNodeRecord` lists into `nir.NIRGraph` objects.
- **ArraySpec**: An IR type representing a shape-only tensor declaration (no explicit values).
  Produced by the parser when the user writes `with weight matrix shape (M, N)`.
- **ArrayValues**: An IR type representing a tensor declaration with explicit numeric values.
- **NIRNodeRecord**: The intermediate record for a single CNL node, carrying `primitive`,
  `params`, `metadata`, `name`, and `line`.
- **Metadata**: The `record.metadata` dictionary populated by the parser from
  `annotated with metadata <key> equal to <value>` clauses in the CNL source.
- **weight_init**: The metadata key whose value selects the initialisation scheme.
  Accepted values: `"xavier"`, `"kaiming"`. Absent key → zero-fill (existing behaviour).
- **seed**: The optional metadata key whose integer value seeds the isolated RNG.
  Absent key → default seed `42`.
- **Xavier Uniform**: Glorot uniform initialisation. Draws weights from
  `U(-a, a)` where `a = sqrt(6 / (fan_in + fan_out))`.
- **Kaiming Uniform**: He uniform initialisation. Draws weights from
  `U(-a, a)` where `a = sqrt(3 / fan_in)`.
- **fan_in**: Number of input units to a layer derived from the weight tensor shape.
- **fan_out**: Number of output units from a layer derived from the weight tensor shape.
- **Receptive_Field_Size**: Product of kernel spatial dimensions `shape[2:]` for
  convolutional (rank > 2) weight tensors.
- **RNG**: Random number generator. Always an isolated `numpy.random.default_rng` instance.
- **CompileError**: The exception type raised by the Compiler on validation failure, carrying a
  list of `Diagnostic` objects.
- **Diagnostic**: A structured error record with fields `stage`, `code`, `message`, `line`,
  `raw`, and `hint`.

---

## Requirements

### Requirement 1: Backward-Compatible Zero-Fill Default

**User Story:** As a CNL author, I want my existing CNL files to compile without modification, so
that adopting the new compiler does not break any currently working network definitions.

#### Acceptance Criteria

1. WHEN a `NIRNodeRecord` with an `ArraySpec` parameter is compiled and `record.metadata` does
   not contain the key `"weight_init"`, or contains `"weight_init"` with an absent, empty, or
   whitespace-only string value, THE Compiler SHALL materialise the parameter as
   `numpy.zeros(shape, dtype=float)`.
2. THE Compiler SHALL produce a result array with `dtype` equal to `float64` for all
   `ArraySpec` materialisations regardless of initialisation scheme.
3. WHEN an `ArraySpec` parameter is materialised, THE Compiler SHALL use an isolated
   `numpy.random.default_rng` instance scoped to that call and SHALL NOT mutate the legacy
   `numpy.random` module-level state (e.g. `numpy.random.get_state()`) or the shared default
   Generator state.

---

### Requirement 2: Xavier Uniform Weight Initialisation

**User Story:** As a CNL author designing a feedforward or transformer network, I want to annotate
a shape-only weight parameter with `weight_init equal to "xavier"` so that the Compiler
initialises it with Glorot uniform values that preserve gradient variance across layers.

#### Acceptance Criteria

1. IF a `NIRNodeRecord` contains an `ArraySpec` parameter for `"weight"` and
   `record.metadata["weight_init"]` (after case-insensitive normalisation and whitespace trimming)
   equals `"xavier"`, THEN THE Compiler SHALL initialise the weight array by sampling each
   element independently from `U(-a, a)` where `a = sqrt(6.0 / (fan_in + fan_out))`, using an
   isolated `numpy.random.default_rng(seed)`.
2. WHEN Xavier initialisation is applied to a rank-2 weight tensor of shape `(M, N)`, THE
   Compiler SHALL compute `fan_in = N` and `fan_out = M`.
3. WHEN Xavier initialisation is applied to a rank-R (R > 2) weight tensor, THE Compiler SHALL
   compute `Receptive_Field_Size = product(shape[2:])`, `fan_in = shape[1] *
   Receptive_Field_Size`, and `fan_out = shape[0] * Receptive_Field_Size`.
4. IF the weight tensor rank is >= 2 and `fan_in + fan_out > 0`, THEN every element `w` of a
   Xavier-initialised array produced by the Compiler SHALL satisfy `-a <= w <= a` where
   `a = sqrt(6.0 / (fan_in + fan_out))`.
5. IF the weight tensor has rank >= 2 and at least 2500 elements, THEN the variance of a
   Xavier-initialised array produced by the Compiler SHALL satisfy
   `|variance - (a^2 / 3)| / (a^2 / 3) <= 0.05` where `a = sqrt(6.0 / (fan_in + fan_out))`.
6. IF `record.metadata["weight_init"]` is set to a value other than `"xavier"` or `"kaiming"`
   (after normalisation), THEN THE Compiler SHALL raise a `CompileError` with `code="invalid_value"`.
7. IF a `NIRNodeRecord` contains an `ArraySpec` parameter with rank < 2 and `"weight_init":
   "xavier"`, THEN THE Compiler SHALL raise a `CompileError` with `code="invalid_value"`
   indicating that Xavier initialisation requires a tensor of rank >= 2.

---

### Requirement 3: Kaiming Uniform Weight Initialisation

**User Story:** As a CNL author designing a spiking network with threshold-based (ReLU-like)
activation, I want to annotate a shape-only weight parameter with `weight_init equal to "kaiming"`
so that the Compiler initialises it with He uniform values optimised for rectifier activations.

#### Acceptance Criteria

1. WHEN a `NIRNodeRecord` contains an `ArraySpec` parameter for `"weight"` and
   `record.metadata["weight_init"]` (after case-insensitive normalisation) equals `"kaiming"`,
   THE Compiler SHALL initialise the weight array by sampling each element independently from
   `U(-a, a)` where `a = sqrt(3.0 / fan_in)` as derived in criteria 2 and 3.
2. WHEN Kaiming initialisation is applied to a rank-2 weight tensor of shape `(M, N)`, THE
   Compiler SHALL compute `fan_in = N`.
3. WHEN Kaiming initialisation is applied to a rank-R (R > 2) weight tensor, THE Compiler SHALL
   compute `Receptive_Field_Size = product(shape[2:])` and `fan_in = shape[1] *
   Receptive_Field_Size`.
4. THE Compiler SHALL ensure every element `w` of a Kaiming-initialised array satisfies
   `-a <= w <= a` where `a = sqrt(3.0 / fan_in)`.
5. THE Compiler SHALL ensure that for any Kaiming-initialised array with at least 2500 elements,
   the variance satisfies `|variance - (a^2 / 3)| / (a^2 / 3) <= 0.05`.
6. IF a `NIRNodeRecord` contains an `ArraySpec` parameter with rank < 2 and `"weight_init":
   "kaiming"`, THEN THE Compiler SHALL raise a `CompileError` with `code="invalid_value"`
   indicating that Kaiming initialisation requires a tensor of rank >= 2.
7. IF the computed `fan_in` is zero (e.g. a degenerate shape with a zero dimension), THEN THE
   Compiler SHALL raise a `CompileError` with `code="invalid_value"` before attempting to
   compute the Kaiming bound.

---

### Requirement 4: Deterministic Seeded Initialisation

**User Story:** As a CI pipeline or chip configuration tool, I want repeated compilations of the
same CNL file to produce byte-identical weight matrices, so that test reproducibility and
hardware configuration consistency are guaranteed.

#### Acceptance Criteria

1. WHEN a `NIRNodeRecord` metadata dictionary contains `"seed": <integer>`, THE Compiler SHALL
   instantiate `numpy.random.default_rng(seed=<integer>)` before generating the weight array.
2. WHEN a `NIRNodeRecord` metadata dictionary does not contain `"seed"`, THE Compiler SHALL use
   the default seed value `42`.
3. WHEN the same `NIRNodeRecord` is compiled twice sequentially in the same process with a seed
   value `s` in the range `[0, 2^128 - 1]`, THE Compiler SHALL produce arrays `w1` and `w2`
   satisfying `numpy.array_equal(w1, w2)`.
4. WHEN the same `NIRNodeRecord` is compiled twice with seeds `s1` and `s2` where
   `s1 != s2` (both in `[0, 2^128 - 1]`), THE Compiler SHALL produce arrays `w1` and `w2`
   such that `not numpy.array_equal(w1, w2)`.
5. THE Compiler SHALL use an isolated `numpy.random.default_rng` instance per materialisation
   call.
6. THE Compiler SHALL NOT mutate the global `numpy.random` module state during any
   weight-initialisation call.
7. IF `record.metadata["seed"]` is present and is not a non-negative integer (e.g. a float,
   string, or negative value), THEN THE Compiler SHALL raise a `CompileError` with
   `code="invalid_value"` before sampling any random values.

---

### Requirement 5: Metadata Annotation Syntax (No Parser Changes)

**User Story:** As a CNL author, I want to specify weight initialisation via the existing metadata
annotation clause, so that I can adopt the feature without learning new grammar keywords and
existing parsers remain forward-compatible.

#### Acceptance Criteria

1. THE Compiler SHALL read weight initialisation configuration exclusively from
   `record.metadata["weight_init"]` and `record.metadata["seed"]`, requiring zero modifications
   to the CNL parser or grammar tables.
2. WHEN a CNL source file contains
   `annotated with metadata weight_init equal to "xavier"`, THE Compiler SHALL interpret the
   parsed `record.metadata["weight_init"]` value (case-insensitive, whitespace-trimmed)
   as the Xavier initialisation scheme.
3. WHEN a CNL source file contains
   `annotated with metadata weight_init equal to "kaiming"`, THE Compiler SHALL interpret the
   parsed `record.metadata["weight_init"]` value (case-insensitive, whitespace-trimmed)
   as the Kaiming initialisation scheme.
4. WHERE the `"weight_init"` value is provided and the parameter is an `ArraySpec` with
   rank >= 2, THE Compiler SHALL apply the initialisation scheme to that parameter.
5. WHERE the `"weight_init"` value is provided and the parameter is an `ArrayValues` instance,
   THE Compiler SHALL materialise the parameter as-is without modification.
6. IF `record.metadata["weight_init"]` is set to a value other than `"xavier"` or `"kaiming"`
   (after normalisation), THEN THE Compiler SHALL raise a `CompileError` with
   `code="invalid_value"`. IF `record.metadata["seed"]` is absent, THEN THE Compiler SHALL
   default to seed `42`; IF `record.metadata["seed"]` is present but cannot be converted to
   `int`, THEN THE Compiler SHALL raise a `CompileError` with `code="invalid_value"`.

---

### Requirement 6: Diagnostic Error Handling

**User Story:** As a CNL author, I want the Compiler to report clear, actionable errors when I
provide an invalid `weight_init` scheme or a non-integer `seed`, so that I can quickly fix
mistakes without guessing what went wrong.

#### Acceptance Criteria

1. WHEN `record.metadata["weight_init"]` is set to a value other than `"xavier"` or `"kaiming"`
   (after case-insensitive normalisation), THE Compiler SHALL raise a `CompileError` with a
   `Diagnostic` carrying `code="invalid_value"`, including the original pre-normalisation
   offending value, and listing `"xavier"` and `"kaiming"` as the accepted alternatives.
2. WHEN `record.metadata["seed"]` is present and cannot be converted to a Python `int` via
   `int()`, THE Compiler SHALL raise a `CompileError` with a `Diagnostic` carrying
   `code="invalid_value"`, including the original offending value as supplied in the metadata.
3. WHEN the Compiler raises a `CompileError` for an invalid `weight_init` or `seed` value and
   `record.line` is a non-negative integer, THE Diagnostic SHALL include that source line number.
4. WHEN the Compiler raises a `CompileError` for an invalid `weight_init` or `seed` value and
   `record.line` is absent or not a non-negative integer, THE Compiler SHALL still raise the
   `CompileError` but the `Diagnostic` MAY omit the line number field.
5. WHEN both `record.metadata["weight_init"]` and `record.metadata["seed"]` are invalid, THE
   Compiler SHALL evaluate `weight_init` first, raise a `CompileError` for the invalid
   `weight_init` before checking `seed`, and SHALL NOT sample any random values.

---

### Requirement 7: RNG Isolation and Side-Effect Freedom

**User Story:** As a test suite or multi-threaded compilation pipeline, I want each weight
initialisation call to use an isolated random generator, so that compilation order and
concurrency cannot cause non-deterministic weight values.

#### Acceptance Criteria

1. WHEN a weight-initialisation compilation call is made, THE Compiler SHALL instantiate one
   new `numpy.random.default_rng` instance scoped to that call and SHALL NOT retain or reuse
   the generator across separate calls.
2. THE Compiler SHALL NOT call any function from the `numpy.random` legacy API (e.g.
   `numpy.random.seed()`, `numpy.random.RandomState()`) or Python `random` module that modifies
   shared global state.
3. WHEN a weight-initialisation compilation call completes (with seed in `[0, 2^32-1]` or
   `None`), the value of `numpy.random.get_state()` sampled after the call SHALL equal the value
   sampled before the call.
4. WHEN the same `NIRNodeRecord` is compiled concurrently in two separate threads using the same
   seed, both threads SHALL produce arrays `w1` and `w2` satisfying
   `numpy.array_equal(w1, w2)`.

---

### Requirement 8: Integration — Non-Zero Activity in Downstream Simulation

**User Story:** As a neuromorphic engineer, I want a CNL network compiled with Xavier-initialised
weights to produce non-zero spike trains when simulated with standard Poisson input, so that I
can verify the zero-activity bug is resolved end-to-end.

#### Acceptance Criteria

1. WHEN a CNL program defining an `Input` of shape `(4,)`, a `Linear` node with weight shape
   `(4, 4)` and `weight_init equal to "xavier"`, and a downstream `LIF` node is compiled by the
   Compiler and executed via the `snntorch_sim` simulation endpoint with Poisson-distributed
   input stimuli (`timesteps=100`, `firing_rate=0.3`, `seed=1`), THE simulation SHALL produce a
   `spikes` map for the `LIF` node containing at least one neuron-to-timestep entry.
2. WHEN the same CNL topology is compiled without any `weight_init` annotation (zero weights) and
   executed via the same `snntorch_sim` simulation endpoint with identical stimuli, THE simulation
   SHALL produce a `spikes` map for the `LIF` node that is empty.
3. WHEN Xavier-initialised weights are compiled for a rank-2 weight tensor of shape `(M, N)`,
   every weight value `w` in the compiled `NIRGraph` SHALL satisfy
   `-a <= w <= a` where `a = sqrt(6.0 / (M + N))`.

---

### Requirement 9: Correctness Properties for Weight Initialisation

**User Story:** As a developer, I want property-based tests to verify the mathematical invariants
of the initialiser, so that edge cases across arbitrary shapes are caught automatically.

#### Acceptance Criteria

1. WHEN Xavier initialisation is applied to any rank-2 shape `(M, N)` with `1 <= M, N <= 512`,
   every element `w` of the produced array SHALL satisfy `-a <= w <= a` (inclusive) where
   `a = sqrt(6.0 / (M + N))`.
2. WHEN Kaiming initialisation is applied to any rank-2 shape `(M, N)` with `1 <= M, N <= 512`,
   every element `w` of the produced array SHALL satisfy `-a <= w <= a` (inclusive) where
   `a = sqrt(3.0 / N)`.
3. WHEN the same `NIRNodeRecord` is compiled twice sequentially in the same process with the
   same seed `s` (for every valid rank-2 shape `(M, N)` with `1 <= M, N <= 512`), THE Compiler
   SHALL produce arrays `w1` and `w2` satisfying `numpy.array_equal(w1, w2)`.
4. WHEN any valid weight shape is compiled with init method `"xavier"` or `"kaiming"`, THE
   returned array SHALL have `dtype` equal to `float64`.
5. WHEN any valid weight shape is compiled with init method `"xavier"` or `"kaiming"`, the
   value of `numpy.random.get_state()` (both the name string and the state array) sampled
   after the call SHALL equal the value sampled before the call.
