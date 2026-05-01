# NeuroMorphicToolKit Agent Router

This checkout contains the suite control plane plus the individual product modules. Default to one writable top-level module per task; if a change crosses a contract boundary, read both modules' `AGENTS.md` files and both sides' spec or ADR docs before writing.

Read before edit:
- Before writing code anywhere in this repo, read `CODING_STYLE_GUIDE.md`.
- If editing `neurocnl/**`, read `neurocnl/AGENTS.md`.
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

Backend endpoint smoke testing:
- For backend endpoint work, use `docs/agents/nmtk-backend-smoke.md` and `python3 scripts/backend_endpoint_smoke.py` to probe `/health`, inspect `/openapi.json`, and call changed endpoints against the manifest-defined module ports.
- Treat `nmtk/neuro_toolkit/assets/modules.json` as the source of truth for module ids, ports, run paths, and uvicorn targets; do not maintain a separate static endpoint catalog.

Launcher and control-plane guardrails:
- For changes under `nmtk/**`, root launcher manifests such as `nmtk/neuro_toolkit/assets/modules.json`, `nmtk/neuro_toolkit/assets/remote_modules.json`, and root compose files, `scripts/**`, or root `tests/**` that affect launcher behavior, module lifecycle behavior, or suite-visible startup semantics, run `python3 scripts/launcher_control_service.py --doctor --json`.
- Use `bash scripts/run_launcher_guardrails.sh` as the canonical local enforcement wrapper for launcher and control-plane work. Use `bash scripts/run_launcher_guardrails.sh --with-integration` when the change alters module contracts or suite-visible startup behavior.
- Treat launcher doctor `fatalCount > 0` as a blocker unless the task is explicitly to diagnose or fix that failure.
- Launcher work is not complete until launcher doctor and launcher unit coverage pass.
- Report launcher doctor outcomes explicitly as either `preflight failed` or `degraded optional capability`; do not collapse both into a generic startup error.
- Keep launcher UI state changes, module manifest changes, and launcher verification updates in the same change when they describe the same behavior. If a launcher-visible state transition depends on manifest metadata, update both surfaces together.
- If `nmtk/neuro_toolkit/assets/modules.json` changes, update the launcher Dart models, launcher tests, and any consuming helper scripts in the same change.
- Do not introduce a new install or startup strategy without doctor or preflight coverage.
