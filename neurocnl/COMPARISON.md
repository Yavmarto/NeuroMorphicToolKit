# Implementation Comparison: v-jules vs v-copilot

## Executive Summary

**v-copilot is the stronger implementation** and serves as the base for the merged
version at `neurocnl/`.  v-jules contributed defensive parameter handling and
broader CNL grammar coverage, both of which are folded into the merge.

---

## 1. CNL Parser (`cnl_parser.py`)

| Aspect | v-jules | v-copilot | Merged |
|--------|---------|-----------|--------|
| Approach | Loose `(.*?)` regex | Strict named-group patterns | Strict patterns, wider article/subject support |
| Function name | `parse_cnl()` | `parse()` | `parse()` |
| Return keys | concept, subject, condition, action, raw | + verb, negated | + verb, negated |
| Article support | Any text (too loose) | Only "The" | "The" or "A" |
| Subject support | Any text | "sensory neuron" / "motor neuron" only | + generic "neuron" |
| Concept names | Space-separated ("threshold firing") | Underscore-separated ("threshold_firing") | Underscore-separated |

### Verdict
v-copilot's pattern-based parser is safer and more maintainable.  v-jules's
`(.*?)` wildcard accepts invalid sentences, which defeats the purpose of a
*controlled* natural language.  The merged parser adds `"A"` article support
and generic `"neuron"` subjects while keeping v-copilot's strict validation.

---

## 2. Layer 1 Invariants (`layer1_invariants.py`)

| Aspect | v-jules | v-copilot | Merged |
|--------|---------|-----------|--------|
| Functions | 5 (`check_*`) | 5 (descriptive names) | 5 (v-copilot names) |
| Parameter access | `.get()` with defaults | Direct `[]` access | `.get()` with defaults (from v-jules) |
| Decay check | Trivial (`tau > 0`) | Full dv/dt dynamics | Full dv/dt dynamics |
| Registry | None | `ALL_INVARIANTS` dict | `ALL_INVARIANTS` dict |
| Documentation | Minimal | Detailed with NeuroML refs | Detailed with NeuroML refs |

### Verdict
v-copilot's `membrane_potential_decays_toward_rest()` is significantly more
sophisticated and biologically meaningful.  v-jules's defensive `.get()` pattern
is incorporated to avoid `KeyError` on incomplete parameter dicts.

---

## 3. Nengo Generator (`nengo_generator.py`)

| Aspect | v-jules | v-copilot | Merged |
|--------|---------|-----------|--------|
| Threshold mapping | `max_rates` only (incorrect) | `intercepts` (correct) | `intercepts` |
| Parameter extraction | Hard-coded | Spec-driven via `extract_numeric()` | Spec-driven |
| Probes | None | `motor_probe` | `motor_probe` |
| Attribute names | `sensory_ensemble`, `motor_ensemble` | `sensory`, `motor` | `sensory`, `motor` |

### Verdict
v-copilot correctly maps thresholds to Nengo `intercepts`, which is the proper
mechanism for controlling firing thresholds in Nengo's LIF model.  v-jules's
approach using only `max_rates` does not achieve threshold control.

---

## 4. Assertion Generator (`assertion_generator.py`)

| Aspect | v-jules | v-copilot | Merged |
|--------|---------|-----------|--------|
| Generation mode | Template-only | Template + LLM (Anthropic) | Template + LLM |
| Test dependencies | Requires simulation data fixture | Self-contained Nengo tests | Self-contained |
| Assertion quality | Weak (e.g., `v >= 0.5` for threshold) | Proper Nengo simulation | Proper Nengo simulation |
| Syntax check | ✓ | ✓ | ✓ |

### Verdict
v-copilot's assertions are dramatically better — each test creates its own
Nengo network and actually validates behavior rather than checking raw data
with lenient thresholds.

---

## 5. Simulation Runner (`run_simulation.py`)

| Aspect | v-jules | v-copilot | Merged |
|--------|---------|-----------|--------|
| Architecture | Monolithic (209 lines) | Modular (`load_spec`, `run_pipeline`, `main`) | Modular |
| Test execution | In-process pytest + file mutation | Subprocess + temp directory | Subprocess + temp dir |
| Error handling | `sys.exit(1)` | Error dict in report | Error dict in report |
| MuJoCo | Hard-coded XML, no termination | Simpler XML, early termination | Early termination |
| Timing | Not measured | Wall-clock timing | Wall-clock timing |

### Verdict
v-copilot's modular design is easier to test and debug.  The subprocess-based
test execution avoids in-process contamination that v-jules suffers from.

---

## 6. Test Coverage

| Module | v-jules tests | v-copilot tests |
|--------|--------------|-----------------|
| CNL Parser | 4 tests (47 lines) | ~47 tests (274 lines) |
| Layer 1 Invariants | 5 tests (27 lines) | 21 tests (125 lines) |
| Layer 1 Validator | 3 tests (44 lines) | 6 tests (118 lines) |
| Nengo Generator | 6 tests (59 lines) | 9 tests (115 lines) |
| Utilities | — | 8 tests (37 lines) |
| **Total** | **~18 tests** | **~91 tests** |

v-copilot has **~5× more test coverage** including edge cases, error paths,
and boundary conditions.

---

## 7. Infrastructure

| Aspect | v-jules | v-copilot | Merged |
|--------|---------|-----------|--------|
| `__init__.py` | Missing | ✓ | ✓ |
| `conftest.py` | Missing | ✓ | ✓ |
| `pyproject.toml` | Missing | ✓ | ✓ |
| `utils.py` | Missing | ✓ | ✓ |
| Path management | `sys.path.append()` | `sys.path.insert(0, ...)` with dedup | insert + dedup |

---

## 8. Spec File Correctness

### v-copilot `reflex_arc.cnl`
```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0
```
✅ Correct — uses concrete numeric values, matches the parser patterns exactly.

### v-jules `reflex_arc.cnl`
```
A neuron MUST emit a spike IF membrane potential exceeds threshold.
A neuron MUST NOT accept input DURING the refractory period.
Membrane potential MUST decay exponentially WITH time constant tau.
A sensory neuron MUST excite the motor neuron WITH a synaptic weight of W.
```
⚠️ Issues:
- Uses abstract variable names (`threshold`, `tau`, `W`) instead of numeric values
- "A neuron" is generic — parser can't determine sensory vs motor
- `"emit a spike IF"` uses `IF` instead of `ONLY IF`
- Missing numeric values means parameters can't be extracted from the spec

### Grammar spec (`cnl_grammar.md`)
Both grammar files define the same 6 verbs (MUST, MUST NOT, ONLY IF, DURING,
AFTER, WITH) and 4 concepts.  v-copilot's grammar is more detailed with
explicit Nengo mapping code examples.  Neither grammar explicitly states
whether articles ("The" / "A") are required.

**Recommendation**: The merged grammar clarifies that both "The" and "A" are
accepted articles, and that numeric values are preferred over symbolic names.

---

## 9. Should We Merge?

**Yes.**  The merged implementation at `neurocnl/` combines:

1. **v-copilot's architecture** — modular, well-tested, proper Python packaging
2. **v-copilot's Nengo mapping** — correct intercepts-based threshold control
3. **v-copilot's test suite** — 5× more coverage
4. **v-jules's defensive parameter handling** — `.get()` with defaults
5. **v-jules's broader grammar** — "A" article, generic "neuron" subject
6. **Fixed spec files** — numeric values with expanded parser patterns

The merged version is strictly better than either individual implementation.
