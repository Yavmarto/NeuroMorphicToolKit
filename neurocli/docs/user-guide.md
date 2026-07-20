# neurocli User Guide

`neurocli` is the terminal front door to the NMTK suite. Install it once and use `neuro` to scaffold projects, manage module backends, and interact with the Neurohub registry — no desktop app required.

---

## Installation

```bash
cd neurocli
pip install -e ".[dev]"
```

Verify:

```bash
neuro --help
```

---

## Commands

### `neuro new` — scaffold a project

Creates a new project directory from a template bundle.

```bash
neuro new <name> --framework <fw> --target <target> [--task <task>] [--output-dir <dir>] [--json]
```

**Supported framework + target combinations:**

| Framework  | Target      | What you get                                  |
|------------|-------------|-----------------------------------------------|
| `nir`      | `snntorch`  | NIR graph + fixed-weight snnTorch simulation  |
| `nir`      | `lava_sim`  | NIR graph + Lava simulator (optional install) |
| `neurocnl` | `pynq`      | NeuroCNL spec + PYNQ-Z2 deployment scaffold   |
| `akida`    | `brainchip` | Akida/MetaTF scaffold (Linux SDK required)    |
| `neurocnl` | `neurosim`  | NeuroCNL spec + NeuroSim canvas simulation    |

**Examples:**

```bash
# Scaffold a keyword-spotting project using NIR + snnTorch
neuro new my_kws_proj --framework nir --target snntorch --task kws

# Same, output into a specific directory
neuro new my_proj --framework nir --target lava_sim --output-dir ~/projects

# Machine-readable output (for CI)
neuro new ci_proj --framework neurocnl --target neurosim --json
```

After scaffolding:

```bash
cd my_kws_proj
uv sync
bash scripts/run.sh
```

---

### `neuro status` — check module health

Polls the health endpoint of every NMTK module and reports their status.

```bash
neuro status [--json]
```

**Output (human):**

```
Module               Status         Port     Latency
----------------------------------------------------------
NeuroStudio          unreachable    9000     -
NeuroChip            no-port        -        -
Bench                unreachable    9000     -
```

**Output (JSON):**

```json
{
  "modules": [
    {"id": "neurocnl", "name": "NeuroStudio", "status": "healthy", "port": 9000, "latency_ms": 12.3},
    {"id": "neuro_dream_hand", "name": "NDH Simulator", "status": "no-port", "port": null, "latency_ms": null}
  ]
}
```

Status values: `healthy`, `unreachable`, `unhealthy`, `no-port`.

---

### `neuro install` — install a module

Installs a module's Python package via `uv` (or `pip` if uv is not available).

```bash
neuro install <module_id> [--extras <extra1,extra2>] [--json]
```

Module IDs come from `nmtk/neuro_toolkit/assets/modules.json`:
`neurocnl`, `Neurochip`, `Neurobench`, `Neurosense`, `Neurohub`, `lava_backend` (see `Neuro-Dream-Hand/` as a reference example, not a launcher module)

**Examples:**

```bash
# Install NeuroCNL
neuro install neurocnl

# Install NeuroCNL with training and lava extras
neuro install neurocnl --extras training,lava

# Install Neurohub
neuro install Neurohub
```

---

### `neuro run` — start a module backend

Starts a module's uvicorn backend on its configured port.

```bash
neuro run <module_id> [--port <port>] [--json]
```

**Examples:**

```bash
# Start NeuroCNL backend on port 9000
neuro run neurocnl

# Start Neurobench on a custom port
neuro run Neurobench --port 9100
```

Modules with no uvicorn target (e.g. `neuro_dream_hand`, which is CLI-only) will exit with a clear error rather than silently doing nothing.

---

### `neuro hub` — Neurohub registry

Interact with a Neurohub registry to share and discover neuromorphic artefacts (models, datasets, benchmark baselines).

#### `neuro hub login`

Store credentials for a registry.

```bash
neuro hub login [--registry <url>] [--token <token>] [--json]
```

Registry URL resolution order:
1. `--registry` flag
2. `NEUROHUB_REGISTRY` environment variable
3. Previously stored `~/.config/neurocli/hub.json`
4. `http://localhost:8005` (default)

Token resolution order:
1. `--token` flag
2. `NEUROHUB_TOKEN` environment variable
3. Interactive prompt (skipped in `--json` mode — exits with error instead)

**Examples:**

```bash
# Login to a local registry
neuro hub login --registry http://localhost:8005 --token mytoken

# Login using environment variables (useful in CI)
NEUROHUB_REGISTRY=https://hub.example.com NEUROHUB_TOKEN=secret neuro hub login --json
```

Credentials are written to `~/.config/neurocli/hub.json` with permissions `0600`.

---

#### `neuro hub push`

Upload an artefact file to the registry.

```bash
neuro hub push <artefact_path> [--registry <url>] [--json]
```

**Example:**

```bash
neuro hub push ./my_model.nir
neuro hub push ./my_model.nir --registry https://hub.example.com --json
```

Requires `neuro hub login` first. Exits with a clear `not_logged_in` error otherwise.

---

#### `neuro hub pull`

Download an artefact by its `neurohub://` URI.

```bash
neuro hub pull <neurohub_uri> [--json]
```

**Example:**

```bash
neuro hub pull neurohub://my_org/lif_model@1.0
```

> Pull is currently a stub — full download implementation follows the neurohub-global-registry spec.

---

#### `neuro hub search`

Search artefacts in the registry.

```bash
neuro hub search <query> [--registry <url>] [--json]
```

**Examples:**

```bash
neuro hub search "lif neuron"
neuro hub search "braille dataset" --json
```

---

### `neuro studio run` — generate and run a NeuroStudio notebook

Reads a NeuroStudio workspace file (`*.nmtk`, saved from the
NeuroStudio GUI's File > Save), generates a Jupyter notebook from its CNL spec via
the `neurocnl` backend, runs it, and streams live training progress until it
finishes.

```bash
neuro studio run <workspace_file> [--epochs N] [--learning-rate F] [--optimizer NAME]
                  [--batch-size N] [--framework NAME] [--dataset NAME]
                  [--registry <url>] [--json]
```

The workspace file only stores the CNL spec (and canvas layout) — it does not store
training parameters. `--epochs`/`--learning-rate`/`--optimizer`/`--batch-size`
default to the same values the GUI's Pipeline tab defaults to (50, 1e-3, Adam, 32),
so an unmodified workspace file behaves the same from the CLI as it would freshly
opened in the GUI. `--framework`/`--dataset` default to the workspace file's
`selectedPlatforms[0]`/`selectedDataset`.

Requires the `neurocnl` backend running first (`neuro run neurocnl`); the registry
URL resolves from `--registry`, then the `neurocnl` port in
`nmtk/neuro_toolkit/assets/modules.json`, then `http://localhost:9000`.

**Examples:**

```bash
neuro studio run my-project.nmtk
neuro studio run my-project.nmtk --framework lava_sim --epochs 100 --json
```

---

## Global flags

All commands support:

| Flag     | Description                          |
|----------|--------------------------------------|
| `--json` | Emit machine-readable JSON output    |
| `--help` | Show help for any command or sub-command |

---

## Exit codes

| Code | Meaning                                      |
|------|----------------------------------------------|
| `0`  | Success                                      |
| `1`  | User / input error (bad args, not logged in) |
| `2`  | Runtime / system error (install failed, registry unreachable) |

---

## Environment variables

| Variable             | Used by              | Description                          |
|----------------------|----------------------|--------------------------------------|
| `NMTK_ROOT`          | All commands         | Override path to repository root (for locating `modules.json`) |
| `NEUROHUB_REGISTRY`  | `neuro hub` commands | Default registry URL                 |
| `NEUROHUB_TOKEN`     | `neuro hub login`    | Token passed without interactive prompt |

---

## Quick reference

```bash
neuro new my_proj --framework nir --target snntorch --task kws
neuro status
neuro install neurocnl
neuro run neurocnl
neuro hub login --registry http://localhost:8005 --token <token>
neuro hub search "lif neuron" --json
neuro hub push ./model.nir
neuro hub pull neurohub://org/model@1.0
```
