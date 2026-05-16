# Troubleshooting

Common problems and fixes. If your issue is not listed here, open a bug report on [GitHub Issues](https://github.com/Completed-Spoon-6/NeuroMorphicToolKit/issues) and include the error text from the module's Health Status panel.

---

## Startup

### Python not found / setup screen appears

The launcher cannot find Python 3.10+.

- **macOS:** Click the **Install with Homebrew** button on the setup screen, or run `brew install python` in a terminal, then restart NMTK.
- **Windows:** Download from [python.org](https://python.org/downloads/windows/) and check **"Add Python to PATH"** during install.
- **Linux:** `sudo apt install python3 python3-venv`

Verify after installing: `python3 --version` must return `3.10` or higher.

### Module fails to install

The venv creation or `pip install` step failed.

1. Check the terminal output (if running from source) or the module's **Health Status** detail panel.
2. Common causes:
    - **No internet connection** — pip needs to download packages.
    - **Permission denied** — ensure you have write access to `~/Library/Application Support/NeuroMorphicToolKit/` (macOS) or `%APPDATA%\NeuroMorphicToolKit\` (Windows).
    - **Missing system libraries** — MuJoCo-backed modules need `libgl1-mesa-dev` and `libosmesa6-dev` on Linux.
3. Click the **trash icon** to uninstall, then click **Install** to retry.

### Module status flips from "Starting" to "Error" immediately

A port conflict — another process is already using the required port.

```bash
# macOS / Linux: find what is using the port
lsof -i :9000

# Windows
netstat -ano | findstr :9000
```

Kill the conflicting process and click **Launch** again. The launcher also attempts to free the port automatically on each launch attempt.

---

## Backends

### `suite_api` does not start with Docker

```bash
# Inspect logs
docker compose logs suite_api

# Rebuild without cache if a dependency changed
docker compose build --no-cache suite_api
docker compose up suite_api
```

If the healthcheck keeps failing:

```bash
# Enter the container and test directly
docker compose exec suite_api bash
curl http://localhost:9000/api/suite/health
```

### `curl http://localhost:9000/api/suite/health` returns connection refused

The backend is not running. Start it:

```bash
docker compose up -d          # Docker path
# or
uvicorn suite_api.main:app --port 9000   # manual path
```

### Module import errors when running manually

```bash
# Install core modules first, from the repo root
pip install -e neurocnl/.[dev]
pip install -e Neuro-Dream-Hand/.[dev]
pip install -e suite_api/.
```

Always run `uvicorn suite_api.main:app` from the **repo root**, not from inside `suite_api/`.

### Poetry not found (Neurochip / Neurobench)

```bash
curl -sSL https://install.python-poetry.org | python3 -
```

Restart your shell and verify: `poetry --version`.

---

## Launcher and Flutter

### `flutter pub get` fails in `neuro_toolkit`

The shared UI package must be fetched first:

```bash
cd nmtk_ui_core && flutter pub get && cd ..
cd nmtk/neuro_toolkit && flutter pub get
```

### macOS build fails after a `flutter upgrade`

```bash
cd nmtk/neuro_toolkit
flutter clean
flutter pub get
flutter run -d macos
```

### WebView shows "Connection Refused"

The frontend loaded before the backend was ready.

1. Wait 5–10 seconds — some backends take longer on first start.
2. Verify the backend is healthy: `curl http://localhost:9000/api/suite/health`
3. Check that your macOS/Windows firewall is not blocking loopback connections on port 9000.
4. Click **Open in Browser** in the launcher to use the system browser as a fallback.

### Linux: `cannot open display` when running `flutter run -d linux`

You are in a headless environment (OrbStack, SSH session, CI).

**Option 1 — XQuartz:**

```bash
# On macOS host
brew install --cask xquartz
# XQuartz → Preferences → Security → check "Allow connections from network clients"
# Restart XQuartz, then in the Linux VM:
export DISPLAY=host.docker.internal:0
flutter run -d linux
```

**Option 2 (recommended for VMs) — use Docker + browser:**

```bash
docker compose up -d
# Access module UIs at http://localhost:9000 in your Mac browser
```

---

## Module-specific

### NeuroStudio: "Open in NeuroStudio" does nothing

- Confirm `http://localhost:9000/api/suite/health` returns `"status":"ok"`.
- If NeuroStudio is not yet launched, open it from the Catalog first.
- Click **Open in System Browser** and retry from there.

### NeuroStudio opens but the canvas is empty

The handoff worked but the CNL did not parse into a valid graph.

1. Check that the imported CNL text is visible in the canvas CNL panel.
2. If the text is present but the canvas is empty, an error banner should describe the parse failure.
3. Fix the CNL and click **Sync to Canvas**.

If the canvas CNL panel is also empty, the handoff itself failed — check the browser console for a network error on the `/api/neurocnl/neurosim_handoff` endpoint.

### Export turns the entire page into raw text

This is a known bug in certain WebView configurations. Workaround: click **Open in Browser** from the launcher toolbar and perform the export from there.

### Akida SDK verification blocked

BrainChip Akida SDK is not supported on macOS for local verification.

| Scenario | Action |
|---------|--------|
| macOS launcher | Use scaffold export + simulator fallback locally; point SDK verification at a Neurochip instance on Linux or Windows using the [Akida remote host runbook](hardware/akida.md) |
| Linux/Windows, Python outside 3.10–3.12 | Create a clean venv with Python 3.11 and reinstall via **Prepare Akida Runtime** |
| Missing MetaTF packages | Open Neurochip → **Prepare Akida Runtime** to install the full BrainChip stack |
| Windows: Visual C++ error | Install the [Visual C++ redistributable](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist) |

### Akida remote host pairing does not reach Neurochip

Check that both services are reachable from the launcher machine:

```bash
# Launcher control API (on the remote host)
python3 scripts/launcher_control_service.py --host 0.0.0.0 --port 8090

# Neurochip backend (on the remote host)
poetry run uvicorn neurochip.app.main:app --host 0.0.0.0 --port 8002
```

Set these environment variables on the launcher machine:

```bash
export NMTK_CONTROL_API_BASE_URL=http://<remote-host>:8090
export NMTK_NEUROCHIP_BASE_URL=http://<remote-host>:8002
```

---

## Git / submodules

### Submodule directories are empty

```bash
git submodule update --init --recursive
```

### Submodule is on the wrong branch or in detached HEAD

```bash
cd <submodule>
git checkout dev
git pull origin dev
```

---

## MuJoCo / simulation rendering

### `EGL error` or `GL error` on Linux

```bash
export MUJOCO_GL=egl
# Then restart the physics worker
```

For headless CI or OrbStack VMs, also ensure at least 4 GB of RAM is allocated.

---

## Still stuck?

1. Run the launcher doctor: `python3 scripts/launcher_control_service.py --doctor --json` and note any `fatalCount > 0` entries.
2. Run the smoke test: `bash scripts/demo_smoke_test.sh` and share the output.
3. Open an issue at [github.com/Completed-Spoon-6/NeuroMorphicToolKit/issues](https://github.com/Completed-Spoon-6/NeuroMorphicToolKit/issues) with the doctor output and the error text from the Health Status panel.
