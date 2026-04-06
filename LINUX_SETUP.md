# Linux (Ubuntu) Setup Guide — NeuroMorphicToolKit

This guide provides instructions for setting up the NMTK development environment on Ubuntu Linux, including OrbStack VMs.

## 1. System Dependencies

Before installing Flutter or Python dependencies, install the required system libraries for desktop development and simulation.

```bash
sudo apt update
sudo apt install -y \
  build-essential \
  curl \
  git \
  unzip \
  xz-utils \
  zip \
  libglu1-mesa \
  # Flutter Desktop dependencies
  clang \
  cmake \
  ninja-build \
  pkg-config \
  libgtk-3-dev \
  libwebkit2gtk-4.1-dev \
  libblkid-dev \
  liblzma-dev \
  # MuJoCo & Simulation dependencies
  libgl1-mesa-dev \
  libosmesa6-dev \
  python3-dev \
  python3-venv
```

## 2. Flutter Setup

1. **Install Flutter**: Follow the [official Linux installation guide](https://docs.flutter.dev/get-started/install/linux).
2. **Enable Linux Desktop**:
   ```bash
   flutter config --enable-linux-desktop
   ```
3. **Verify**:
   ```bash
   flutter doctor
   ```
   Ensure the "Linux toolchain" and "GTK+ development" rows are checked.

## 3. OrbStack Specifics (X11/Wayland)

If you are running in an OrbStack Ubuntu machine and want to see the GUI:
- Ensure you have an X11 server (like XQuartz on Mac) or that OrbStack's built-in GUI support is active.
- If the GUI fails to launch, you can still develop using the **Docker Setup** (Option A in the main [SETUP_GUIDE.md](file:///Users/yoshimartodihardjo/NeuroMorphicToolKit/SETUP_GUIDE.md)) which serves the module interfaces as Web apps at `http://localhost:<port>`.

## 4. Makefile Usage

The `Makefile` at the root of the project now automatically detects your OS.

- **On macOS**: `make dev` runs `flutter run -d macos`
- **On Linux**: `make dev` runs `flutter run -d linux`

## 5. Troubleshooting Rendering

If you encounter GL errors when running simulations in a VM, try setting the rendering driver to EGL:

```bash
export MUJOCO_GL=egl
```

For heavy headless processing, ensure you have sufficient memory allocated to your OrbStack VM (at least 4GB recommended).
