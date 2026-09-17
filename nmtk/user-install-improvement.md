# User Installation & Cross-Platform Distribution Improvement Plan

## Executive Summary

Both the neurocnl (backend + frontend) and Neuro-Dream-Hand (NDH) projects currently lack any automated release, distribution, or installer pipeline. The end-user experience today requires cloning repos, installing Python/Conda/Flutter toolchains, and running manual commands. This spec defines the path to: **download an executable → run it → done**.

---

## Current State

| Component | How Users Install Today | Pain Points |
|-----------|------------------------|-------------|
| **neurocnl backend** | `git clone` → `pip install .` → `uvicorn backend.app.main:app` | Requires Python 3.11+, pip, manual dep install |
| **neurocnl frontend** | `git clone` → `flutter pub get` → `flutter run` (or Docker) | Requires Flutter SDK 3.24+ or Docker |
| **Neuro-Dream-Hand** | `git clone` → `conda env create` → `pip install -e .` | Requires Conda, Python 3.11, MuJoCo, ~2GB env |
| **Full stack (Docker)** | `docker-compose up` in neurocnl/ | Works but images not published; requires Docker install |

### What Already Exists
- ✅ Docker Compose for backend + frontend (local build only, not published)
- ✅ Nuitka standalone build target in NDH Makefile (`make build-nuitka`)
- ✅ Flutter supports iOS/Android/macOS/Windows/Linux/Web from single codebase
- ✅ CLI entry points defined in both pyproject.toml files
- ✅ CI runs on self-hosted (but no macOS/Windows runners)

### What's Missing
- ❌ No GitHub Releases workflow — no downloadable artifacts exist
- ❌ No PyPI publishing — `pip install neurocnl` doesn't work publicly
- ❌ No Docker registry push — must build images locally
- ❌ No multi-platform CI — only Linux builds
- ❌ No Flutter desktop builds in CI — only web
- ❌ No Nuitka builds in CI — only manual
- ❌ No installers (.msi, .dmg, .deb, AppImage)
- ❌ No unified setup/bootstrap script
- ❌ No cross-arch Docker images (no ARM64 for Apple Silicon)

---

## Target User Experience

### Scenario 1: Server Operator (sets up backend)
```
# Option A: Docker (recommended)
docker run -p 8000:8000 ghcr.io/yoshimartodihardjo/neurocnl-server:latest

# Option B: Download standalone binary
curl -LO https://github.com/.../releases/download/v0.2.0/neurocnl-server-linux-x86_64.tar.gz
tar xzf neurocnl-server-linux-x86_64.tar.gz
./neurocnl-server --port 8000

# Option C: pip install (for Python users)
pip install neurocnl[server]
neurocnl-server --port 8000
```

### Scenario 2: End User (connects frontend to server)
```
# Option A: Download desktop app
# → macOS: neurocnl-studio.dmg → drag to Applications → open → enter server URL
# → Windows: neurocnl-studio-setup.exe → install → open → enter server URL  
# → Linux: neurocnl-studio.AppImage → chmod +x → run → enter server URL

# Option B: Web app (zero install)
# → Navigate to https://neurocnl-studio.example.com
# → Enter server URL → connected

# Option C: Mobile
# → Download from App Store / Google Play → enter server URL
```

### Scenario 3: Developer / Researcher (uses as library)
```
pip install neurocnl
pip install neurodreamhand[physics]
```

---

## Implementation Plan

### Phase 1: GitHub Releases + Multi-Platform CI Builds

**Priority: CRITICAL**
**Effort: Medium**

#### 1.1 — Release Workflow (`.github/workflows/release.yml`)

Trigger on git tag push (`v*`). Matrix build across 3 OS × 2 architectures.

```yaml
name: Release
on:
  push:
    tags: ['v*']

permissions:
  contents: write
  packages: write

jobs:
  build-backend:
    strategy:
      matrix:
        include:
          - os: self-hosted
            target: linux-x86_64
            nuitka_args: ""
          - os: ubuntu-24.04-arm
            target: linux-arm64
            nuitka_args: ""
          - os: macos-latest
            target: macos-arm64
            nuitka_args: "--macos-create-app-bundle"
          - os: macos-13
            target: macos-x86_64
            nuitka_args: "--macos-create-app-bundle"
          - os: windows-latest
            target: windows-x86_64
            nuitka_args: "--windows-console-mode=attach"
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: |
          pip install -e ".[dev]"
          pip install nuitka ordered-set
      - name: Build standalone executable
        run: |
          python -m nuitka --standalone --follow-imports \
            --output-dir=dist/${{ matrix.target }} \
            ${{ matrix.nuitka_args }} \
            backend/app/main.py
      - name: Package artifact
        run: |
          cd dist/${{ matrix.target }}
          tar czf neurocnl-server-${{ matrix.target }}.tar.gz main.dist/
      - uses: actions/upload-artifact@v4
        with:
          name: neurocnl-server-${{ matrix.target }}
          path: dist/${{ matrix.target }}/*.tar.gz

  build-frontend-desktop:
    strategy:
      matrix:
        include:
          - os: macos-latest
            platform: macos
            build_cmd: "flutter build macos --release"
            artifact: "build/macos/Build/Products/Release/neurocnl_studio.app"
          - os: windows-latest
            platform: windows
            build_cmd: "flutter build windows --release"
            artifact: "build/windows/x64/runner/Release/"
          - os: self-hosted
            platform: linux
            build_cmd: "flutter build linux --release"
            artifact: "build/linux/x64/release/bundle/"
    runs-on: ${{ matrix.os }}
    defaults:
      run:
        working-directory: neurocnl/frontend
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      - run: flutter pub get
      - run: ${{ matrix.build_cmd }}
      - uses: actions/upload-artifact@v4
        with:
          name: neurocnl-studio-${{ matrix.platform }}
          path: neurocnl/frontend/${{ matrix.artifact }}

  build-frontend-web:
    runs-on: self-hosted
    defaults:
      run:
        working-directory: neurocnl/frontend
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          flutter-version: '3.24.0'
      - run: flutter pub get
      - run: flutter build web --release
      - uses: actions/upload-artifact@v4
        with:
          name: neurocnl-studio-web
          path: neurocnl/frontend/build/web/

  create-release:
    needs: [build-backend, build-frontend-desktop, build-frontend-web]
    runs-on: self-hosted
    steps:
      - uses: actions/download-artifact@v4
        with:
          path: artifacts/
      - uses: softprops/action-gh-release@v2
        with:
          files: artifacts/**/*
          generate_release_notes: true
          draft: false
```

#### 1.2 — NDH Release Workflow

Similar pattern for Neuro-Dream-Hand standalone executables:

```yaml
# Neuro-Dream-Hand/.github/workflows/release.yml
jobs:
  build-ndh:
    strategy:
      matrix:
        include:
          - os: self-hosted
            target: linux-x86_64
          - os: macos-latest
            target: macos-arm64
          - os: windows-latest
            target: windows-x86_64
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install -e ".[dev]"
      - run: |
          python -m nuitka --standalone --follow-imports \
            --output-dir=dist/${{ matrix.target }} \
            neurodreamhand/
      - uses: actions/upload-artifact@v4
        with:
          name: neurodreamhand-${{ matrix.target }}
          path: dist/${{ matrix.target }}/
```

---

### Phase 2: Docker Image Publishing

**Priority: HIGH**
**Effort: Small**

#### 2.1 — Push to GitHub Container Registry

Add to the release workflow or as a separate workflow:

```yaml
  publish-docker:
    runs-on: self-hosted
    permissions:
      packages: write
    steps:
      - uses: actions/checkout@v4
      - uses: docker/setup-buildx-action@v3
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v5
        with:
          context: neurocnl
          file: neurocnl/backend/Dockerfile
          push: true
          tags: |
            ghcr.io/yoshimartodihardjo/neurocnl-server:${{ github.ref_name }}
            ghcr.io/yoshimartodihardjo/neurocnl-server:latest
          platforms: linux/amd64,linux/arm64
      - uses: docker/build-push-action@v5
        with:
          context: neurocnl/frontend
          file: neurocnl/frontend/Dockerfile
          push: true
          tags: |
            ghcr.io/yoshimartodihardjo/neurocnl-studio:${{ github.ref_name }}
            ghcr.io/yoshimartodihardjo/neurocnl-studio:latest
          platforms: linux/amd64,linux/arm64
```

#### 2.2 — Multi-arch Support

Use `docker buildx` with `platforms: linux/amd64,linux/arm64` to support both Intel and Apple Silicon (via Docker Desktop) and ARM servers.

---

### Phase 3: PyPI Publishing

**Priority: HIGH**
**Effort: Small**

```yaml
  publish-pypi:
    runs-on: self-hosted
    environment: pypi
    permissions:
      id-token: write  # trusted publishing
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: '3.11'
      - run: pip install build
      - run: python -m build  # builds both neurocnl and neurodreamhand
      - uses: pypa/gh-action-pypi-publish@release/v1
```

**Setup required:**
1. Register `neurocnl` and `neurodreamhand` on PyPI
2. Configure Trusted Publishing (OIDC) in PyPI project settings
3. No API tokens needed — GitHub OIDC handles auth

**Result:** `pip install neurocnl` and `pip install neurodreamhand` work globally.

---

### Phase 4: Desktop App Packaging & Installers

**Priority: MEDIUM**
**Effort: Medium-Large**

#### 4.1 — macOS: DMG Installer

```bash
# In CI after flutter build macos
brew install create-dmg
create-dmg \
  --volname "NeuroCNL Studio" \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 100 \
  --app-drop-link 400 150 \
  neurocnl-studio-macos.dmg \
  build/macos/Build/Products/Release/neurocnl_studio.app
```

#### 4.2 — Windows: NSIS/Inno Setup Installer

```yaml
# In CI after flutter build windows
- uses: Minionguyjpro/Inno-Setup-Action@v1.2.2
  with:
    path: installer/windows/setup.iss
    options: /O+ /DMyAppVersion=${{ github.ref_name }}
```

#### 4.3 — Linux: AppImage

```yaml
# In CI after flutter build linux
- name: Build AppImage
  run: |
    wget https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage
    chmod +x appimagetool-x86_64.AppImage
    ./appimagetool-x86_64.AppImage build/linux/x64/release/bundle/ \
      neurocnl-studio-linux-x86_64.AppImage
```

#### 4.4 — Mobile (Future)

- iOS: `flutter build ipa` → upload to App Store Connect via `xcrun altool`
- Android: `flutter build appbundle` → upload to Google Play via Fastlane

---

### Phase 5: Unified Setup Script

**Priority: HIGH**
**Effort: Small**

Create a `setup.sh` (and `setup.ps1` for Windows) that auto-detects the platform, downloads the correct binaries, and starts the stack:

```bash
#!/usr/bin/env bash
# setup.sh — One-command NeuroCNL setup
set -euo pipefail

VERSION="${1:-latest}"
ARCH=$(uname -m)
OS=$(uname -s | tr '[:upper:]' '[:lower:]')

# Map architecture
case "$ARCH" in
  x86_64|amd64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

BASE_URL="https://github.com/yoshimartodihardjo/neurocnl/releases/download/${VERSION}"

echo "==> Downloading NeuroCNL Server (${OS}-${ARCH})..."
curl -LO "${BASE_URL}/neurocnl-server-${OS}-${ARCH}.tar.gz"
tar xzf "neurocnl-server-${OS}-${ARCH}.tar.gz"

echo "==> Downloading NeuroCNL Studio (${OS})..."
curl -LO "${BASE_URL}/neurocnl-studio-${OS}.tar.gz"
tar xzf "neurocnl-studio-${OS}.tar.gz"

echo ""
echo "✅ Installation complete!"
echo ""
echo "To start the server:"
echo "  ./neurocnl-server --port 8000"
echo ""
echo "To launch the studio:"
echo "  ./neurocnl-studio"
echo ""
echo "Or use Docker:"
echo "  docker run -p 8000:8000 ghcr.io/yoshimartodihardjo/neurocnl-server:${VERSION}"
```

---

### Phase 6: First-Run Configuration UX

**Priority: MEDIUM**
**Effort: Small**

The Flutter frontend should have a first-run setup screen:

1. **Auto-discover**: Scan `localhost:8000` for a running backend
2. **Manual entry**: Text field for server URL (e.g., `https://my-server.example.com:8000`)
3. **Health check**: Validate connection via `/health` endpoint
4. **Remember**: Persist server URL in local storage / shared preferences
5. **Status indicator**: Persistent connection status badge in the app

This requires a small frontend change — add a "Server Connection" settings page that stores the backend URL and validates connectivity before proceeding.

---

## Summary: Phased Delivery

| Phase | Deliverable | User Impact |
|-------|-------------|-------------|
| **1** | GitHub Releases + multi-OS builds | Users can download executables from GitHub |
| **2** | Docker images on GHCR | `docker run` to start server instantly |
| **3** | PyPI packages | `pip install neurocnl` for developers |
| **4** | Native installers (.dmg, .exe, .AppImage) | Polished install experience per platform |
| **5** | Unified setup script | One-command bootstrap for any platform |
| **6** | First-run connection UX | Frontend auto-connects to backend |

## File Changes Required

| File | Action | Purpose |
|------|--------|---------|
| `.github/workflows/release.yml` | Create | Multi-platform release builds |
| `.github/workflows/docker-publish.yml` | Create | Push Docker images to GHCR |
| `.github/workflows/pypi-publish.yml` | Create | Publish to PyPI on tag |
| `Neuro-Dream-Hand/.github/workflows/release.yml` | Create | NDH standalone builds |
| `scripts/setup.sh` | Create | Unified setup script (Linux/macOS) |
| `scripts/setup.ps1` | Create | Unified setup script (Windows) |
| `installer/macos/create-dmg.sh` | Create | macOS DMG packaging |
| `installer/windows/setup.iss` | Create | Windows Inno Setup script |
| `installer/linux/appimage.sh` | Create | Linux AppImage packaging |
| `neurocnl/frontend/lib/screens/server_setup.dart` | Create | First-run connection screen |
