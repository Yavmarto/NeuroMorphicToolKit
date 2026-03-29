# Root docker-compose.yml Full-Stack Orchestration

This document details the startup ordering dependencies for the root `docker-compose.yml` services.

## Service Startup Dependencies

The root `docker-compose.yml` orchestrates 7 backend services. While most services can start independently, they have the following communication dependencies:

1.  **Independent Services:**
    *   `neurocnl`: Starts on port 8000. No dependencies.
    *   `neurosim`: Starts on port 8001. No dependencies.
    *   `neurochip`: Starts on port 8002. No dependencies.
    *   `neurobench`: Starts on port 8003. No dependencies.
    *   `neurosense`: Starts on port 8004. No dependencies.
    *   `neurocnl-physics`: Starts on port 8006 (requires `physics` profile). No dependencies.

2.  **Dependent Services:**
    *   `neurohub`: Starts on port 8005. Acts as the orchestration layer.
        *   **Dependency:** Depends on `neurocnl`, `neurosim`, `neurochip`, `neurobench`, and `neurosense` to be healthy before it fully initializes its cross-app communication features.
        *   **Condition:** Configured with `depends_on: ... condition: service_healthy` in `docker-compose.yml` to ensure it waits for the underlying services to pass their health checks.

## Environment Config Overlay

*   **`docker-compose.dev.yml`**: Mounts local directories as volumes into the containers to allow hot-reloading of code without rebuilding the Docker images. Sets `DEBUG=1`.
*   **`docker-compose.prod.yml`**: Configures restart policies (`always`), sets `read_only: true` file systems with specific `tmpfs` mounts, drops all capabilities (`cap_drop: ALL`), and applies security options (`no-new-privileges:true`) for production-grade security hardening. Sets `PYTHONOPTIMIZE=1`.
