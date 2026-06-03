# NeuroMorphicToolKit Agent Router

This checkout contains the suite control plane plus the individual product modules. Default to one writable top-level module per task; if a change crosses a contract boundary, read both modules' `AGENTS.md` files and both sides' spec or ADR docs before writing.

## End-User Convenience — Top Priority

**End-user convenience is the highest product priority in this codebase.**

When multiple valid solutions exist, always choose the one that requires the least action from the end user. Concretely:
- Prefer auto-detection and auto-configuration over requiring the user to set anything up manually.
- Prefer sensible defaults that work out of the box over options that require the user to know internal port numbers, service names, or deployment details.
- When a service can be discovered automatically, do so — never require the user to type in a URL or port they shouldn't need to know.
- Prefer changes to config files (docker-compose, modules.json, server defaults) over changes that require UI interaction or user knowledge.
- Error messages must be actionable: say what failed, why, and exactly what to do — never expose raw exception strings to the end user.
- When choosing between a simple UI action and a code fix that makes the action unnecessary, fix the code.

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

Knowledge Management (Open Brain):

- **Always check Open Brain** (Knowledge Items and Brain logs) at the start of a task to retrieve relevant context, architectural decisions (ADRs), and historical workstreams.
- **Update Open Brain** after completing a task if new durable knowledge, decisions, or important context were established. Use the `capture_thought` tool if available, or manually update Knowledge Items (KIs).
- Refer to `docs/archive/open-brain-import.md` for guidelines on how to organize and categorize knowledge for the Open Brain.

## Code Search

Use `semble search` to find code by describing what it does or naming a symbol/identifier, instead of grep:

```bash
semble search "authentication flow" ./my-project
semble search "save_pretrained" ./my-project
semble search "save model to disk" ./my-project --top-k 10
```

Use `semble find-related` to discover code similar to a known location (pass `file_path` and `line` from a prior search result):

```bash
semble find-related src/auth.py 42 ./my-project
```

`path` defaults to the current directory when omitted; git URLs are accepted.

If `semble` is not on `$PATH`, use `uvx --from "semble[mcp]" semble` in its place.

## Workflow

1. **Check Open Brain** for existing context and relevant Knowledge Items.
2. Start with `semble search` to find relevant chunks.
3. Inspect full files only when the returned chunk is not enough context.
4. Optionally use `semble find-related` with a promising result's `file_path` and `line` to discover related implementations.
5. Use grep only when you need exhaustive literal matches or quick confirmation of an exact string.
6. **Apply autofixers and run tests** for the language you are working in (e.g., `ruff check --fix .` and `ruff format .` for Python, `dart fix --apply` and `dart format .` for Dart) to ensure the codebase remains green before finishing a task.
7. **Update Open Brain** with any new durable knowledge or architectural changes upon task completion.
8. **End of Task Reporting**: When you finish a task, always report back to the user with the following:
   - State whether the front end or back end has to be restarted.
   - Describe exactly where the user can notice the changes.
   - Provide a summary of the issue and solution in no more than 3 sentences.
   - **Important Constraint**: The length of the "Summary of Issue and Solution" and the "Where to notice the changes" sections combined must be between half and 2/3 of the entire report. Keep these two sections highly concise.
