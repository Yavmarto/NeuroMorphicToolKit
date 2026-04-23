# Installing the NeuroMorphic ToolKit (NMTK)

This guide covers the system requirements and installation steps for the NeuroMorphic ToolKit (NMTK) across different platforms.

## System Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| **CPU**  | Dual-core 2.0GHz | Quad-core+ (for simulations) |
| **RAM**  | 4 GB | 8 GB+ |
| **Disk** | 2 GB free space | 10 GB+ (for multiple modules) |
| **OS**   | Windows 10+, macOS 12+, Ubuntu 22.04+ | Latest stable OS versions |

### Software Prerequisites

*   **Python 3.10 or higher**: Required to run the backend modules.
*   **Git**: Required for cloning the repository and submodules.
*   **Docker (Optional)**: Recommended for running the entire suite easily using Docker Compose.

### Optional Akida Runtime

BrainChip Akida support is stricter than the toolkit baseline:

*   **Supported hosts for local Akida SDK setup**: Windows 10/11 or Linux hosts compatible with manylinux 2.28.
*   **Python for Akida**: `3.10` to `3.12`.
*   **MetaTF package set**: `tensorflow==2.19.*`, `akida==2.19.1`, `cnn2snn==2.19.1`, and `akida-models==1.13.1`.
*   **Windows prerequisite**: install the latest Visual C++ redistributable before preparing the Akida runtime.
*   **macOS note**: local Akida SDK install is not supported. On macOS, NMTK can still generate scaffold packages and use simulator-only fallback locally, but real SDK verification should run through Neurochip on Linux or Windows.
*   **Remote-host pairing**: use the [Akida remote host runbook](./akida_remote_host.md) when the launcher machine cannot satisfy the local SDK requirements.

---

## Installation Steps

### 1. Download and Install Python

NMTK requires a working Python 3.10+ environment.

*   **macOS**: Use Homebrew (`brew install python`) or download from [python.org](https://www.python.org/downloads/macos/).
*   **Windows**: Download the installer from [python.org](https://www.python.org/downloads/windows/). Ensure you check **"Add Python to PATH"** during installation.
*   **Linux**: Use your package manager (e.g., `sudo apt install python3 python3-venv`).

### 2. Clone the Repository

Open your terminal or command prompt and run:

```bash
git clone --recurse-submodules https://github.com/Completed-Spoon-6/NeuroMorphicToolKit.git
cd NeuroMorphicToolKit
```

If you have already cloned it without submodules, run:
```bash
git submodule update --init --recursive
```

### 3. Launch the Application

#### For Developers (Running from Source)

1.  **Install Flutter**: Follow the instructions at [flutter.dev](https://docs.flutter.dev/get-started/install).
2.  **Navigate to the Launcher**:
    ```bash
    cd nmtk/neuro_toolkit
    flutter pub get
    ```
3.  **Run the App**:
    ```bash
    flutter run -d macos  # or windows / linux
    ```

#### For End Users (Using Installers)

Refer to the platform-specific release artifacts (DMG for macOS, EXE for Windows, AppImage for Linux) provided in the GitHub Releases section.

---

## First-Time Setup

When you first launch NMTK, it will:
1.  **Detect Python**: If Python is not found, you will be guided through the setup.
2.  **Extract Modules**: Bundled modules will be extracted to your application support directory.
3.  **Welcome Walkthrough**: A brief onboarding will introduce you to the Dashboard, Catalog, and Workspace.

If you want local Akida SDK verification, install Neurochip first and then use the dedicated **Prepare Akida Runtime** action from the Akida deploy flow. This keeps the default Neurochip environment lean unless you explicitly opt into the BrainChip MetaTF stack. If the launcher host is macOS or the local Neurochip environment is outside Python `3.10` to `3.12`, follow the [Akida remote host runbook](./akida_remote_host.md) instead.

Now you're ready to explore the neuromorphic world!
