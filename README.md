# NeuroMorphicToolkit (NMTK)

> **Unifying Neuromorphic Engineering, Neuroscience, and Software Development.**

Welcome to the **NeuroMorphicToolkit (NMTK)**—the central hub designed to bridge the gap between disciplines in the neuromorphic computing field. Whether you are a neuroscientist designing biological invariants, a software engineer building spiking neural networks, or a hardware roboticist deploying to edge devices, NMTK provides a unified, low-barrier entry point to streamline your R&D workflows.

The toolkit centralizes several specialized applications into a single, cohesive platform.

---

## 🎯 The Vision & Problem Statement

Neuromorphic computing is inherently multidisciplinary.
*   **Neuroscientists** understand the biological mechanisms but may lack the software engineering background for complex pipelines.
*   **Software Developers** know how to build robust systems but struggle with the biological constraints (invariants) and specialized hardware.
*   **Hardware Engineers** build the physical neuromorphic chips and robots but need accessible interfaces and compilers to test their designs.

**The Solution:** The NeuroMorphicToolkit app serves as the single entry point. Instead of juggling a dozen fragmented repositories, users install one native toolkit application. From this app, professionals can browse, download, and launch specialized modules tailored to their immediate needs, completely hiding the complex setup, dependency management, and interoperability issues.

---

## 🧩 The Submodule Ecosystem (The Apps)

NMTK orchestrates the following specialized modules, which can be dynamically downloaded into the main toolkit:

1.  **[NeuroCNL](./neurocnl) (Conceptual Neuromorphic Language)**
    *   *Purpose:* Translates plain-English specifications into verified Spiking Neural Networks (SNNs).
    *   *Best for:* Fast prototyping, ensuring biological constraints, and exporting to various hardware (Loihi, Lava, SpiNNaker).
2.  **[Neurosim](./Neurosim)**
    *   *Purpose:* A robust simulation environment to test neuromorphic models before physical deployment.
    *   *Best for:* Software testing, model validation, and parameter tuning.
3.  **[Neurosense](./Neurosense)**
    *   *Purpose:* Sensory processing and encoding. Converts traditional data modalities (vision, audio, touch) into spike trains.
    *   *Best for:* Preparing datasets for SNNs and integrating sensors.
4.  **[Neurochip](./Neurochip)**
    *   *Purpose:* Interfacing directly with neuromorphic hardware backends.
    *   *Best for:* Hardware engineers and low-level deployment orchestration.
5.  **[Neurobench](./Neurobench)**
    *   *Purpose:* Standardized benchmarking and testing of neuromorphic models and hardware configurations.
    *   *Best for:* Evaluating performance, latency, and energy efficiency.
6.  **[Neurohub](./Neurohub)**
    *   *Purpose:* Community registry for sharing and discovering pre-trained SNN models, neuromorphic datasets, hardware profiles, NeuroCNL spec templates, encoding presets, and benchmark baselines.
    *   *Best for:* Researchers publishing work, engineers looking for a starting point, and anyone who wants to reuse community-validated artefacts across the suite.
7.  **[NeuroDash](./NeuroDash)**
    *   *Purpose:* Central orchestration dashboard for managing cross-app projects, pipelines, milestones, and team collaboration across the full suite.
    *   *Best for:* Team leads and project managers coordinating work across multiple Neuro-space apps.
8.  **[Neuro-Dream-Hand](./Neuro-Dream-Hand)**
    *   *Purpose:* Applied hardware robotics and edge integration (e.g., controlling a robotic hand via SNNs and Teensy microcontrollers).
    *   *Best for:* Applied robotics, edge AI, and end-to-end physical demonstrations.

### 📊 Current Module Status (March 2026)

| Module | Status | Backend | Frontend | Tests | Docker | CI |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **NeuroCNL** | 97% | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Neurosim** | 80% | ✅ | ⚠️ | ✅ | ✅ | ✅ |
| **Neurosense** | 85% | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| **Neurohub** | 0% | ❌ | ❌ | ❌ | ❌ | ❌ |
| **NeuroDash** | 80% | ✅ | ✅ | ✅ | ⚠️ | ✅ |
| **Neurochip** | 90% | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Neurobench** | 70% | ⚠️ | ⚠️ | ✅ | ✅ | ✅ |
| **Neuro-Dream-Hand** | 95% | ✅ | N/A | ✅ | N/A | ✅ |
| **NMTK Launcher** | 85% | ✅ | ✅ | ✅ | N/A | ❌ |

---

## 🚀 Architecture & Deployment Strategy

To achieve the goal of a single deployable desktop app with self-hosted downloadable modules (macOS, Windows, Linux), we employ a **"Launcher + Micro-Service Container"** architecture.

### 1. The Core Desktop App: NMTK Flutter Client (`neuro_toolkit` + `nmtk`)
The main repository (`neuro_toolkit`) is a desktop Flutter application.
*   **Unified Dashboard:** Acts as an "App Store" and launcher for the user. It manages user profiles, general settings, and global state.
*   **Self-Hosted Desktop Delivery:** Compiles natively to Windows, macOS, and Linux to provide a robust, self-hosted environment.
*   **Module Manager:** Handles downloading, version control, and storage of the submodules locally.

### 2. Module Delivery System (Local Orchestration)
Because the sub-apps require heavy Python environments, Docker containers, and complex scientific libraries, deploying them as simple plugins isn't feasible. Instead, NMTK uses a local micro-service orchestration approach:

*   **Process Orchestration (Docker / Virtual Environments)**
    *   When a user clicks "Install Neurobench", the Flutter app downloads the `Neurobench` module package (which contains its `docker-compose.yml`, Python backend, and compiled frontend assets).
    *   The NMTK desktop app acts as a local daemon manager. It spins up the necessary Docker containers (or isolated Python `venv`s via the `nmtk/installer` scripts) directly on the host machine in the background.
    *   The UI of the submodule is presented seamlessly inside the Flutter desktop app using a **Web View** (pointing to the module's localized frontend ports) or native Flutter UI communicating via a local REST/gRPC API.

### 3. Workflow Example
1.  A hardware engineer opens the NMTK app (Flutter).
2.  They navigate to the "Module Hub" and download **NeuroCNL** and **Neuro-Dream-Hand**.
3.  Behind the scenes, NMTK pulls the Docker containers/dependencies and starts the local backend servers for these modules.
4.  The engineer clicks "Open NeuroCNL". The Flutter app opens a new tab displaying the NeuroCNL interface natively. They write an English spec.
5.  They switch to the "Neuro-Dream-Hand" tab, pass the generated model from NeuroCNL, and click "Deploy to Hardware".
6.  Everything happens seamlessly without the engineer ever opening a terminal, managing a `.env` file, or running a `pip install`.

---

## 📚 Documentation

For users and developers:
-   **[API Reference Index](./docs/api/README.md)** — Suite-level API entrypoint with service ports, live OpenAPI links, auth notes, and module API guides.
-   **[User Guide: Installation](./docs/user/installation.md)** — Getting started with NMTK.
-   **[User Guide: Troubleshooting](./docs/user/troubleshooting.md)** — Solutions for common startup issues.
-   **[Developer Setup Guide](./SETUP_GUIDE.md)** — Running the full suite from source.
-   **[Production Playbook](./docs/PRODUCTION_PLAYBOOK.md)** — Deployment and operational guide.

---

## 🛠 Getting Started

### Quick Start (Developers)

1.  **Clone the Repository**:
    ```bash
    git clone --recurse-submodules https://github.com/Completed-Spoon-6/NeuroMorphicToolKit.git
    cd NeuroMorphicToolKit
    ```

2.  **Run the Desktop Launcher**:
    ```bash
    cd nmtk/neuro_toolkit
    flutter pub get
    flutter run -d macos  # or windows/linux
    ```

3.  **Start Backends (Docker)**:
    ```bash
    docker compose up --build
    ```

4.  **Verify Services**:
    ```bash
    bash scripts/validate_docker_compose.sh
    bash scripts/demo_smoke_test.sh
    ```

For detailed module-specific development, explore the subdirectories (e.g., `neurocnl/`, `Neurosim/`) which contain their own `README.md` files.
