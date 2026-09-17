# neurocnl Release Checklist

Use this checklist before cutting any release. Core gates must pass. Optional hardware extras
are best-effort — document their status but do not block the release if they fail.

---

## Before any release

- [ ] `pyproject.toml` `[project].version` matches the intended tag (e.g. `0.6.0`)
- [ ] `neurocnl/__init__.py` `__version__` matches `pyproject.toml`
  - Automated by `version_variables` in `[tool.semantic_release]` for future releases
- [ ] `CHANGELOG.md` has an entry for the version being released
- [ ] Classifier in `pyproject.toml` reflects actual maturity (`4 - Beta` for pre-beta and above)
- [ ] Python version classifiers match the CI matrix (currently 3.11, 3.12)

---

## Core support (required — block release if any fail)

- [ ] `pytest neurocnl/ -v --cov=neurocnl --cov-fail-under=70` passes on Python 3.11 and 3.12
- [ ] `NEUROCNL_RUN_INSTALL_SMOKE=1 pytest tests/test_install_smoke.py -v` passes
  (covers: core import, `__version__`, public API, CLI entry point, viz gating, `[viz]` extra, `[loihi]` extra)
- [ ] `ruff check neurocnl/` exits 0
- [ ] `mypy` core packages exit 0 (cnl, ir, backends, layers, generation, pipeline, planner)
- [ ] `pip install .` in a fresh venv, then `python -c "import neurocnl; print(neurocnl.__version__)"` prints the release tag
- [ ] CLI entry point works: `neurocnl --help` (after `pip install .`)

---

## Optional hardware extras (best-effort — document status, do not block release)

| Extra | Smoke command | Status |
|-------|---------------|--------|
| `[loihi]` | `pip install ".[loihi]" && python -c "import nengo_loihi"` | covered by install-smoke CI |
| `[viz]` | `pip install ".[viz]" && python -c "from neurocnl.visualization import spike_raster"` | covered by install-smoke CI |
| `[neuroml]` / `[export]` | `pip install ".[neuroml]" && python -c "import lxml"` | manual |
| `[lava]` | `pip install ".[lava]" && python -c "import lava"` | manual; no hardware required |
| `[spinnaker]` | `pip install ".[spinnaker]" && python -c "import pyNN"` | manual; no hardware required |
| `[spinnaker2]` | `pip install ".[spinnaker2]"` | requires network + GitLab access; manual only |
| `[rockpool]` | `pip install ".[rockpool]" && python -c "import rockpool"` | manual |
| `[synsense]` | `pip install ".[synsense]" && python -c "import sinabs"` | manual; ~1 GB (torch) |
| `neurodreamhand` | not a pyproject.toml extra; install separately | verify `DreamHandNotAvailableError` is raised cleanly when absent |

---

## Release mechanics

- [ ] Confirm the branch being tagged is `dev`
- [ ] Run `release-promote.yml` with `dry_run=true` — verify `dev → main` merge is clean
- [ ] Run `release-promote.yml` with `dry_run=false` — promote and push tag to `main`
- [ ] Verify the release tag appears on GitHub

---

## Post-release

- [ ] PyPI publish (if applicable): `python -m build && twine upload dist/*`
- [ ] Verify `pip install neurocnl==<version>` resolves correctly
- [ ] Reset `CHANGELOG.md` — add an empty `## [Unreleased]` section at the top for the next cycle
