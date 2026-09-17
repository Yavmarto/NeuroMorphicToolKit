# NeuroMorphicToolkit (NMTK)

> **Unifying Neuromorphic Engineering, Neuroscience, and Software Development.**

NMTK is a cross platform app (macOS, Windows, Linux, Android, iOS) plus a backend suite. It lets you author a spiking neural network in controlled English, validate it, simulate it, and hand it off to neuromorphic hardware — without assembling SDK toolchains, Python environments, or Docker infrastructure yourself.

---

## The problem it solves

Neuromorphic computing is multidisciplinary, but its tooling is fragmented, SDK-specific, and assumes deep expertise at every layer. NMTK is built for people who want to work with SNNs and neuromorphic hardware without being experts in all of it: students and early-stage researchers, computational neuroscientists who know the biology but not the toolchains, ML engineers entering the field, and applied teams where one person maintains the hardware backend and everyone else connects to it remotely.

Download the app, install the backend in one step or connect to an existing one, and the suite is available.

---

## Getting Started

### 1. Download the app

Grab the latest NMTK desktop app from the [Releases page](https://github.com/Yavmarto/NeuroMorphicToolKit/releases) for macOS, Windows, or Linux.

### 2. Install the backend — or connect to one

On first launch the app walks you through a one-time backend setup:

| Option | When to use |
|--------|-------------|
| **Local (standalone)** | Running everything on your own machine. The app installs and starts the backend for you. |
| **Docker** | Containerised services on your machine or a lab server. |
| **Connect to existing** | A teammate already set up a backend. Enter the server URL. |

### 3. Start working

The app opens onto NeuroStudio, which is where nearly all of the suite's functionality lives. See [Architecture](#architecture) for what that means concretely.

> **Note on hardware**: NMTK does not install or configure physical neuromorphic hardware (Akida boards, PYNQ-Z2 FPGAs, Loihi nodes). That is the responsibility of whoever owns the hardware. Once a device and its vendor SDK are operational on the server, Neurochip's routes can talk to it. Read each module's **Limits** section before assuming a target works — shipped container images do not include vendor SDKs.

---

## The Suite

| Module | What you get today | Backend | UI surface |
|---|---|---|---|
| **[NeuroStudio (`neurocnl`)](./neurocnl)** | CNL→IR→NIR compiler, the seven-step Studio pipeline, canvas, deploy workspaces | In-process in `suite_api` at `/api/neurocnl`; the MuJoCo physics route proxied to `neurocnl-physics-worker:8006` | **The app's main surface** |
| **[Neurosim](./Neurosim)** | The Studio's `defineModel` canvas step and the app's `/canvas` routes | In-process at `/api/neurosim` | Inside NeuroStudio — not a separate module |
| **[Neurochip](./Neurochip)** | The Studio's `deployHardware` step: Akida, PYNQ, Lava, SC-NeuroCore workspaces | Split — analysis, estimation, export, faults, quantization, targets in-process; `akida`, `lava`, `speck`, `pynq`, `serial` proxied to `neurochip-hw-worker:8002` | Inside NeuroStudio — no Neurochip app exists |
| **[Neurohub](./Neurohub)** | Artifact registry and metadata for models, datasets, templates, presets, baselines | In-process; registry at `/api/v1`, module routes at `/api/neurohub` | A modal inside NeuroStudio |
| **[Neurobench](./Neurobench)** | Benchmark Configure / Results / Compare / Reports / Robustness | Fully proxied to `neurobench-runner-worker:8003` | Its own surface; desktop only |
| **[Neurosense](./Neurosense)** | Encoding presets, quality checks, NIR conversion; recording and device I/O when the optional worker runs | Split — presets, encoding, quality, nir in-process; recording, sessions, export, devices, stream, sense proxied to `neurosense-hw-worker:8004` (opt-in profile) | **No UI.** Backend only |
| **Notebooks** *(Jupyter)* | JupyterLab with nine kernels | `jupyter-server:8008` | WebView inside the app |

Nine Jupyter kernels are registered at startup, unconditionally: a base `Python (NeuroStudio)` kernel plus snnTorch, Nengo, Rockpool, Sinabs, Brian2, Lava, PyNN/SpiNNaker, and Akida. There is no separate PyTorch kernel — torch ships in the base image.

See [neurocnl/README.md](./neurocnl/README.md) for the CNL grammar, the compiler pipeline, and the seven Studio steps.

> `NMTK_SIDE/` is an internal docs tree (branding, market intelligence, product strategy). It is not a runtime module.

### Support vocabulary

Module READMEs use exactly three terms, and mean them literally:

- **`works`** — shipped, reachable, covered by tests.
- **`needs hardware`** — the code path exists but requires a physical device or a vendor SDK that shipped images do not install.
- **`not implemented`** — no working path today.

neurocnl additionally uses a `faithful` / `approximate` / `unsupported` scale. That is a *per-export-target fidelity* rating — a different axis from the three terms above. See its [Support Matrix](./neurocnl/docs/support_matrix.md).

---

## Architecture

**One app.** NMTK ships a single Flutter application, `nmtk/neuro_toolkit`. It fetches the module manifest from `launcher-control` and mounts exactly one module surface, full-window. The host renders **no navigation of its own** — chrome, nav, and workspace switching all belong to whichever module surface is mounted.

In practice that surface is almost always **NeuroStudio** (`neurocnl`), embedded through `NeurocnlShellAdapter`. **Neurobench** is the one other real native surface; it is nav-eligible on desktop and hidden on mobile. Everything else a user sees — the canvas, hardware deployment, the artifact registry — is a step or a modal *inside* NeuroStudio, not a separate app. Neurosense and the Lava backend have no UI at all.

`nmtk_ui_core` is the shared Flutter design system, consumed by three projects: the launcher, `neurocnl/frontend`, and `Neurobench/frontend`.

**One backend container, plus workers where hardware forces it.** Almost all module routes run in-process inside a single `suite_api` container. Separate services exist only where a vendor SDK, MuJoCo, or long-running compute demands isolation:

| Service | Port | Starts by default |
|---|---|---|
| `suite_api` | 9000 | yes |
| `neurochip-hw-worker` | 8002 | yes |
| `neurobench-runner-worker` | 8003 | yes |
| `neurosense-hw-worker` | 8004 | **no** — profile `neurosense` |
| `neurocnl-physics-worker` | 8006 | yes |
| `snn-mlir-compiler` | 8007 | yes |
| `jupyter-server` | 8008 | yes |
| `lava-backend` | 8012 | yes |
| `launcher-control` | 8091 (host 8090) | yes |

Proxied routes return HTTP 503 while their worker is down. See [workers/README.md](./workers/README.md) for what each one owns.

### Typical team workflow

1. A lab admin deploys the NMTK backend to a shared server from the app's **Backend Setup** screen, and connects the hardware.
2. Researcher A downloads the app, enters that server's URL, and opens NeuroStudio. They write a CNL specification, simulate it, and export a validated NIR artifact.
3. Researcher B connects to the same server, opens NeuroBench, loads that artifact, and benchmarks it.

No one needs a terminal, a Python environment, or knowledge of the infrastructure.

---

## Documentation

- **[AGENTS.md](./AGENTS.md)** — repository conventions and developer paths.
- **[CONTRIBUTING.md](./CONTRIBUTING.md)** — how to contribute.
- **[CODING_STYLE_GUIDE.md](./CODING_STYLE_GUIDE.md)** — style rules, including the Flutter design system.
- **[docs/ADR-claude/](./docs/ADR-claude)** — architecture decision records.
- **[neurocli/docs/user-guide.md](./neurocli/docs/user-guide.md)** — the command-line client.

Each module subdirectory carries its own `README.md`.

---

## Future / Planned

Not implemented today.

- **Kubernetes deployment mode.** A renderer exists (`nmtk/launcher_control/deployment_k8s_renderer.py`) and `modules.json` advertises the mode, but it is not a verified deployment path. Use Local or Docker.
- **Mobile distribution.** The Flutter app builds for mobile from source, but only desktop artifacts are released; there is no App Store or Google Play listing.
- **Expanded suite documentation.** An API reference index, installation and troubleshooting guides, and a production playbook were previously listed here and do not exist.

---

## License

NeuroMorphicToolKit and all of its first-party modules are licensed under the
**GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later)**.

Copyright (C) 2026 Yoshimar Todihardjo and NeuroMorphicToolKit contributors.

The AGPL is a strong copyleft license. In particular, its **network-use clause
(Section 13)** means that if you run a modified version of this software and let
users interact with it over a network, you must also offer those users the
complete corresponding source code of your modified version. Distributing the
software, modified or not, carries the usual GPL source-offer obligations.

- Full license text: [`LICENSE`](./LICENSE). A verbatim copy ships in each module root.
- Third-party dependency licenses and attribution: [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md).
- Some optional hardware integrations depend on proprietary vendor SDKs that are
  **not** distributed with this project and remain under their own licenses; see
  the Compliance Notes in `THIRD_PARTY_NOTICES.md` before redistributing builds
  that bundle them.
