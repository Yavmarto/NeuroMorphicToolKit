# Containerize Launcher Control Service Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `launcher_control_service` into a Docker container so the complete backend stack (control API + suite_api + workers) runs on one device, removing the Mac intermediary requirement for end-user clients.

**Architecture:** The `launcher_control_service` is a Python HTTP server (port 8091) that manages module state, hardware provisioning (PYNQ/Akida), and workspace. Currently it runs on the developer's Mac as a host process; after this change it will run in a Docker container alongside `suite_api`. Two new Docker-managed volumes will persist its state (settings, module states, workspace, deployment). `run_dev.sh` will no longer spawn a local control process when `--docker` or `--remote-host` is used — instead Flutter connects directly to port 8091 on the Docker host.

**Tech Stack:** Python 3.12-slim (Docker), Docker Compose v2, Bash, existing `nmtk/launcher_control/server.py` HTTP server

---

## File Map

| File | Action | Responsibility |
|---|---|---|
| `nmtk/launcher_control/config.py` | **Create** | Resolve all state/data paths from env vars with repo-root defaults |
| `nmtk/launcher_control/server.py` | **Modify** | Import path constants from `config.py` instead of hardcoding |
| `Dockerfile.control` | **Create** | Docker image for the launcher control service |
| `docker-compose.yml` | **Modify** | Add `launcher-control` service + two named volumes |
| `docker-compose.dev.yml` | **Modify** | Add dev override (source mount for live reload) |
| `scripts/run_dev.sh` | **Modify** | Skip local control service in `--docker` / `--remote-host` mode; pass correct control API URL to Flutter |
| `tests/test_launcher_control_service.py` | **Modify** | Add env-var path override test |

---

## Task 1: Extract configurable state paths into `config.py`

The five hardcoded `Path` globals in `server.py` (lines 53–59 and 148) must become configurable via env vars so a Docker container can redirect them to a persistent volume.

**Files:**
- Create: `nmtk/launcher_control/config.py`
- Modify: `nmtk/launcher_control/server.py` (remove the 6 `Path` globals, import from config)
- Modify: `tests/test_launcher_control_service.py` (add env-override test)

---

- [ ] **Step 1: Write the failing test**

Add at the bottom of `tests/test_launcher_control_service.py`:

```python
class TestConfigPaths(unittest.TestCase):
    def test_default_paths_use_repo_root(self):
        """Without env vars set, all paths fall under REPO_ROOT."""
        import nmtk.launcher_control.config as cfg
        import importlib
        # Reload to pick up clean env
        with mock.patch.dict(os.environ, {}, clear=False):
            # Remove overrides if accidentally set
            for key in ("NMTK_STATE_DIR", "NMTK_DATA_DIR"):
                os.environ.pop(key, None)
            importlib.reload(cfg)
            assert cfg.STATE_FILE.is_relative_to(PROJECT_ROOT)
            assert cfg.SETTINGS_FILE.is_relative_to(PROJECT_ROOT)
            assert cfg.WORKSPACE_FILE.is_relative_to(PROJECT_ROOT)
            assert cfg.DEPLOYMENT_STATE_FILE.is_relative_to(PROJECT_ROOT)
            assert cfg.DEPLOYMENT_SECRET_FILE.is_relative_to(PROJECT_ROOT)
            assert cfg.SUITE_API_ENV_ROOT.is_relative_to(PROJECT_ROOT)
            assert cfg.MODULES_MANIFEST.is_relative_to(PROJECT_ROOT)

    def test_nmtk_state_dir_overrides_state_files(self):
        """NMTK_STATE_DIR redirects the 4 module/workspace/settings state files."""
        import nmtk.launcher_control.config as cfg
        import importlib
        with tempfile.TemporaryDirectory() as state_dir:
            with mock.patch.dict(os.environ, {"NMTK_STATE_DIR": state_dir}):
                importlib.reload(cfg)
                assert str(cfg.STATE_FILE).startswith(state_dir)
                assert str(cfg.SETTINGS_FILE).startswith(state_dir)
                assert str(cfg.WORKSPACE_FILE).startswith(state_dir)
                assert str(cfg.DEPLOYMENT_STATE_FILE).startswith(state_dir)

    def test_nmtk_data_dir_overrides_secrets(self):
        """NMTK_DATA_DIR redirects deployment_secrets and suite_api_env."""
        import nmtk.launcher_control.config as cfg
        import importlib
        with tempfile.TemporaryDirectory() as data_dir:
            with mock.patch.dict(os.environ, {"NMTK_DATA_DIR": data_dir}):
                importlib.reload(cfg)
                assert str(cfg.DEPLOYMENT_SECRET_FILE).startswith(data_dir)
                assert str(cfg.SUITE_API_ENV_ROOT).startswith(data_dir)
```

- [ ] **Step 2: Run the test to confirm it fails**

```bash
cd $HOME/NeuroMorphicToolKit
python -m pytest tests/test_launcher_control_service.py::TestConfigPaths -v
```

Expected: `ImportError` or `AttributeError` — `nmtk.launcher_control.config` does not exist yet.

- [ ] **Step 3: Create `nmtk/launcher_control/config.py`**

```python
"""Configurable filesystem paths for the launcher control service.

All paths default to locations relative to the repository root. Set
``NMTK_STATE_DIR`` or ``NMTK_DATA_DIR`` as environment variables to redirect
them — this is required when running the service in a Docker container where
state must live on a persistent volume rather than inside the image.

Environment variables
---------------------
NMTK_STATE_DIR
    Directory that holds the four JSON state files (module_states,
    launcher_settings, workspace_state, deployment_state).
    Default: ``<repo_root>/nmtk/neuro_toolkit/``

NMTK_DATA_DIR
    Directory that holds deployment secrets and the suite_api venv.
    Default: ``<repo_root>/.nmtk/``
"""

from __future__ import annotations

import os
from pathlib import Path

# Resolved once at import time so callers get a stable object.
# Tests that need different values should reload this module inside a
# mock.patch.dict(os.environ, ...) block.

REPO_ROOT: Path = Path(__file__).resolve().parents[2]


def _state_dir() -> Path:
    env = os.environ.get("NMTK_STATE_DIR", "").strip()
    return Path(env) if env else REPO_ROOT / "nmtk" / "neuro_toolkit"


def _data_dir() -> Path:
    env = os.environ.get("NMTK_DATA_DIR", "").strip()
    return Path(env) if env else REPO_ROOT / ".nmtk"


# ── Paths resolved from env vars ──────────────────────────────────────────────

STATE_FILE: Path = _state_dir() / "module_states.json"
SETTINGS_FILE: Path = _state_dir() / "launcher_settings.json"
WORKSPACE_FILE: Path = _state_dir() / "workspace_state.json"
DEPLOYMENT_STATE_FILE: Path = _state_dir() / "deployment_state.json"

DEPLOYMENT_SECRET_FILE: Path = _data_dir() / "deployment_secrets.json"
SUITE_API_ENV_ROOT: Path = _data_dir() / "suite_api_env"

# ── Paths that are always relative to the repo root (baked into the image) ───

MODULES_MANIFEST: Path = REPO_ROOT / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
```

- [ ] **Step 4: Update `nmtk/launcher_control/server.py` to import from config**

Find and replace the six globals at the top of `server.py` (currently around lines 53–59 and 148). They look like this:

```python
REPO_ROOT = Path(__file__).resolve().parents[2]
MODULES_MANIFEST = REPO_ROOT / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
STATE_FILE = REPO_ROOT / "nmtk" / "neuro_toolkit" / "module_states.json"
SETTINGS_FILE = REPO_ROOT / "nmtk" / "neuro_toolkit" / "launcher_settings.json"
WORKSPACE_FILE = REPO_ROOT / "nmtk" / "neuro_toolkit" / "workspace_state.json"
DEPLOYMENT_STATE_FILE = REPO_ROOT / "nmtk" / "neuro_toolkit" / "deployment_state.json"
DEPLOYMENT_SECRET_FILE = REPO_ROOT / ".nmtk" / "deployment_secrets.json"
```

And further down (around line 148):

```python
SUITE_API_ENV_ROOT = REPO_ROOT / ".nmtk" / "suite_api_env"
```

Replace **all eight lines** with:

```python
from .config import (
    REPO_ROOT,
    MODULES_MANIFEST,
    STATE_FILE,
    SETTINGS_FILE,
    WORKSPACE_FILE,
    DEPLOYMENT_STATE_FILE,
    DEPLOYMENT_SECRET_FILE,
    SUITE_API_ENV_ROOT,
)
```

> **Important:** Remove the original `REPO_ROOT = Path(__file__).resolve().parents[2]` line — `REPO_ROOT` is now exported from `config.py`. Keep all other `Path` imports if they exist elsewhere.

- [ ] **Step 5: Run the tests to confirm they pass**

```bash
python -m pytest tests/test_launcher_control_service.py -v 2>&1 | tail -30
```

Expected: `TestConfigPaths` tests PASS. All previously passing tests should still pass (the imported names have identical default values).

- [ ] **Step 6: Commit**

```bash
git add nmtk/launcher_control/config.py nmtk/launcher_control/server.py tests/test_launcher_control_service.py
git commit -m "refactor: extract configurable state paths from launcher control server into config.py"
```

---

## Task 2: Create `Dockerfile.control`

A minimal Python 3.12-slim image that runs the launcher control service. It includes `openssh-client` and `rsync` for PYNQ/Akida hardware provisioning over SSH.

**Files:**
- Create: `Dockerfile.control`

---

- [ ] **Step 1: Create the Dockerfile**

Create `$HOME/NeuroMorphicToolKit/Dockerfile.control`:

```dockerfile
# Launcher control service — orchestrates module state, workspace, and
# hardware provisioning (PYNQ/Akida SSH). Suite_api is managed by Docker
# Compose, not by this process (--no-manage-suite-api).
FROM python:3.12-slim

# openssh-client + rsync are required for PYNQ and Akida SSH provisioning.
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-client rsync \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy the launcher control package and its entry-point script.
# No extra pip dependencies — the service uses only stdlib + tomllib (3.11+).
COPY nmtk/launcher_control/ nmtk/launcher_control/
COPY scripts/launcher_control_service.py scripts/launcher_control_service.py

# modules.json is read at startup to load module definitions.
# assets/ also contains overlay staging files for PYNQ provisioning.
COPY nmtk/neuro_toolkit/assets/ nmtk/neuro_toolkit/assets/

# State and secrets are redirected to Docker volumes via these env vars.
# Matches the volume mount points declared in docker-compose.yml.
ENV NMTK_STATE_DIR=/app/state
ENV NMTK_DATA_DIR=/app/data
ENV PYTHONUNBUFFERED=1

EXPOSE 8091

# --no-manage-suite-api: Docker Compose owns suite_api lifecycle, not us.
CMD ["python", "scripts/launcher_control_service.py", \
     "--host", "0.0.0.0", \
     "--port", "8091", \
     "--no-manage-suite-api"]
```

- [ ] **Step 2: Build the image to confirm it compiles**

```bash
cd $HOME/NeuroMorphicToolKit
docker build -f Dockerfile.control -t nmtk-control-test .
```

Expected: build completes without errors. The image should be ~200–300 MB (Python slim + ssh client).

- [ ] **Step 3: Smoke-test the image starts and shows help**

```bash
docker run --rm nmtk-control-test python scripts/launcher_control_service.py --help
```

Expected output (exact text may differ):
```
usage: launcher_control_service.py [-h] [--host HOST] [--port PORT] [--doctor] [--json] [--manage-suite-api] [--no-manage-suite-api] [--external-probe-host EXTERNAL_PROBE_HOST]
```

- [ ] **Step 4: Clean up test image**

```bash
docker rmi nmtk-control-test
```

- [ ] **Step 5: Commit**

```bash
git add Dockerfile.control
git commit -m "feat: add Dockerfile.control for containerized launcher control service"
```

---

## Task 3: Add `launcher-control` service to `docker-compose.yml`

**Files:**
- Modify: `docker-compose.yml`

Add the `launcher-control` service definition before the `prometheus` service, and add two named volumes at the bottom.

---

- [ ] **Step 1: Add the service**

In `docker-compose.yml`, insert the following block **after the `lava-backend` service block and before the `neurocnl-physics-worker` service block** (i.e., after line 117, before line 119):

```yaml
  launcher-control:
    build:
      context: .
      dockerfile: Dockerfile.control
    ports:
      - "${LAUNCHER_CONTROL_PORT:-8091}:8091"
    environment:
      - PYTHONUNBUFFERED=1
      - NMTK_STATE_DIR=/app/state
      - NMTK_DATA_DIR=/app/data
    volumes:
      - launcher_control_state:/app/state
      - launcher_control_data:/app/data
    healthcheck:
      test: ["CMD", "python", "-c", "import urllib.request; urllib.request.urlopen('http://localhost:8091/health')"]
      start_period: 30s
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    networks:
      - backend-net
```

- [ ] **Step 2: Add the two named volumes**

In the `volumes:` section at the bottom of `docker-compose.yml` (currently contains `prometheus_data`, `grafana_data`, `jupyter_notebooks`), add:

```yaml
  launcher_control_state:
  launcher_control_data:
```

The complete `volumes:` block should now read:

```yaml
volumes:
  prometheus_data:
  grafana_data:
  jupyter_notebooks:
  launcher_control_state:
  launcher_control_data:
```

- [ ] **Step 3: Validate the compose file**

```bash
cd $HOME/NeuroMorphicToolKit
docker compose config --quiet
```

Expected: exits 0 with no output (no YAML errors).

- [ ] **Step 4: Confirm the service appears in the service list**

```bash
docker compose config --services
```

Expected: `launcher-control` appears in the list alongside `suite_api`, `lava-backend`, etc.

- [ ] **Step 5: Commit**

```bash
git add docker-compose.yml
git commit -m "feat: add launcher-control Docker service and persistent state volumes"
```

---

## Task 4: Add dev override in `docker-compose.dev.yml`

In development, source code changes to `nmtk/launcher_control/` should take effect without rebuilding. A volume mount achieves this.

**Files:**
- Modify: `docker-compose.dev.yml`

---

- [ ] **Step 1: Add the dev override**

The current `docker-compose.dev.yml` content:

```yaml
services:
  suite_api:
    volumes:
      - ./suite_api:/repo/suite_api
    environment:
      - DEBUG=1
```

Replace the entire file with:

```yaml
services:
  suite_api:
    volumes:
      - ./suite_api:/repo/suite_api
    environment:
      - DEBUG=1

  launcher-control:
    volumes:
      # Live-reload: edits to launcher_control/ take effect on container restart.
      - ./nmtk/launcher_control:/app/nmtk/launcher_control
      - ./scripts/launcher_control_service.py:/app/scripts/launcher_control_service.py
      - ./nmtk/neuro_toolkit/assets:/app/nmtk/neuro_toolkit/assets
```

- [ ] **Step 2: Validate the merged compose config**

```bash
cd $HOME/NeuroMorphicToolKit
docker compose -f docker-compose.yml -f docker-compose.dev.yml config --quiet
```

Expected: exits 0 with no output.

- [ ] **Step 3: Commit**

```bash
git add docker-compose.dev.yml
git commit -m "feat: add launcher-control dev override with source mount for live reload"
```

---

## Task 5: Update `run_dev.sh` to stop spawning a local control service in Docker/remote mode

This is the core behavioural change. When `USE_DOCKER=true` or `REMOTE_HOST_IP` is set, `run_dev.sh` must:
1. **Not** call `start_control_api` (Docker Compose owns it)
2. Point Flutter at the containerised control service instead

**Files:**
- Modify: `scripts/run_dev.sh`

---

- [ ] **Step 1: Add a `wait_for_control_api` helper function**

After the existing `wait_for_suite_api` function (ends around line 150), add:

```bash
wait_for_control_api() {
  local url="$1"
  local timeout_secs=90
  local start
  start=$(date +%s)

  echo "==> Waiting for launcher control API at $url (timeout ${timeout_secs}s)..."
  while true; do
    local elapsed=$(( $(date +%s) - start ))
    if [ "$elapsed" -ge "$timeout_secs" ]; then
      echo "==> Launcher control API did not become ready within ${timeout_secs}s; continuing" >&2
      return 0
    fi

    if "$PYTHON3" - "$url" 2>/dev/null <<'PY'
import sys, urllib.request, urllib.error
try:
    urllib.request.urlopen(sys.argv[1] + "/health", timeout=2)
    sys.exit(0)
except Exception:
    sys.exit(1)
PY
    then
      echo "==> Launcher control API is ready"
      return 0
    fi
    sleep 2
  done
}
```

- [ ] **Step 2: Replace the `start_control_api` / `wait_for_suite_api` block**

Find the section of `run_dev.sh` that currently reads (approximately lines 288–306):

```bash
CONTROL_API_URL=""
# Only reserve suite api port if NOT using docker and NOT using remote host
if [[ "$USE_DOCKER" == "false" ]] && [[ -z "$REMOTE_HOST_IP" ]]; then
  reserve_suite_api_port
fi

MANAGE_SUITE_API="true"
if [[ "$USE_DOCKER" == "true" ]] || [[ -n "$REMOTE_HOST_IP" ]]; then
  MANAGE_SUITE_API="false"
fi

start_control_api "$CONTROL_API_BIND_HOST" "$MANAGE_SUITE_API" "$REMOTE_HOST_IP"
CONTROL_API_URL="http://$CONTROL_API_PUBLIC_HOST:$CONTROL_API_PORT"

if [[ -z "$REMOTE_HOST_IP" ]]; then
  wait_for_suite_api "$CONTROL_API_URL"
else
  echo "==> Using remote backend at $REMOTE_HOST_IP; skipping local suite_api readiness check."
fi
```

Replace it with:

```bash
CONTROL_API_URL=""

if [[ "$USE_DOCKER" == "true" ]]; then
  # Docker Compose manages both suite_api and launcher-control.
  # Resolve the URL that the Flutter app will use to reach the control service.
  if [[ "$TARGET_PLATFORM" == android* || "$TARGET_PLATFORM" == ios* || "$FLUTTER_DEVICE" == "ios" ]]; then
    CONTROL_API_URL="http://$HOST_IP:${LAUNCHER_CONTROL_PORT:-8091}"
  else
    CONTROL_API_URL="http://localhost:${LAUNCHER_CONTROL_PORT:-8091}"
  fi
  # Docker Compose already started the container; just wait for it to be healthy.
  wait_for_control_api "$CONTROL_API_URL"

elif [[ -n "$REMOTE_HOST_IP" ]]; then
  # Backend is on a remote server (docker-ex targets).
  CONTROL_API_URL="http://$REMOTE_HOST_IP:${LAUNCHER_CONTROL_PORT:-8091}"
  echo "==> Using remote launcher control API at $CONTROL_API_URL"

else
  # Pure local dev — start the control service on this machine as before.
  reserve_suite_api_port
  start_control_api "$CONTROL_API_BIND_HOST" "true" ""
  CONTROL_API_URL="http://$CONTROL_API_PUBLIC_HOST:$CONTROL_API_PORT"
  wait_for_suite_api "$CONTROL_API_URL"
fi
```

- [ ] **Step 3: Update the Flutter `dart-define` block to use `CONTROL_API_URL`**

Find the flutter run section (approximately lines 318–331):

```bash
flutter_args=(
  run
  -d "$FLUTTER_DEVICE"
  --dart-define="NMTK_CONTROL_API_BASE_URL=$CONTROL_API_URL"
  --dart-define="NMTK_CONTROL_API_PORT=$CONTROL_API_PORT"
)
if [[ -n "$SUITE_API_URL" ]]; then
  flutter_args+=(--dart-define="SUITE_API_URL=$SUITE_API_URL")
fi
if [[ -n "$REMOTE_HOST_IP" ]]; then
  flutter_args+=(--dart-define="NMTK_SERVICES_HOST=$REMOTE_HOST_IP")
fi
```

No change needed for the flutter args — `CONTROL_API_URL` is already set correctly by Step 2.

However, add `NMTK_SERVICES_HOST` for Docker mode on mobile so the Flutter app can also reach suite_api directly:

```bash
flutter_args=(
  run
  -d "$FLUTTER_DEVICE"
  --dart-define="NMTK_CONTROL_API_BASE_URL=$CONTROL_API_URL"
  --dart-define="NMTK_CONTROL_API_PORT=${LAUNCHER_CONTROL_PORT:-8091}"
)
if [[ -n "$SUITE_API_URL" ]]; then
  flutter_args+=(--dart-define="SUITE_API_URL=$SUITE_API_URL")
fi
if [[ -n "$REMOTE_HOST_IP" ]]; then
  flutter_args+=(--dart-define="NMTK_SERVICES_HOST=$REMOTE_HOST_IP")
elif [[ "$USE_DOCKER" == "true" ]] && \
     [[ "$TARGET_PLATFORM" == android* || "$TARGET_PLATFORM" == ios* || "$FLUTTER_DEVICE" == "ios" ]]; then
  # Docker on mobile: tell Flutter the host IP for direct suite_api access
  flutter_args+=(--dart-define="NMTK_SERVICES_HOST=$HOST_IP")
fi
flutter "${flutter_args[@]}"
```

- [ ] **Step 4: Verify the script has no syntax errors**

```bash
bash -n $HOME/NeuroMorphicToolKit/scripts/run_dev.sh
```

Expected: exits 0 with no output.

- [ ] **Step 5: Commit**

```bash
git add scripts/run_dev.sh
git commit -m "feat: run_dev.sh no longer spawns local control service when using Docker or remote host"
```

---

## Task 6: End-to-end smoke test — `make docker` on macOS

This verifies the complete flow: Docker starts all containers including `launcher-control`, Flutter connects directly to Docker port 8091, no local Python process needed.

**No code changes — this is a verification task.**

---

- [ ] **Step 1: Start the full Docker stack**

```bash
cd $HOME/NeuroMorphicToolKit
docker compose up --build -d
```

Expected: all services start. `docker compose ps` should show `launcher-control` as healthy.

- [ ] **Step 2: Confirm `launcher-control` container health**

```bash
docker compose ps launcher-control
```

Expected output:
```
NAME                 IMAGE               COMMAND             SERVICE             CREATED             STATUS                    PORTS
nmtk-launcher-control-1  ...          ...    launcher-control  ...     Up X seconds (healthy)  0.0.0.0:8091->8091/tcp
```

- [ ] **Step 3: Confirm the control API responds**

```bash
curl -s http://localhost:8091/health | python3 -m json.tool
```

Expected: JSON with a `status` key, e.g. `{"status": "ok", ...}`.

- [ ] **Step 4: Confirm no local Python control service is running**

```bash
lsof -nP -iTCP:8091 -sTCP:LISTEN
```

Expected: the only listener is Docker's port-forwarding proxy (not a local `python` process).

- [ ] **Step 5: Run `make docker` and confirm Flutter launches with correct API URL**

```bash
make docker
```

Watch the terminal output. You should see:
```
==> Waiting for launcher control API at http://localhost:8091 (timeout 90s)...
==> Launcher control API is ready
==> Starting NeuroToolkit launcher on macos
```

You should **not** see:
```
==> Starting launcher control API on ...
```

- [ ] **Step 6: In the Flutter app, verify the workspace loads**

Open the running Flutter macOS app. The `LauncherBootstrapHost` screen should skip the setup screen and go straight to `NeuroToolkitApp` (the main workspace), confirming `backendDeploymentReady = true` was returned by the containerised control service.

- [ ] **Step 7: Tear down**

```bash
docker compose down
```

---

## Task 7: End-to-end smoke test — `make docker-ex` (remote deployment)

Verifies that `make docker-ex-m REMOTE_HOST=user@<ip>` deploys the full stack to a remote server — including `launcher-control` — and Flutter connects directly to the remote host's port 8091, with no local intermediary.

> **Prerequisites:** You need SSH access to a remote Linux host with Docker installed.

---

- [ ] **Step 1: Deploy to remote**

```bash
make docker-ex-m REMOTE_HOST=user@<remote-ip>
```

Expected terminal sequence:
1. `==> Syncing source code to user@<remote-ip>...`
2. `==> Building all images in parallel on user@<remote-ip>...` (includes `launcher-control`)
3. `==> Starting containers on user@<remote-ip>...`
4. `==> Using remote launcher control API at http://<remote-ip>:8091` (NEW — no local control service)
5. Flutter launches with `--dart-define="NMTK_CONTROL_API_BASE_URL=http://<remote-ip>:8091"`

- [ ] **Step 2: Verify the control API is reachable on the remote IP**

```bash
curl -s http://<remote-ip>:8091/health | python3 -m json.tool
```

Expected: JSON health response from the remote container.

- [ ] **Step 3: Verify the Flutter macOS app loads the workspace from the remote server**

The app should connect to `http://<remote-ip>:8091` and show the main workspace (no setup screen).

- [ ] **Step 4: Tear down remote stack**

```bash
make docker-ex-down REMOTE_HOST=user@<remote-ip>
```

---

## Self-review

**Spec coverage:**
- ✅ Launcher control service runs in Docker (Tasks 2, 3)
- ✅ State persists across container restarts (Task 3 — named volumes)
- ✅ `make docker` works without local Python intermediary (Tasks 5, 6)
- ✅ `make docker-ex` / remote deployment works end-to-end (Tasks 5, 7)
- ✅ Mobile (`make docker-a` / `make docker-i`) gets correct host IP in control API URL (Task 5, Step 2)
- ✅ Dev source-mount override for fast iteration (Task 4)
- ✅ PYNQ/Akida SSH provisioning still works (container includes `openssh-client` + `rsync`)
- ✅ `make dev` (pure local, no Docker) is **unchanged** — falls through to the existing `start_control_api` path

**Placeholder scan:** No TBDs, no "implement later", no "similar to Task N" patterns. All code blocks are complete.

**Type/name consistency:**
- `LAUNCHER_CONTROL_PORT` env var is used consistently in `run_dev.sh` (Tasks 5) and `docker-compose.yml` (Task 3).
- `NMTK_STATE_DIR` / `NMTK_DATA_DIR` env var names match between `config.py` (Task 1), `Dockerfile.control` (Task 2), and `docker-compose.yml` (Task 3).
- `wait_for_control_api` function defined in Task 5 Step 1 and called in Task 5 Step 2 — names match.
