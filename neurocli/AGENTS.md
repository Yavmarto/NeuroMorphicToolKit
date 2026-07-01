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

<directory_structure>
├── AGENTS.md
├── LICENSE
├── Makefile
├── README.md
├── docs
│   ├── ADR-Gemini
│   │   └── 0001-initial-architecture.md
│   ├── ADR-claude
│   │   ├── 0001-scaffolding-first-cli.md
│   │   ├── 0002-template-bundle-architecture.md
│   │   ├── 0003-module-lifecycle-commands.md
│   │   └── 0004-headless-ci-integration.md
│   └── user-guide.md
├── issues-archive
│   ├── 01-cli-contracts-for-shell-actions.md
│   └── 22mar1_project_scaffolder.md
├── issues-future
│   ├── 001-poc-bootstrap-cli-package-and-entrypoint.md
│   ├── 002-poc-implement-project-scaffolder-command.md
│   ├── 003-poc-add-template-catalog-and-generated-project-smoke-tests.md
│   ├── 01-f811-redefined-names.md
│   ├── 02-plw0602-global-state.md
│   ├── 03-arg001-unused-router-args.md
│   ├── 04-g004-try401-logging.md
│   ├── 05-pt011-pytest-raises-match.md
│   ├── 06-pth-pathlib-modernization.md
│   ├── 07-sim117-nested-with.md
│   ├── 08-plc0206-era001-dict-and-deadcode.md
│   ├── 09-npy002-numpy-random.md
│   ├── 10-ann-type-hints.md
│   ├── 11-d417-docstring-args.md
│   ├── 12-plc0415-inline-imports.md
│   ├── 13-plr2004-magic-numbers.md
│   └── 14-plr0915-oversized-functions.md
├── neurocli
│   ├── __init__.py
│   ├── cli.py
│   ├── deploy.py
│   ├── hub.py
│   ├── lifecycle.py
│   ├── manifest.py
│   ├── new.py
│   ├── output.py
│   ├── renderer.py
│   ├── templates
│   │   ├── akida_brainchip
│   │   │   ├── README.md.jinja
│   │   │   ├── pyproject.toml.jinja
│   │   │   ├── scripts
│   │   │   │   └── run.sh
│   │   │   └── src
│   │   │       └── main.py.jinja
│   │   ├── neurocnl_neurosim
│   │   │   ├── README.md.jinja
│   │   │   ├── pyproject.toml.jinja
│   │   │   ├── scripts
│   │   │   │   └── run.sh
│   │   │   └── src
│   │   │       └── main.py.jinja
│   │   ├── neurocnl_pynq
│   │   │   ├── README.md.jinja
│   │   │   ├── pyproject.toml.jinja
│   │   │   ├── scripts
│   │   │   │   └── run.sh
│   │   │   └── src
│   │   │       └── main.py.jinja
│   │   ├── nir_lava_sim
│   │   │   ├── README.md.jinja
│   │   │   ├── pyproject.toml.jinja
│   │   │   ├── scripts
│   │   │   │   └── run.sh
│   │   │   └── src
│   │   │       └── main.py.jinja
│   │   ├── nir_sc_neurocore
│   │   │   ├── README.md.jinja
│   │   │   ├── pyproject.toml.jinja
│   │   │   ├── scripts
│   │   │   │   └── run.sh
│   │   │   └── src
│   │   │       └── main.py.jinja
│   │   └── nir_snntorch
│   │       ├── README.md.jinja
│   │       ├── pyproject.toml.jinja
│   │       ├── scripts
│   │       │   └── run.sh
│   │       └── src
│   │           └── train.py.jinja
│   └── uri_parser.py
├── pyproject.toml
├── tests
│   ├── __init__.py
│   ├── properties
│   │   ├── __init__.py
│   │   └── test_uri_properties.py
│   ├── test_cli.py
│   ├── test_hub.py
│   ├── test_integration.py
│   ├── test_lifecycle.py
│   ├── test_manifest.py
│   ├── test_new.py
│   └── test_renderer.py
└── uv.lock
</directory_structure>

## Remote Testing Configuration

For dev, `REMOTE_HOST=moosebuntu@192.168.2.51` can be used. For example, when the agent wants to test run the app, you can use `192.168.2.51` as the server address.
