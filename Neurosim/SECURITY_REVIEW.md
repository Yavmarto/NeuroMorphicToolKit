# Manual Security Review for Docker Hardening

## 1. Pinned Base Images
- **Backend (Dockerfile):** The base image `python:3.11-slim` has been pinned using a specific digest `sha256:9358444059ed78e2975ada2c189f1c1a3144a5dab6f35bff8c981afb38946634`.
- **Frontend (frontend/Dockerfile):**
    - Build stage: `ghcr.io/cirruslabs/flutter:3.27.0` pinned with digest `sha256:3aa235f10b9700466ee5fc92ece03e867c336168ead60ef7449480a38c6cd92e`.
    - Serving stage: `ghcr.io/nginxinc/nginx-unprivileged:1.25-alpine` pinned with digest `sha256:8265b1df5a89cc1a0a067e472bf47aca7cee52f0561c98a0dff91312dcdd8adb`.

## 2. Resource Limits
- Resource limits have been added to the `docker-compose.yml` for both the `backend` and `frontend` services:
    - CPU limit: `0.50`
    - Memory limit: `512M`

## 3. Multi-stage Builds
- The frontend now uses a multi-stage Docker build to separate the build environment (Flutter SDK) from the runtime environment (minimal Nginx server), significantly reducing the final image size and attack surface.

## 4. Non-root Execution
- **Backend:** A non-root user `neurosim` has been created and configured as the execution user in the `Dockerfile`.
- **Frontend:** The `nginx-unprivileged` base image is used, which is pre-configured to run as a non-root user and listen on an unprivileged port (8080).

## 5. Observations & Recommendations
- **Scanning Tools:** No automated scanning tools (Trivy, Snyk, Docker Scout) were available in the current environment to perform an automated vulnerability scan. A manual review was performed instead, focusing on image pinning, non-root execution, and resource management.
