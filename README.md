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

**The Solution:** The NeuroMorphicToolKit app is a downloadable desktop executable that serves as a single entry point to the entire suite. Users download NMTK, configure a backend connection (local or remote), and access all modules without juggling separate repositories, Python environments, or terminal commands.

---

## 🧩 The Submodule Ecosystem (The Apps)

NMTK orchestrates the following specialized modules, which can be dynamically downloaded into the main toolkit:

1. **[neurocnl / NeuroStudio](./neurocnl)**
   * *Purpose:* Translates plain-English specifications into verified Spiking Neural Networks (SNNs) and hosts the merged visual canvas workflow under the NeuroStudio launcher surface.
   * *Best for:* Fast prototyping, biological-constraint validation, visual editing, simulation preview, and export to hardware targets such as Loihi, Lava, and SpiNNaker.
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

### 📊 Current Module Status (May 2026)

| Module                           | Status | Backend | Frontend | Tests | Docker | CI |
| :------------------------------- | :----: | :-----: | :------: | :---: | :----: | :-: |
| **neurocnl / NeuroStudio** (incl. Neurosim canvas) | 99% | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| **Neurosense**             |  97%  |   ✅   |    ✅    |  ✅  |   ✅   | ✅ |
| **Neurohub**               |  85%  |   ✅   |    ✅    |  ⚠️  |   ✅   | ❌ |
| **Neurochip**              |  60%  |   ✅   |   ❌¹   |  ✅  |   ✅   | ✅ |
| **Neurobench**             |  95%  |   ✅   |    ✅    |  ✅  |   ✅   | ✅ |
| **Neuro-Dream-Hand**       |  95%  |   ✅   |   N/A   |  ✅  |  N/A  | ✅ |
| **NMTK Launcher**          |  95%  |   ✅   |    ✅    |  ✅  |  N/A  | ⚠️ |

> ¹ Neurochip has no standalone frontend. CNL Studio (NeuroStudio) owns the deployment and diagnostics UI via the [ADR 0021 handoff contract](./docs/ADR-claude/0021-studio-neurochip-handoff-contract.md). The Neurosim visual canvas is embedded inside NeuroStudio at the `/canvas` route — it is not a separate launcher card. NeuroDash has been deferred and is not in the active `modules.json` manifest.

---

## 🚀 Architecture & Deployment Strategy

NMTK uses a **"Downloadable Launcher + Backend-as-a-Service"** model. The desktop app and its mobile companion are thin clients that connect to a backend suite which can be hosted anywhere — on the same machine, on a lab server, or on a remote cloud instance.

### 1. The Desktop App & Mobile Companion

* **Download and run.** The NMTK desktop app is a native executable for macOS, Windows, and Linux — no build tools, no Python environment, no SDK required to install it.
* **Connect to a backend.** On first launch, the app walks the user through connecting to a backend suite. This can be a local instance deployed from within the app, or a remote server that a lab admin or team member has already set up.
* **Module UI is embedded.** All module interfaces (NeuroStudio, NeuroBench, Neurohub, etc.) are surfaced inside the NMTK app shell. Users navigate between modules from a single sidebar.
* **Mobile companion.** The NMTK mobile app offers the same core functionality as the desktop app — it connects to the same backend and can be used as a remote dashboard or on-the-go interface.

### 2. Backend Deployment

The backend suite is a set of Python/FastAPI services containerised with Docker. It can be deployed in multiple ways:

* **From within the NMTK app** (guided setup): the app provides a backend deployment wizard that orchestrates Docker on the current machine or targets a remote host. This is the recommended path for individual researchers.
* **By a lab admin or IT operator** (server deployment): deploy the backend once to a shared server using `docker compose up`. Team members then point their NMTK desktop or mobile app at that server URL and work collaboratively without any local setup.
* **On Kubernetes** for institutional or multi-user deployments.

> **Note on hardware**: NMTK does not install or configure physical neuromorphic hardware (Akida boards, PYNQ-Z2 FPGAs, Loihi nodes, etc.). Hardware setup is the responsibility of the person or team who owns the hardware. Once the hardware and its SDK are operational on the server, NMTK's Neurochip backend can communicate with it and surface diagnostics in the UI.

### 3. Typical Team Workflow

1. **Lab admin** deploys the NMTK backend suite to a shared server (`docker compose up`). The server has an Akida board connected and the MetaTF SDK installed.
2. **Researcher A** downloads the NMTK desktop app, points it at the lab server URL, and opens NeuroStudio. They write a CNL specification, simulate it, and export a validated NIR artifact.
3. **Researcher B** on a different machine (or on mobile) connects to the same server, opens NeuroBench, loads Researcher A's artifact, and runs a standardized benchmark against it.
4. Neither researcher needed to touch a terminal, configure a Python environment, or know anything about the underlying Docker infrastructure.

---

## 📚 Documentation

For users and developers:

- **[API Reference Index](./docs/api/README.md)** — Suite-level API entrypoint with service ports, live OpenAPI links, auth notes, and module API guides.
- **[User Guide: Installation](./docs/user/installation.md)** — Getting started with NMTK.
- **[User Guide: Troubleshooting](./docs/user/troubleshooting.md)** — Solutions for common startup issues.
- **[Developer Setup Guide](./SETUP_GUIDE.md)** — Running the full suite from source.
- **[Production Playbook](./docs/PRODUCTION_PLAYBOOK.md)** — Deployment and operational guide.

---

## 🛠 Getting Started

### End Users

Download the latest NMTK desktop app from the [Releases page](https://github.com/Completed-Spoon-6/NeuroMorphicToolKit/releases). Open it and follow the guided backend setup to deploy the suite locally or connect to an existing server.

The mobile companion app is available on the App Store and Google Play.

---

### NMTK Contributors (Source Build)

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
