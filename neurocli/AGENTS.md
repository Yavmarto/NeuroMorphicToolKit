# neurocli

Read first:
- `../CODING_STYLE_GUIDE.md`
- `README.md`
- `docs/ADR-claude/0001-scaffolding-first-cli.md`
- `docs/ADR-claude/0002-template-bundle-architecture.md`
- `docs/ADR-claude/0003-module-lifecycle-commands.md`
- `docs/ADR-claude/0004-headless-ci-integration.md`
- `../nmtk/neuro_toolkit/assets/modules.json`

## Verification

```bash
cd neurocli
make verify
```

This runs: `pip install -e ".[dev]"` → `ruff check` → `mypy` → `pytest tests/ -q`

All four must be clean before merging.

## Package layout

```
neurocli/
  neurocli/
    __init__.py
    cli.py          # Typer root app — registers all commands
    output.py       # print_result / error_exit helpers
    manifest.py     # load_manifest / find_module — reads modules.json
    renderer.py     # render_template — Jinja2 template materialiser
    new.py          # neuro new command
    lifecycle.py    # neuro status / install / run commands
    hub.py          # neuro hub sub-commands (login/push/pull/search)
    templates/      # template bundles (package data)
      nir_snntorch/
      nir_lava_sim/
      neurocnl_pynq/
      akida_brainchip/
      neurocnl_neurosim/
  tests/
    test_cli.py
    test_manifest.py
    test_renderer.py
    test_new.py
    test_lifecycle.py
    test_hub.py
    test_integration.py
```

## Constraints

- Module IDs, ports, install paths, and uvicorn targets MUST come from
  `nmtk/neuro_toolkit/assets/modules.json` exclusively. Never hardcode them.
- Template `.jinja` files use `jinja2.StrictUndefined` — missing variables
  raise loudly at render time.
- All `subprocess.run` calls use list-form args (`shell=False`).
- Optional hardware SDKs (Lava, PYNQ, Akida) MUST NOT be imported at module
  level — guard with `try/except ImportError`.
- Exit codes: 0 = success, 1 = user/input error, 2 = runtime/system error.
- `--json` flag must work on every command including error paths.
- The `neuro hub` sub-commands implement the CLI surface defined in
  `.kiro/specs/neurohub-global-registry/design.md`.

## Do NOT

- Add docs that imply a different shipped command exists.
- Introduce command behavior that diverges from the launcher's module naming
  or lifecycle model.
- Scatter template files across arbitrary directories.
- Invent a second module manifest or module registry.
