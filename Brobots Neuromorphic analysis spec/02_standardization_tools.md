# Standardization Tools
> Addresses the gap: every framework and hardware target speaks a different language

---

## 1. Model Converter

**Description**
Translate SNN model definitions between the major frameworks without manually rewriting network code.

**Target surfaces:** Desktop app + Python library

**Tags:** `NIR` `Lava` `PyNN` `Nengo` `Brian2`

### Spec
- Uses NIR as the intermediate pivot format — import from any supported framework, export to any other
- Preserves neuron parameters, connectivity, and time constants; flags unsupported primitives with warnings
- Validation step: runs a quick spike-count sanity check on a test input after conversion
- **Desktop:** drag-and-drop file → choose target framework → download converted file
- **Python:** `convert(model, source="lava", target="brian2")`

---

## 2. NIR Inspector

**Description**
Open, visualize, and edit NIR files — the emerging standard intermediate representation for neuromorphic models.

**Target surfaces:** Desktop app

**Tags:** `NIR` `graph` `inspection`

### Spec
- Renders the NIR computational graph as an interactive node-link diagram
- Click any node to inspect neuron type, parameters, and connections
- Edit parameter values inline and re-export as a valid NIR file
- Shows a diff view when comparing two NIR files (e.g. before vs. after conversion)
- Validates against the NIR schema and displays errors with line references

---

## 3. Hardware Target Mapper

**Description**
Analyse a model and report which hardware backends it is compatible with, and what changes are needed to run on each.

**Target surfaces:** Desktop app + Python library

**Tags:** `compatibility` `mapping` `constraints`

### Spec
- Input: a model in any supported format
- Output: a compatibility matrix — green (runs as-is), amber (needs minor changes), red (unsupported)
- For amber/red items, provides a plain-English explanation and a suggested fix
- Covers: Loihi 2, SpiNNaker 2, BrainScaleS 2, Xylo (SynSense), and simulation-only targets
- **Desktop:** visual compatibility card per hardware target
- **Python:** returns a structured dict with compatibility status and recommended changes per target
