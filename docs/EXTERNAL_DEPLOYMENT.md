# External Deployment Guide (Local Network)

This document outlines how to deploy the NeuroMorphicToolKit (NMTK) backend to an external server or a Kubernetes cluster on your local network.

> **App-driven setup (source-free).** The NMTK desktop app sets up a remote
> Docker backend by copying only `docker-compose.yml` + `docker-compose.prod.yml`
> (+ `monitoring/`) to the server and running `docker compose pull && up -d
> --remove-orphans`, then verifies the required Suite API health endpoint. It
> pulls prebuilt images from GHCR, no repo or `make` on the server. This
> requires the images to be published and public first; see
> [PUBLISHING_IMAGES.md](PUBLISHING_IMAGES.md). The `make docker-ex*` targets
> below remain the source-build path for development.

### App-driven remote setup

The normal end-user flow is **Set up a new server** in the NMTK app:

1. Enter the server's IPv4 address and a root/sudo administrator credential.
2. Choose Docker or Podman.
3. Select **Set up and connect**.

The administrator credential is used once over SSH and is never saved. The app
removes NMTK-owned containers left by either Docker or Podman, preserves
notebooks/databases/workspace data, installs the selected engine when needed,
creates a dedicated `nmtk-deploy` account, starts the stack, and connects only
after Suite API, launcher control, and NeuroStudio are reachable from the
client.

Setup becomes a tracked job before the first administrator SSH command. Select
**View raw SSH output** at any time to follow the exact command plus the
sanitized stdout and stderr returned by the server. Successful commands do not
receive invented result messages; nonzero exits and timeouts are identified as
client metadata. Stdout and stderr are shown live but captured separately:
only validated stdout identifiers can drive container or volume cleanup, so a
Podman warning on stderr can never become an `rm` argument. The retained
transcript is bounded to 2,000 lines or 512 KB,
with an explicit truncation notice, and **Copy output** is safe to share
because protocol markers, administrator passwords, private keys, and generated
deployment credentials are never added to it. If preparation fails while an
older deployment remains reachable, the app keeps that connection and
identifies it separately from the failed reinstall attempt.

Runtime probes stop after 20 seconds, container inspection and removal after 60
seconds, account and socket setup after 30 seconds, and package installation
after 5 minutes. The complete administrator session stops after 12 minutes, and
Cancel closes the active administrator SSH session. While a command is silent,
the status card names it and shows how long no new server output has arrived.

Nothing may stall silently. The administrator script announces its own exit
rather than relying on the SSH channel closing, because preparing rootless
Podman deliberately leaves lingering processes that hold that channel open. Any
other silence — including between steps — fails the attempt after 90 seconds.
Once the compose bundle is running on the host, `install.sh` bounds each long
step (stop 5 minutes, image download 20 minutes, start 10 minutes) and the image
download republishes its elapsed time so the app can tell slow from dead. The
app gives up on a deployment that reports no new progress for three minutes, or
twenty-five while images download, and offers **Retry setup** — which keeps the
address, engine, and factory-reset choice and asks only for the administrator
password again.

**Factory reset server data** is a separate destructive option. It requires
confirmation and removes NMTK-owned volumes in addition to containers; leave it
off for normal reinstalls and engine switches. The option turns itself off
after each confirmed submission so a retry cannot erase data accidentally.

## 1. Docker Deployment (SSH-based)
**Status:** Highly Recommended for quick setup.

The NMTK backend is already containerized. You can use Docker's SSH context to deploy directly to a server without manually copying files (though `rsync` is recommended for build contexts).

### Makefile Implementation
Add the following to your root `Makefile`:

```makefile
# Deployment variables (can be overridden on command line)
REMOTE_HOST ?=
DEPLOY_DIR ?= ~/nmtk-deploy

docker-ex:
	@if [ -z "$(REMOTE_HOST)" ]; then \
		echo "Error: REMOTE_HOST is not set. Example: make docker-ex REMOTE_HOST=user@192.168.1.50"; \
		exit 1; \
	fi
	@echo "==> Syncing source code to $(REMOTE_HOST)..."
	ssh $(REMOTE_HOST) "mkdir -p $(DEPLOY_DIR)"
	rsync -avz --exclude '.git' --exclude '.env' . $(REMOTE_HOST):$(DEPLOY_DIR)
	@echo "==> Starting Docker containers on $(REMOTE_HOST)..."
	ssh $(REMOTE_HOST) "cd $(DEPLOY_DIR) && docker compose up --build -d"
	@echo "==> Backend deployed. Access it at http://$$(echo $(REMOTE_HOST) | cut -d@ -f2):9000"

docker-ex-m: docker-ex
	@./scripts/run_dev.sh --flutter-device macos --remote-host "$$(echo $(REMOTE_HOST) | cut -d@ -f2)"

docker-ex-a: docker-ex
	@$(MAKE) check-devices
	@echo "==> Using Android device: $(ANDROID_DEVICE)"
	@./scripts/run_dev.sh --flutter-device "$(ANDROID_DEVICE)" --remote-host "$$(echo $(REMOTE_HOST) | cut -d@ -f2)"

docker-ex-i: docker-ex
	@$(MAKE) check-devices
	@echo "==> Using iOS device: $(IOS_DEVICE)"
	@./scripts/run_dev.sh --flutter-device "$(IOS_DEVICE)" --remote-host "$$(echo $(REMOTE_HOST) | cut -d@ -f2)"
```

**How to use:**
- `make docker-ex REMOTE_HOST=user@192.168.1.50` -> Deploys the full backend stack (same as `docker-ex-all`: all workers, Jupyter, monitoring). Re-runs sync changed files and `docker compose up --build` rebuilds images whose sources changed.
- `make docker-ex-m REMOTE_HOST=user@192.168.1.50` -> Deploys the backend, then launches the macOS Flutter desktop app pointing to it.
- `make docker-ex-a REMOTE_HOST=user@192.168.1.50` -> Deploys the backend, then launches the Android Flutter app pointing to it.
- `make docker-ex-i REMOTE_HOST=user@192.168.1.50` -> Deploys the backend, then launches the iOS Flutter app pointing to it.
- `make docker-ex-down REMOTE_HOST=user@192.168.1.50` -> Stops and removes the Docker containers on the remote host.

### Prerequisites
1. **SSH Access:** Ensure you have SSH key-based authentication set up to the target server.
2. **Server Tools:** The target server must have `docker` and the `docker-compose-plugin` installed.
3. **Network:** Both machines should be on the same local network subnet.

### Using Podman instead of Docker

Every `docker-ex*`/`deploy-prod` Makefile target and `scripts/run_dev.sh --docker`
accept a `CONTAINER_ENGINE` override (default `docker`):

```bash
make docker-ex-deploy REMOTE_HOST=user@192.168.1.50 CONTAINER_ENGINE=podman
make deploy-prod       REMOTE_HOST=user@192.168.1.50 CONTAINER_ENGINE=podman
./scripts/run_dev.sh --container-engine podman --flutter-device macos
```

- The target server needs **Podman + a Compose provider** installed. The NMTK
  client installs Podman when needed, starts the SSH user's rootless
  `podman.socket`, and routes the Compose provider through
  `unix:///run/user/<uid>/podman/podman.sock`; no rootful Docker daemon is
  required.
- Rootless Podman uses a per-user systemd socket. For manual diagnostics, run
  `systemctl --user enable --now podman.socket` as the deploy user and set
  `DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock` before invoking
  Compose. SSH-only service accounts may also need
  `sudo loginctl enable-linger <username>`.
- The published GHCR images are plain OCI images, so `docker-compose.prod.yml`'s
  `image:` pull path works unmodified under Podman.
- `remote-setup`'s sudoers rules (`fuser`, `systemctl`, the Akida key script)
  never touch Docker itself, so rootless Podman needs no extra sudoers entries.
- The stack is CPU-only and Linux/amd64-only either way — nothing here is
  Docker-Desktop-specific except `host.docker.internal`, which is already
  wired through a plain `extra_hosts: host-gateway` entry that Podman also
  understands.
- Remote deployments include `docker-compose.remote.yml`. It keeps the
  internal worker ports (including Lava on `8012`) private on the Compose
  network, so an existing native service or stale rootless-port helper cannot
  block startup. Only the client-facing Suite API (`9000`), launcher control
  API (`8090`), and Jupyter (`8008`) remain published for the Flutter app.
- Before Compose startup, the launcher probes the client-facing ports and
  removes only containers carrying the current or legacy NMTK Compose project
  labels across Docker and Podman, including rootless Podman installations
  owned by an earlier deployment account. It then runs the project-scoped
  `compose down --remove-orphans` without removing volumes, so stale NMTK
  bindings are released without stopping unrelated containers. Cleanup
  failures block startup instead of being ignored. If a remaining client-facing
  port is owned by another service, the deployment log identifies its runtime,
  Compose project, container, and listening process.
- Remote startup does not use a global Compose `--wait`, because that would
  turn an optional Lava healthcheck failure into a core deployment failure.
  Suite API readiness is checked separately; the deployment log records Lava
  as degraded when its health history or direct `/health` probe is unavailable.

---

## 2. Kubernetes Deployment
**Status:** Implemented in `nmtk/launcher_control`.

The launcher control service can render and apply Kubernetes manifests automatically. You can trigger this through the NMTK Desktop UI or programmatically via the launcher control API.

### Prerequisites
1. **kubectl:** Installed and configured with access to your target cluster.
2. **Cluster Access:** Your kubeconfig context must have permissions to create Namespaces, Deployments, Services, ConfigMaps, and Secrets.
3. **Container Images:** The `suite_api` image must be available in a registry accessible by the cluster (default: `ghcr.io/completed-spoon-6/neuromorphictoolkit/suite-api`).

### Via Launcher Control API
1. **Create a Kubernetes target:**
   ```bash
   curl -X POST http://localhost:8091/api/launcher/deployment/targets \
     -H "Content-Type: application/json" \
     -d '{
       "displayName": "Production K8s",
       "targetType": "kubernetes_cluster",
       "mode": "kubernetes",
       "namespace": "nmtk-backend",
       "context": "production",
       "backendPort": 9000,
       "imageTag": "latest",
       "authMode": "kubeconfig"
     }'
   ```

2. **Run preflight:**
   ```bash
   curl -X POST http://localhost:8091/api/launcher/deployment/preflight \
     -H "Content-Type: application/json" \
     -d '{"targetId": "<target-id>"}'
   ```

3. **Start deployment job:**
   ```bash
   curl -X POST http://localhost:8091/api/launcher/deployment/jobs \
     -H "Content-Type: application/json" \
     -d '{"targetId": "<target-id>"}'
   ```

4. **Stream progress:**
   ```bash
   curl http://localhost:8091/api/launcher/deployment/jobs/<job-id>/events
   ```

### Manual Manifest Generation
If you prefer to manage manifests yourself, the launcher control renderer can generate them:

```python
from pathlib import Path
from nmtk.launcher_control.deployment_contracts import DeploymentTarget
from nmtk.launcher_control.deployment_k8s_renderer import render_manifests, write_manifests

target = DeploymentTarget(
    id="manual-k8s",
    display_name="Manual K8s",
    target_type="kubernetes_cluster",
    mode="kubernetes",
    namespace="nmtk-backend",
    backend_port=9000,
    image_tag="v1.0.0",
)

manifests = render_manifests(target, app_name="nmtk-suite-api")
write_manifests(manifests, Path("./k8s-output"))
```

Then apply:
```bash
kubectl apply -f ./k8s-output/
```

---

## 3. Project Context & Roadmap

The toolkit is moving towards an automated deployment flow managed by `launcher_control`.

- **Key Plan:** `docs/archive/2026-05-04-first-run-backend-deployment-standalone-docker-kubernetes-plan.md`
- **Current Backend Orchestrator:** `nmtk/launcher_control/deployment_service.py`
- **Deployment Models:** `nmtk/launcher_control/deployment_contracts.py`

Once the `launcher_control` executors are finalized, you will be able to configure these targets directly through the NMTK Desktop UI.

---

## 4. Verification
After deployment, verify the backend health:

```bash
curl http://<SERVER_IP>:9000/api/suite/health
```
If you see `{"suiteApiStatus": "ready"}`, your external deployment is successful.
