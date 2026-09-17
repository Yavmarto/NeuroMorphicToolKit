# NeuroStudio (neurocnl)

> **Translating structured specifications into spiking neural hardware.**

[![CI](https://github.com/Yavmarto/neurocnl/actions/workflows/ci.yml/badge.svg)](https://github.com/Yavmarto/neurocnl/actions/workflows/ci.yml)

**NeuroStudio** is the authoring environment that bridges high-level network intent and neuromorphic execution. Using **Controlled Natural Language (CNL)**, you describe a spiking network in readable sentences, and the compiler turns that description into a verified NIR (Neuromorphic Intermediate Representation) graph that downstream modules can deploy.

---

## How it works

NeuroStudio uses a multi-layered verification approach:

1.  **Authoring:** Write NIR-native CNL — `Define a LIF neuron named detect with time constant shape (1,)...`
2.  **Validation:** The parser and validators check grammar, shapes, topology, and per-target support.
3.  **Compilation:** The engine compiles the spec directly to a `nir.NIRGraph` via the `CNL → IR → NIR` pipeline. No Nengo network is constructed on this path.
4.  **Handoff:** Validated NIR artifacts are passed to **Neurochip** for hardware deployment.

### A spec that compiles today

```python
from neurocnl import compile_to_nir, CompileError

spec = """
Define a network named reflex.
Define an input port named stimulus with shape (1,).
Define a LIF neuron named detect with time constant shape (1,), resistance shape (1,), leak voltage shape (1,), and firing threshold shape (1,).
Define a linear transformation named w_detect_drive with weight matrix shape (1, 1).
Define a LIF neuron named drive with time constant shape (1,), resistance shape (1,), leak voltage shape (1,), and firing threshold shape (1,).
Define an output port named response with shape (1,).

stimulus connects to detect.
detect connects to w_detect_drive.
w_detect_drive connects to drive.
drive connects to response.
"""

try:
    graph = compile_to_nir(spec)  # nodes: stimulus, detect, w_detect_drive, drive, response
except CompileError as exc:
    for d in exc.diagnostics:
        print(f"[{d.stage}] {d.code}: {d.message}")
```

> **Legacy grammar is rejected.** The older biological phrasing (`The sensory neuron MUST fire ONLY IF ...`) is no longer accepted: the validator raises `legacy_grammar` for `MUST`, `sensory`, `motor`, and the rest of the retired keyword set. Of the specs under `examples/`, only [`keyword_spotting.cnl`](examples/keyword_spotting.cnl) is currently NIR-native and round-trip valid; the remaining `.cnl` files are legacy and await migration.

---

## Where it runs

* **Backend:** in-process in `suite_api` at `/api/neurocnl` — roughly fifteen routers. The MuJoCo physics route is proxied to `neurocnl-physics-worker:8006`. The module-local backend serves the same routes at `/api`.
* **Surface:** NeuroStudio is the surface the NMTK app mounts by default. For how the app shell hosts it, see the [root README](../README.md#architecture).

## The Studio pipeline

NeuroStudio drives a fixed seven-step pipeline (`frontend/lib/models/studio_pipeline_steps.dart`):

* **Setup** — `selectData`
* **Design** — `defineModel` (the canvas), `defineTrain`, `defineEval`
* **Execute** — `run`, `deployHardware`, `deployReview`

Two other module names are surfaces of this same app rather than separate applications: **the canvas is what Neurosim means today**, and **`deployHardware` is what Neurochip means today** — it holds the Akida, PYNQ, Lava, and SC-NeuroCore workspaces under `frontend/lib/screens/studio/deploy/`. The **Neurohub** registry appears as a modal (`frontend/lib/screens/hub_popup.dart`). None of the three is a separate app, and the "handoff to NeuroSim" action re-enters this same surface with `moduleId: 'neurocnl'`.

---

## Technical details

### Support Semantics
Fidelity terms are used consistently across the project (canonical definitions live in the [Support Matrix](docs/support_matrix.md)):

- `faithful`: execution closely preserves the intended semantics.
- `approximate`: execution or export works, but relies on heuristics or backend-specific simplifications.
- `unsupported`: the project cannot honestly claim runtime or backend support yet.

A fourth term, `parser-recognized`, means the sentence family is accepted by the parser but says nothing about execution fidelity.

**Exportability is not deployability.** Producing an artifact (a Python script, C header, or ZIP overlay) means the file was generated — not that it was compiled, flashed, or run on real hardware. Every backend is currently rated `approximate` or narrower at the whole-target level; check the [Support Matrix](docs/support_matrix.md) for per-target status before relying on one.

### Installation
```bash
pip install .
```
```bash
pip install ".[dev]"
```

Optional extras exist per target (`loihi`, `lava`, `spinnaker`, `spinnaker2`, `synsense`, `rockpool`, `norse`, `akida` via `studio`, and others) — see `[project.optional-dependencies]` in `pyproject.toml`.

Note: `nengo` remains a required core dependency because the legacy exporters (`loihi_exporter`, `rockpool_exporter`, `neuroml_exporter`, `nengo_io`) still import it. It is not used by the `CNL → IR → NIR` compile path.

### Local Development
To run the desktop app, see the [root README](../README.md#nmtk-contributors-source-build) — the app shell is not built from this directory.

For module-local backend work:
```bash
uvicorn backend.app.main:app --reload --port 8000
```
Run it from this directory with the repo root on `PYTHONPATH` (the backend imports `nmtk_sdk` from there).

> The module `Makefile` targets are currently dead: line 1 includes a repo-root `common.mk` that no longer exists, which breaks every target in `neurocnl/`, `Neurobench/`, `Neurochip/`, `Neurosense/`, and `Neurosim/`.

For further reading:
- [API Reference](docs/api_reference.md)
- [User Happy Flow](docs/USER_HAPPY_FLOW.md)
- [Dataset cache (Firebase Storage)](docs/datasets.md)

---

## Documentation

- [ADR 0021: Studio-Neurochip Handoff Contract](../docs/ADR-claude/0021-studio-neurochip-handoff-contract.md)
- [Support Matrix](docs/support_matrix.md)
- [API Reference](docs/api_reference.md)

---

## License
GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later). See [LICENSE](LICENSE).
