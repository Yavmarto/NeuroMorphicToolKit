# NeuroMorphicToolkit (NMTK)

> **Unifying Neuromorphic Engineering, Neuroscience, and Software Development.**

Welcome to the **NeuroMorphicToolkit (NMTK)**—the central hub designed to bridge the gap between disciplines in the neuromorphic computing field. Whether you are a neuroscientist designing biological invariants, a software engineer building spiking neural networks, or a hardware roboticist deploying to edge devices, NMTK provides a unified, low-barrier entry point to streamline your R&D workflows.

The toolkit centralizes several specialized applications into a single, cohesive platform.

---

## 🎯 The Vision & Problem Statement

Neuromorphic computing is inherently multidisciplinary, yet most of its tooling is fragmented, SDK-specific, and assumes deep expertise from every user.

**NMTK is built for people who want to learn and work with SNNs and neuromorphic hardware without needing to be experts in every layer of the stack.** This includes:

* **Students and early-stage researchers** exploring spiking neural networks, biological modelling, or edge AI for the first time.
* **Computational and systems neuroscientists** who understand the biology but don't want to manage SDK toolchains, Docker infrastructure, or low-level hardware configuration.
* **ML engineers and software practitioners** entering the neuromorphic space who need a structured environment to prototype, benchmark, and validate SNN designs.
* **Applied researchers and teams** working with real neuromorphic hardware — where one team member (or an IT/lab admin) sets up and maintains the hardware backend (e.g. an Akida board, a PYNQ-Z2, or a Loihi node), and others connect to it remotely to author, simulate, and benchmark without touching the hardware directly.

**The Solution:** The NeuroMorphicToolKit app is a downloadable desktop executable that serves as a single entry point to the entire suite. Download NMTK, install the backend with one click (or connect to an existing server), and everything works — no juggling separate repositories, Python environments, or terminal commands.

---

## 🚀 Getting Started

### 1. Download the app

Grab the latest NMTK desktop app from the [Releases page](https://github.com/Completed-Spoon-6/NeuroMorphicToolKit/releases) for macOS, Windows, or Linux. A mobile companion app is available on the App Store and Google Play.

### 2. Install the backend — or connect to one

On first launch the app walks you through a one-time backend setup. Choose whichever option fits your situation:

| Option | When to use |
|--------|-------------|
| **Local (standalone)** | Running everything on your own machine. The app installs and starts the backend for you. |
| **Docker** | Prefer containerised services, or want a clean and reproducible environment on your machine or a lab server. |
| **Kubernetes** | Institutional or multi-user deployments where the backend runs in a shared cluster. |
| **Connect to existing** | A lab admin or teammate already set up a backend. Enter the server URL and you are ready to go. |

### 3. Start working

Once the backend is running the full suite is available in the sidebar — no further setup required.

> **Note on hardware**: NMTK does not install or configure physical neuromorphic hardware (Akida boards, PYNQ-Z2 FPGAs, Loihi nodes, etc.). Hardware setup is the responsibility of the person or team who owns the hardware. Once the hardware and its SDK are operational on the server, NMTK's Neurochip backend can communicate with it and surface diagnostics in the UI.

---

## 🧩 The Suite

NMTK ships with the following modules. All are started automatically when the backend is running.

1. **[neurocnl / NeuroStudio](./neurocnl)**
   * *Purpose:* Translates plain-English specifications into verified Spiking Neural Networks (SNNs) and hosts the merged visual canvas workflow under the NeuroStudio launcher surface.
   * *Best for:* Fast prototyping, biological-constraint validation, visual editing, simulation preview, and export to hardware targets such as Loihi, Lava, and SpiNNaker.
   * *Note:* The `/canvas` visual graph, preview, sweep, and export workspace shown inside NeuroStudio is owned by the [`Neurosim`](./Neurosim) module. It is embedded in CNL Studio's canvas rather than a standalone launcher card — see [`Neurosim/README.md`](./Neurosim/README.md) for its current scope.
2. **[Neurosense](./Neurosense)**
   * *Purpose:* Sensory processing and encoding. Converts traditional data modalities (vision, audio, touch) into spike trains.
   * *Best for:* Preparing datasets for SNNs and integrating sensors.
3. **[Neurochip](./Neurochip)**
   * *Purpose:* Interfacing directly with neuromorphic hardware backends.
   * *Best for:* Hardware engineers and low-level deployment orchestration.
4. **[Neurobench](./Neurobench)**
   * *Purpose:* Standardized benchmarking and testing of neuromorphic models and hardware configurations.
   * *Best for:* Evaluating performance, latency, and energy efficiency.
5. **[Neurohub](./Neurohub)**
   * *Purpose:* Community registry for sharing and discovering pre-trained SNN models, neuromorphic datasets, hardware profiles, NeuroCNL spec templates, encoding presets, and benchmark baselines.
   * *Best for:* Researchers publishing work, engineers looking for a starting point, and anyone who wants to reuse community-validated artefacts across the suite.
6. **[Neuro-Dream-Hand](./Neuro-Dream-Hand)**
   * *Purpose:* Applied hardware robotics and edge integration (e.g., controlling a robotic hand via SNNs and Teensy microcontrollers).
   * *Best for:* Applied robotics, edge AI, and end-to-end physical demonstrations.
7. **Notebooks** *(Jupyter)*
   * *Purpose:* A full JupyterLab environment embedded in the app, backed by the suite's Jupyter Server worker. Pre-configured kernels for SNNTorch, Lava, and PyTorch are registered automatically when the relevant modules are installed.
   * *Best for:* Exploratory analysis, writing reproducible experiments, and interactive prototyping without leaving the app.

### 📊 Current Module Status (May 2026)

| Module                           | Status | Backend | Frontend | Tests | Docker | CI |
| :------------------------------- | :----: | :-----: | :------: | :---: | :----: | :-: |
| **neurocnl / NeuroStudio** (incl. Neurosim canvas) | 99% | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| **Neurosense**             |  97%  |   ✅   |    ✅    |  ✅  |   ✅   | ✅ |
| **Neurohub**               |  85%  |   ✅   |    ✅    |  ⚠️  |   ✅   | ❌ |
| **Neurochip**              |  60%  |   ✅   |   ❌¹   |  ✅  |   ✅   | ✅ |
| **Neurobench**             |  95%  |   ✅   |    ✅    |  ✅  |   ✅   | ✅ |
| **Neuro-Dream-Hand**       |  95%  |   ✅   |   N/A   |  ✅  |  N/A  | ✅ |
| **Notebooks (Jupyter)**    |  90%  |   ✅   |    ✅    |  ✅  |   ✅   | N/A |
| **NMTK Launcher**          |  95%  |   ✅   |    ✅    |  ✅  |  N/A  | ⚠️ |

> ¹ Neurochip has no standalone frontend. CNL Studio (NeuroStudio) owns the deployment and diagnostics UI via the [ADR 0021 handoff contract](./docs/ADR-claude/0021-studio-neurochip-handoff-contract.md). The Neurosim visual canvas is embedded inside NeuroStudio at the `/canvas` route — it is not a separate launcher card. NeuroDash has been deferred and is not in the active `modules.json` manifest.
>
> Note: `NMTK_SIDE/` is an internal docs tree (branding, market intelligence, product strategy) used by the project team. It is not a runtime module and is intentionally excluded from the table above.

---

## 🏗 Architecture

NMTK uses a **"Downloadable App + Backend-as-a-Service"** model. The desktop and mobile apps are thin clients that connect to a backend suite which can run anywhere — on the same machine, on a lab server, or in a cloud cluster.

* **The app** is a native executable. No build tools, Python environment, or SDK required to install it.
* **The backend** is a set of Python/FastAPI services (containerised with Docker) that the app installs and manages, or that a lab admin deploys centrally for a team.
* **All module UIs** are surfaced inside the NMTK app shell. Users navigate between modules from a single sidebar — there is nothing else to open or install separately.

### Typical team workflow

1. **Lab admin** deploys the NMTK backend to a shared server (`docker compose up`). The server has an Akida board connected and the MetaTF SDK installed.
2. **Researcher A** downloads the NMTK desktop app, enters the lab server URL, and opens NeuroStudio. They write a CNL specification, simulate it, and export a validated NIR artifact.
3. **Researcher B** on a different machine (or on mobile) connects to the same server, opens NeuroBench, loads Researcher A's artifact, and runs a standardized benchmark against it.
4. Neither researcher needed to touch a terminal, configure a Python environment, or know anything about the underlying infrastructure.

---

## 📚 Documentation

- **[API Reference Index](./docs/api/README.md)** — Suite-level API entrypoint with service ports, live OpenAPI links, auth notes, and module API guides.
- **[User Guide: Installation](./docs/user/installation.md)** — Getting started with NMTK.
- **[User Guide: Troubleshooting](./docs/user/troubleshooting.md)** — Solutions for common startup issues.
- **[Developer Setup Guide](./docs/SETUP_GUIDE.md)** — Running the full suite from source.
- **[Production Playbook](./docs/PRODUCTION_PLAYBOOK.md)** — Deployment and operational guide.

---

## 🛠 NMTK Contributors (Source Build)

> These instructions are for developers contributing to NMTK itself — not for end users.

1. **Clone the Repository**:

   ```bash
   git clone --recurse-submodules https://github.com/Completed-Spoon-6/NeuroMorphicToolKit.git
   cd NeuroMorphicToolKit
   ```
2. **Run the Desktop Launcher**:

   ```bash
   cd nmtk/neuro_toolkit
   flutter pub get
   flutter run -d macos  # or windows/linux
   ```
3. **Start Backends (Docker)**:

   ```bash
   docker compose up --build
   ```
4. **Verify Services**:

   ```bash
   bash scripts/validate_docker_compose.sh
   bash scripts/demo_smoke_test.sh
   ```

For detailed module-specific development, explore the subdirectories (e.g., `neurocnl/`, `Neurochip/`) which contain their own `README.md` files.

## 📜 License

NeuroMorphicToolKit and all of its first-party modules are licensed under the
**GNU Affero General Public License v3.0 or later (AGPL-3.0-or-later)**.

Copyright (C) 2026 Yoshimar Todihardjo and NeuroMorphicToolKit contributors.

The AGPL is a strong copyleft license. In particular, its **network-use clause
(Section 13)** means that if you run a modified version of this software and let
users interact with it over a network, you must also offer those users the
complete corresponding source code of your modified version. Distributing the
software, modified or not, carries the usual GPL source-offer obligations.

- Full license text: [`LICENSE`](./LICENSE) (a verbatim copy ships in every package root).
- Third-party dependency licenses and attribution: [`THIRD_PARTY_NOTICES.md`](./THIRD_PARTY_NOTICES.md).
- Some optional hardware integrations depend on proprietary vendor SDKs that are
  **not** distributed with this project and remain under their own licenses; see
  the Compliance Notes in `THIRD_PARTY_NOTICES.md` before redistributing builds
  that bundle them.
