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
- `make docker-ex REMOTE_HOST=user@192.168.1.50` -> Deploys the backend only.
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
**Status:** In Development (Architecture defined in `nmtk/launcher_control`).

The project is currently building a "First-Run" wizard that will handle Kubernetes deployments natively. If you wish to deploy manually now:

### Manual Steps
1. **Create Manifests:** Define `Deployment` and `Service` resources for `suite_api` (port 9000).
2. **Context:** Ensure your local `kubectl` context is set to your local network cluster.
3. **Execute:**
   ```bash
   kubectl create namespace nmtk-backend
   kubectl apply -f ./k8s/ -n nmtk-backend
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
