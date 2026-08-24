# neurocli User Guide

Install NeuroCLI from the checkout with `python -m pip install -e
"./neurocli[dev]"`. The `neuro` command is developer tooling; the desktop app
remains the supported end-user surface.

## Scaffold and train

`neuro new NAME --trainer snntorch --data static` creates the verified PoC
project. Project names may contain letters, numbers, underscores, and hyphens,
and rendering is atomic: a failed template never leaves a half-created project.

Run `uv sync` and `uv run python src/train.py` in the generated directory. A
successful run writes `artifacts/trained.nir`; `network.cnl` carries the matching
architecture required for target validation.

Legacy framework/target bundles require `--experimental`, for example `neuro
new lava-demo --framework nir --target lava_sim --experimental`.

## Backend lifecycle

- `neuro install [--json]` builds the core services from `docker-compose.yml`.
- `neuro run [--wait-timeout 240] [--api-url URL] [--json]` starts the core
  stack and returns only after Suite API is healthy.
- `neuro status [--api-url URL] [--json]` reports aggregated module health;
  degraded modules exit `1`, and an unreachable backend exits `2`.

The core services are `suite_api`, `launcher-control`, and `jupyter-server`.
Set `NMTK_ROOT` to select a checkout and `NMTK_SUITE_API_URL` to change the
default API URL.

## Offline PYNQ packaging

```bash
neuro deploy network.cnl \
  --trained-nir artifacts/trained.nir \
  --hardware pynq \
  --output pynq.zip
```

The command validates the CNL/NIR pair, requires confirmation that trained
weights were applied, and writes a handoff ZIP containing the CNL, NIR,
validated deploy request, and checksummed manifest. It reports
`hardware_programmed: false`; Akida and real device execution are outside the
PoC.

## Studio

`neuro studio run FILE.nmtk [--api-url URL]` reads the active canonical CNL
document, generates and starts its notebook, and follows training events until
completion. `--json` produces JSON Lines while events stream, followed by one
terminal result object.

## Neurohub

- `neuro hub login --registry URL --token TOKEN` stores credentials with mode
  `0600`; `NEUROHUB_TOKEN` is supported for CI.
- `neuro hub push FILE --type TYPE --slug SLUG --version X.Y.Z` uploads an
  artefact.
- `neuro hub pull neurohub://TYPE/OWNER/SLUG@VERSION` refuses downloads whose
  metadata lacks a valid SHA-256 or whose bytes do not match it.
- `neuro hub search QUERY` searches registry metadata.

Registry resolution is `--registry`, `NEUROHUB_REGISTRY`, stored configuration,
the launcher manifest, then local Suite API.

## Output contract

Every command supports machine-readable output. Exit code `0` is success, `1`
is an input or validation rejection, and `2` is an infrastructure failure.
