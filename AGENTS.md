# NeuroMorphicToolKit Agent Router

This checkout contains the suite control plane plus the individual product modules. Default to one writable top-level module per task; if a change crosses a contract boundary, read both modules' `AGENTS.md` files and both sides' spec or ADR docs before writing.

Read before edit:
- Before writing code anywhere in this repo, read `CODING_STYLE_GUIDE.md`.
- If editing `neurocnl/**`, read `neurocnl/AGENTS.md`.
- If editing `Neurosim/**`, read `Neurosim/AGENTS.md`.
- If editing `Neurochip/**`, read `Neurochip/AGENTS.md`.
- If editing `Neurobench/**`, read `Neurobench/AGENTS.md`.
- If editing `Neuro-Dream-Hand/**`, read `Neuro-Dream-Hand/AGENTS.md`.
- If editing `Neurosense/**`, read `Neurosense/AGENTS.md`.
- If editing `Neurohub/**`, read `Neurohub/AGENTS.md`.
- If editing `nmtk/**`, read `nmtk/AGENTS.md`.
- If editing `nmtk_ui_core/**`, read `nmtk_ui_core/AGENTS.md`.
- If editing `neurocli/**`, read `neurocli/AGENTS.md`.
- If editing root-owned `docs/**`, `scripts/**`, `tests/**`, `monitoring/**`, or root config files, stay in the root repo and read the owning module `AGENTS.md` for every contract you touch.
- If editing more than one top-level module, name the write set explicitly and run the owning checks plus `python3 -m pytest tests/integration/test_cross_module.py` and `python3 -m pytest tests/integration/test_teensy_e2e.py`.
