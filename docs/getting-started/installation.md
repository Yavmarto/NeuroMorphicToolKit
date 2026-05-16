# Installation

This page covers system requirements and installation steps for the NeuroMorphicToolKit on macOS, Windows, and Linux.

---

## System requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | Dual-core 2.0 GHz | Quad-core+ (simulations are CPU-heavy) |
| RAM | 4 GB | 8 GB+ |
| Disk | 2 GB free | 10 GB+ (for multiple installed modules) |
| OS | macOS 12+, Windows 10+, Ubuntu 22.04+ | Latest stable |

### Software prerequisites

| Tool | Required for | Where to get it |
|------|-------------|-----------------|
| **Python 3.10–3.12** | Running module backends | [python.org](https://python.org/downloads/) |
| **Git 2.30+** | Cloning with submodules | [git-scm.com](https://git-scm.com/) |
| **Docker 24+ & Compose v2.20+** | Recommended startup path | [docs.docker.com](https://docs.docker.com/get-docker/) |
| **Flutter SDK 3.41+** | Building from source only | [flutter.dev](https://docs.flutter.dev/get-started/install) |

!!! note "Docker is optional"
    Docker is the fastest way to start all backends. If you prefer not to use it, follow the [Manual Setup](#option-b-manual-setup) path below.

---

## End-user install (recommended)

Download the latest release for your platform from the [GitHub Releases page](https://github.com/Completed-Spoon-6/NeuroMorphicToolKit/releases).

=== "macOS"

    1. Download the `.dmg` file.
    2. Open the DMG and drag **NeuroMorphicToolKit.app** to your Applications folder.
    3. Launch the app. On first run, modules will be extracted to `~/Library/Application Support/NeuroMorphicToolKit/`.
    4. Click **Install** on any module in the Catalog — the launcher handles Python venv creation automatically.

    !!! tip "Python detection"
        The app searches for Python in this order: bundled interpreter → `python3` on PATH → Homebrew paths → pyenv shims. If none are found, a setup screen appears with a one-click Homebrew install button.

=== "Windows"

    1. Download the `.exe` installer.
    2. Run the installer and follow the prompts.
    3. Launch NMTK from the Start Menu. Modules are extracted on first run.

    !!! warning "Visual C++ redistributable"
        Some modules (especially Akida support) require the [Visual C++ redistributable](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist). Install it if module startup fails.

=== "Linux"

    1. Download the `.AppImage` file.
    2. Make it executable and run it:
       ```bash
       chmod +x NeuroMorphicToolKit-*.AppImage
       ./NeuroMorphicToolKit-*.AppImage
       ```
    3. Required system libraries for the desktop GUI:
       ```bash
       sudo apt install libgtk-3-0 libwebkit2gtk-4.1-0
       ```

---

## Developer install (from source)

Use this path if you want to modify modules, contribute, or run the bleeding-edge `dev` branch.

### 1. Clone with submodules

```bash
git clone --recurse-submodules https://github.com/Completed-Spoon-6/NeuroMorphicToolKit.git
cd NeuroMorphicToolKit
git checkout dev
```

If you already cloned without `--recurse-submodules`:

```bash
git submodule update --init --recursive
```

Verify all six submodules are present:

```bash
git submodule status
# Expected: Neuro-Dream-Hand  Neurobench  Neurochip  Neurohub  Neurosense  neurocnl
```

### 2. Start backends

=== "Option A — Docker (recommended)"

    ```bash
    docker compose up --build
    ```

    This starts `suite_api` on `http://localhost:9000`. Verify it is healthy:

    ```bash
    curl http://localhost:9000/api/suite/health
    # Expected: {"status":"ok", ...}
    ```

    Optional worker profiles:

    ```bash
    # MuJoCo physics worker
    docker compose --profile physics up --build

    # Hardware workers (Neurochip + Neurosense)
    docker compose --profile hardware up --build
    ```

=== "Option B — Manual setup"

    ```bash
    # Create a shared virtual environment
    python3 -m venv .venv
    source .venv/bin/activate       # Windows: .venv\Scripts\activate

    # Install core modules
    pip install -e neurocnl/.[dev]
    pip install -e Neuro-Dream-Hand/.[dev]
    pip install -e suite_api/.

    # Start the unified backend from the repo root
    uvicorn suite_api.main:app --reload --port 9000
    ```

    Verify: `curl http://localhost:9000/api/suite/health`

### 3. Run the Flutter launcher

```bash
# Install shared UI package first
cd nmtk_ui_core && flutter pub get && cd ..

# Install and run the launcher
cd nmtk/neuro_toolkit
flutter pub get
flutter run -d macos    # or: -d windows / -d linux
```

=== "Linux-specific setup"

    Install required system libraries before running `flutter run -d linux`:

    ```bash
    sudo apt install -y \
      clang cmake lld ninja-build pkg-config \
      libgtk-3-dev libwebkit2gtk-4.1-dev \
      libblkid-dev liblzma-dev \
      libgl1-mesa-dev libosmesa6-dev
    ```

    Enable Linux desktop target:

    ```bash
    flutter config --enable-linux-desktop
    flutter doctor   # confirm "Linux toolchain" row is green
    ```

    **OrbStack / headless VM:** If `flutter run` fails with `cannot open display`, either:

    - Install XQuartz on macOS, set `export DISPLAY=host.docker.internal:0`, then retry, or
    - Use the Docker setup (Option A) and access module UIs at `http://localhost:9000` in your browser instead.

---

## Port reference

| Service | Port | Docker profile | Health endpoint |
|---------|------|---------------|-----------------|
| suite_api | 9000 | default | `GET /api/suite/health` |
| neurocnl physics worker | 8006 | physics | `GET /health` |
| neurochip hardware worker | 8002 | hardware | `GET /health` |
| neurosense hardware worker | 8004 | hardware | `GET /health` |
| neurobench runner worker | 8003 | jobs | `GET /health` |

---

## Verifying the install

Run the built-in smoke test to confirm the backend endpoints are reachable:

```bash
bash scripts/demo_smoke_test.sh
```

All checks should pass with exit code 0 before proceeding to the [Quick Start](quickstart.md).

---

## Akida support (optional)

BrainChip Akida requires extra setup beyond the base install:

- **Supported hosts:** Linux and Windows only (not macOS for local SDK verification)
- **Python:** `3.10` to `3.12` strictly
- **Required packages:** `tensorflow==2.19.*`, `akida==2.19.1`, `cnn2snn==2.19.1`, `akida-models==1.13.1`

On a supported host, open NMTK → Neurochip → **Prepare Akida Runtime** to install the MetaTF stack into the Neurochip environment automatically. If your launcher machine is macOS, see the [Akida remote host runbook](../hardware/akida.md).
