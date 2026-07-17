# Current Task: Align NeuroCNL Sentence Picker & Autocomplete with NIR-Native Compiler

## Verified Implementation Status (2026-07-04)

**Status: NOT STARTED — doc's own "Identified Gap / Pending Refactoring" status is still accurate; no drift.**

- `neurocnl/frontend/lib/widgets/cnl_sentence_builder_dialog.dart:58` still contains the exact legacy template quoted in this doc: `'The ${v['neuron']} MUST fire ONLY IF membrane potential exceeds ${v['threshold']}'`, and `_kConcepts` still uses `defaultValue: 'sensory neuron'` / `'motor neuron'` throughout (lines 48, 69, 90, 111, 116, 158, 163, 189, 252, 273).
- `neurocnl/frontend/lib/widgets/cnl_editor.dart:182-227` `_kAllTemplates` is unchanged: still contains `MUST fire ONLY IF`, `MUST adapt WITH STDP learning rate`, `{sensory neuron}`/`{motor neuron}` templates.
- `neurocnl/neurocnl/nir_cnl/grammar_tables.py:479-489` `forbidden_biological_keywords` frozenset is unchanged — still `{"sensory", "motor", "MUST", "MUST NOT", "threshold_firing", "refractory_period", "STDP"}` — so the described `ParseError`/legacy-token rejection is still live and still triggered by the picker/autocomplete output.
- Neither Task 1 (rewrite `_kAllTemplates`) nor Task 2 (rewrite `_kConcepts`) from this doc's action plan has been applied.

**Missing:** everything in Section 4 (Task 1 and Task 2) — no NIR-native template/concept rewrite has started.

**Date:** May 22, 2026  
**Status:** Identified Gap / Pending Refactoring  
**Target Module:** `neurocnl/frontend` and `neurocnl/neurocnl`

---

## 1. Overview of the Alignment Gap
The **CNL Sentence Picker** (accessible via the **Add CNL Sentence** button in CNL Studio) and the **Editor Autocomplete suggestions** are currently out of sync with the new NIR-native CNL compiler.

While the new compiler has been completely overhauled to bypass Nengo and target `nir.NIRGraph` directly via explicit primitive and structural declarations, the frontend inputs still generate **legacy biological grammar** statements. This causes any sentence added via the picker or autocomplete to be immediately rejected by the parser's legacy-token safety gate.

---

## 2. Codebase Locations & Evidence

### A. The Outdated Frontend Inputs
The frontend guided inputs still reference old, Nengo-era biological concepts (such as `threshold_firing`, `refractory_period`, `STDP`, `sensory neuron`, and `motor neuron`):
*   **Guided Picker:** [cnl_sentence_builder_dialog.dart](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/cnl_sentence_builder_dialog.dart#L36-L272) defines the `_kConcepts` list containing old template constructs like:
    ```dart
    'The ${v['neuron']} MUST fire ONLY IF membrane potential exceeds ${v['threshold']}'
    ```
*   **Editor Autocomplete:** [cnl_editor.dart](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/cnl_editor.dart#L169-L220) contains `_kAllTemplates` loaded with legacy templates using keywords such as `MUST`, `MUST NOT`, `sensory neuron`, and `STDP`.

### B. The Compiler's Strict Denylist
The new NIR-native compiler's parser ([parser.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/nir_cnl/parser.py)) validates input against a list of forbidden keywords to avoid executing deprecated or unfaithful pipelines.

In [grammar_tables.py](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/neurocnl/nir_cnl/grammar_tables.py#L404-L428), the following keywords are blacklisted:
```python
forbidden_biological_keywords: frozenset[str] = frozenset(
    {
        "sensory",
        "motor",
        "MUST",
        "MUST NOT",
        "threshold_firing",
        "refractory_period",
        "STDP",
    }
)
```
Any sentence inserted from the current picker or autocompletes containing these words will trigger an immediate `ParseError` (e.g. `unsupported_sentence_family` or `legacy_token_detected`).

---

## 3. Reference: The New NIR-Native CNL Grammar
The new parser expects explicit, structural definitions that map directly to NIR primitives. For example, a minimal working script (such as [reflex_arc.cnl](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/backend/app/templates/reflex_arc.cnl)) must look like this:

```cnl
Define a network named reflex_arc.

# Node Declarations
Define an input port named input with shape (1,).
Define a leaky integrate-and-fire neuron named sensor with time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.
Define a linear transformation named w_sensor_actuator with weight matrix shape (1, 1) ...
Define an output port named output with shape (1,).

# Connectivity Declarations
input connects to sensor.
sensor connects to w_sensor_actuator.
w_sensor_actuator connects to actuator.
actuator connects to output.
```

---

## 4. Recommended Action Plan / Refactoring Tasks

To resolve this contract drift and restore the utility of the sentence picker, the following frontend updates are required:

### Task 1: Update Autocomplete Templates in `CnlEditor`
*   **File:** [cnl_editor.dart](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/cnl_editor.dart)
*   **Action:** Rewrite `_kAllTemplates` to suggest valid NIR-native declarations, such as:
    *   `Define an input port named {input} with shape ({1,}).`
    *   `Define a leaky integrate-and-fire neuron named {sensor} with time constant {0.02}, resistance {1.0}, leak voltage {0.0}, and firing threshold {1.0}.`
    *   `Define a linear transformation named {w_trans} with weight matrix shape ({1, 1}) and weight matrix values ({1.0,}).`
    *   `Define a leaky integrator neuron named {li} with time constant {0.02}, resistance {1.0}, and leak voltage {0.0}.`
    *   `Define an output port named {output} with shape ({1,}).`
    *   `{source} connects to {target}.`

### Task 2: Align `CnlSentenceBuilderDialog` Concepts
*   **File:** [cnl_sentence_builder_dialog.dart](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/frontend/lib/widgets/cnl_sentence_builder_dialog.dart)
*   **Action:** Update `_kConcepts` list to represent NIR primitives instead of biological concepts:
    1.  **Input/Output Ports:** Inputs for shape declaration.
    2.  **LIF Neuron:** Builder fields for time constant, resistance, leak, and threshold.
    3.  **LI Neuron:** Builder fields for time constant, resistance, and leak.
    4.  **Linear Transformation:** Builder fields for source, target, shape, and weights.
    5.  **Connections:** Simplifies mapping of `{source} connects to {target}.`

---

> [!IMPORTANT]
> A detailed breakdown of this direct-lower compilation model and the remaining legacy cleanup roadmap can be reviewed in [CODE_REVIEW_CRITICAL_2026-05-14.md](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/neurocnl/docs/CODE_REVIEW_CRITICAL_2026-05-14.md).
