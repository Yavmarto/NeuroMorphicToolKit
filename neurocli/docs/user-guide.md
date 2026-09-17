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

## Connecting to a running backend

`neuro backend` gives the CLI the same reach as the desktop app: every action
the app can perform against a running backend has a matching command.

The CLI reuses what the app already knows. `neuro backend targets` lists the
backends configured in the app, and every `neuro backend` command accepts
`--target ID` to pick one (it is optional when only one is configured).

Credentials are handled the way the app handles them, and nothing secret is
written to a file:

- Host, user, and port come from the app's own target list.
- If the target needs an SSH password, run `neuro login` once. It stores the
  password in the OS keychain (macOS Keychain, or `secret-tool` on Linux) and
  hands it to `ssh` through `SSH_ASKPASS`, never on a command line. SSH keys
  and a running agent work with no login step at all. `neuro logout` forgets it.
- The backend's administrator token is never stored. It is read live over the
  authenticated SSH connection, exactly as the app does.

Remote backends are reached over an SSH tunnel to loopback ports, matching the
app's policy that non-loopback traffic never leaves the tunnel.

```bash
neuro login --target remote-192-168-2-90   # once, saves to the keychain
neuro backend connect                      # confirm the session works
neuro backend modules list --json
neuro backend modules start neurocnl
neuro backend deployment watch JOB_ID      # live deployment progress
```

Command groups: `modules`, `launcher`, `workspace`, `deployment`, `akida`,
`pynq`, `suite`, and `jupyter`. Run `neuro backend GROUP --help` for the
actions in each. Anything not yet given a name is still reachable:

```bash
neuro backend api POST /api/neurochip/akida/inference --service suite --data '{...}'
```

In CI, set `NMTK_LAUNCHER_URL` and `NMTK_ADMIN_TOKEN` to skip target discovery
and the tunnel entirely.

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
