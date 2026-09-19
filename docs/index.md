# NeuroMorphicToolkit (NMTK)

> **Build, train, benchmark, and deploy spiking neural networks to real neuromorphic hardware — from one desktop app, without assembling SDKs, Python environments, or Docker infrastructure yourself.**

**License:** [AGPL-3.0-or-later](../LICENSE) · **Source:** [github.com/Yavmarto/NeuroMorphicToolKit](https://github.com/Yavmarto/NeuroMorphicToolKit)

---

## Why this exists

Neuromorphic hardware revenue was an estimated **~USD 50M in 2025**, projected to **~USD 185M by 2030** (~30% CAGR). The software and tooling slice is the fastest-growing part of that market — and the field is still blocked by fragmented SDKs and reinvention. NMTK is the neutral interoperability layer: one visual authoring surface on a **CNL → IR → NIR** compiler spine, with honest per-target status instead of demo hype.

---

## The wedge

| | |
|---|---|
| **Authoring for non-specialists** | Controlled-English specs plus a visual canvas — describe an SNN without hand-assembling every framework API. |
| **NIR as the spine** | One trained network, many backends (snnTorch, Brian2, Lava, Nengo, PyNN, Sinabs, Rockpool, plus Akida/PYNQ hardware paths). |
| **Zero-infrastructure start** | Download the desktop app; **Backend Setup** installs or connects to a backend in one step. End users never open a terminal. |
| **Honesty as a feature** | Every claim below uses the same vocabulary as the codebase: `works` / `needs hardware` / `not implemented`, and per-export `faithful` / `approximate` / `unsupported`. |

**What NMTK is not:** it does not install physical chips, shipped container images do not bundle vendor SDKs, and several targets are `not implemented` today. See the table.

---

## What works today

| Capability | Status | NIR fidelity (where it applies) |
|---|---|---|
| NeuroStudio — CNL authoring, validation, compile to NIR | `works` | `faithful` on the NIR spine |
| snnTorch train, simulate, export | `works` | `faithful` |
| Brian2 / Lava simulation (worker-backed) | `works` | `approximate` |
| JupyterLab (nine kernels) | `works` | — |
| NeuroBench — configure, run, compare, report | `works` | — (CPU/sim unless hardware attached) |
| Neurohub — artifact registry | `works` | — |
| [N-MNIST demo guide](guides/GUIDE-nmnist-snntorch.md) | `works` | `faithful` |
| [SHD demo guide](guides/GUIDE-shd-akida.md) — train & export | `works` | `approximate` |
| SHD on physical Akida card | `needs hardware` | `approximate` |
| Akida / PYNQ / Teensy / Speck deploy paths | `needs hardware` | `approximate` to `unsupported` per target |
| Neurosense live sensor I/O | `needs hardware` | — (opt-in `neurosense` worker profile) |
| Intel Loihi hardware, Lava on-chip | `not implemented` | `unsupported` |
| Kubernetes deployment mode | `not implemented` | — (renderer exists; path unverified) |
| Mobile app store distribution | `not implemented` | — (desktop releases only) |

Per-target measured round-trip ratings: [NIR fidelity leaderboard](hardware/support-matrix.md). Primitive-level detail: [neurocnl support matrix](../neurocnl/docs/support_matrix.md).

---

## Download and install

### 1. Desktop app (recommended)

Grab the latest build for **macOS, Windows, or Linux** from [GitHub Releases](https://github.com/Yavmarto/NeuroMorphicToolKit/releases).

On first launch, **Backend Setup** walks you through a one-time install or connection — local standalone, Docker on your machine, or an existing lab server. No terminal required.

### 2. Self-host the backend (operators)

Requires Docker and Docker Compose on the host:

```bash
git clone https://github.com/Yavmarto/NeuroMorphicToolKit.git
cd NeuroMorphicToolKit
docker compose up -d
```

Health check: `curl -fsS http://127.0.0.1:9000/health`. Point the desktop app at that host in **Sign in to your server**.

---

## See it in action

- **Reproducible walkthroughs:** [N-MNIST (simulation)](guides/GUIDE-nmnist-snntorch.md) and [SHD on Akida](guides/GUIDE-shd-akida.md)
- **3-minute product demo (video):** not published yet — use the walkthroughs above until the English demo video lands

---

## Learn more

- [Root README](../README.md) — architecture, module map, contributor paths
- [Demo guides index](guides/README.md)
- [Contributing](../CONTRIBUTING.md)
