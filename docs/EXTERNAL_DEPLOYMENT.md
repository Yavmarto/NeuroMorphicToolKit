# External Deployment Guide (Local Network)

This document outlines how to deploy the NeuroMorphicToolKit (NMTK) backend to an external server or a Kubernetes cluster on your local network.

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

---

## 2. Kubernetes Deployment
**Status:** Implemented in `nmtk/launcher_control`.

The launcher control service can render and apply Kubernetes manifests automatically. You can trigger this through the NMTK Desktop UI or programmatically via the launcher control API.

### Prerequisites
1. **kubectl:** Installed and configured with access to your target cluster.
2. **Cluster Access:** Your kubeconfig context must have permissions to create Namespaces, Deployments, Services, ConfigMaps, and Secrets.
3. **Container Images:** The `suite_api` image must be available in a registry accessible by the cluster (default: `ghcr.io/completed-spoon-6/neurocnl`).

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
