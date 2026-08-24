# neurocli

`neurocli` is the scriptable developer front door to NMTK. The proof of concept
ships one verified project scaffold, manages the consolidated backend through
the repository's Compose stack, runs Studio workspaces, talks to Neurohub, and
builds validated offline PYNQ packages.

## Install and verify

```bash
cd neurocli
python -m pip install -e ".[dev]"
make verify
```

The installed command is `neuro`.

## Verified workflow

```bash
neuro new demo --trainer snntorch --data static
cd demo
uv sync
uv run python src/train.py
neuro deploy network.cnl --trained-nir artifacts/trained.nir --hardware pynq --output pynq.zip
```

The generated project trains a deterministic two-class snnTorch model and
writes non-zero weights to `artifacts/trained.nir`. Deployment calls Suite API
for target validation and package generation; it never programs hardware.

The other template bundles remain available for exploration with
`--experimental`, but they are not part of the PoC acceptance contract.

## Backend and integrations

- `neuro install` builds `suite_api`, `launcher-control`, and `jupyter-server`
  from the canonical root Compose file.
- `neuro run` starts those services and waits for Suite API health.
- `neuro status` reads `/api/suite/health` and `/api/suite/health/modules`.
- `neuro studio run FILE.nmtk` generates, runs, and follows a Studio notebook.
- `neuro hub login|push|pull|search` uses Neurohub's `/api/v1` registry.

Set `NMTK_ROOT` when the CLI cannot locate this checkout,
`NMTK_SUITE_API_URL` when Suite API is not at `http://127.0.0.1:9000`, and
`NEUROHUB_REGISTRY`/`NEUROHUB_TOKEN` for non-interactive registry access.

All commands expose `--json`; exit code `1` means invalid input or a rejected
operation, while `2` means a runtime or infrastructure failure.

Full command reference: [`docs/user-guide.md`](docs/user-guide.md).
