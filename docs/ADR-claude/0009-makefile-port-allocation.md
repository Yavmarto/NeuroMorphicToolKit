# ADR 0009: Makefile Port Allocation

## Status
Superseded by ADR 0018 (suite_api unified backend)

## Supersession note
Ports 8000–8005 were the per-module port assignments under the old
module-as-app architecture. After Phase 2 of the consolidation plan,
all modules are served by suite_api on port 9000. The legacy ports are
retained only for optional hardware/compute workers (Phase 4). This ADR
remains for historical reference.

## Context
The NMTK desktop launcher starts 6 backend services simultaneously on the same machine. Each service needs a unique, predictable port for the launcher to connect to and for inter-service communication (e.g., Neurohub health-checking all other services).

## Decision
Allocate fixed ports via the Makefile: neurocnl=8000, Neurosim=8001, Neurochip=8002, Neurobench=8003, Neurosense=8004, Neurohub=8005. These ports are embedded in `build_all_frontends.sh` via `--dart-define=API_BASE_URL`, in Docker Compose service definitions, in the desktop launcher's module manifest, and in Neurohub's suite client defaults. The Makefile orchestrates `make dev` (build submodules + run launcher) and per-module targets.

## Consequences
- **Positive:** Fixed port allocation eliminates dynamic discovery complexity; the same ports work across local development, Docker Compose, and CI.
- **Negative:** Fixed ports conflict if any other application uses ports 8000-8005; no mechanism for running multiple NMTK instances on the same machine.
