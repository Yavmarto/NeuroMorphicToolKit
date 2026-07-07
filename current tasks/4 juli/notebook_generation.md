# CNLStudio notebook generation run

**Date:** 4 July 2026
**Output:** `gen test/` at repo root (9 `.ipynb` files + `_weights.npz` artifacts + `MANIFEST.md`)
**Source docs:** `docs/current tasks/16 june/cnlstudio_notebook_analysis.md`, `..._extended.md`, `..._new_guides.md`

Generated the 9 CNLStudio notebooks confirmed buildable across the two prior analysis docs, using the backend's own `_build_v2_notebook()` codegen (`neurocnl/backend/app/routers/notebook.py`) called directly in Python — no manual UI clicking, no HTTP server. 5 of the 9 were built from the real trained `.nir` files already in `paper/**` (weights preserved exactly, embedded via `weights.npz`); the other 4 (`lif_norse`, `lif_rockpool`, `lif_nengo`, `lif_sinabs`) were hand-constructed `nir.NIRGraph` objects matching the simple `Linear→LIF` architecture from `paper/01_lif/lif_norse.ipynb`.

Environment note: the project's real `neurocnl/backend/Dockerfile` currently fails to build as-is — `backend/requirements.txt` pins a private, non-PyPI package (`neurodreamhand`), and `pyproject.toml` requires a `README.md` the Dockerfile never copies in. Worked around both in a throwaway image for this generation run only; did not modify the real Dockerfile/requirements.txt. Worth a real fix separately since this likely means the project's own Docker build is currently broken for anyone building it fresh.

**Real finding surfaced by this run:** `snntorch_apply.ipynb` classifies as `unsupported` on `snntorch_sim` (via `nir_support.classify_nir_graph`), not the 🟢 HIGH the companion doc claims — the real `cnn_sinabs.nir` file uses `nir.SumPool2d`, which is formally unsupported for that backend, not `AvgPool2d` as the doc's architecture diagram states. Full detail in `gen test/MANIFEST.md`.

See `gen test/MANIFEST.md` for the full per-notebook table (framework, support level, cell count, artifacts).
