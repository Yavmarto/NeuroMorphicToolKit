# ADR 0015: Container Security Hardening

## Status
Accepted

## Context
NMTK containers may run in shared lab environments with access to physical neuromorphic hardware (Teensy, PYNQ boards). Container escape or privilege escalation could compromise expensive hardware and sensitive research data.

## Decision
The production Docker Compose (`docker-compose.prod.yml`) enforces: read-only root filesystem (`read_only: true`), ephemeral temp directories (`tmpfs: [/tmp, /run]`), no privilege escalation (`security_opt: [no-new-privileges:true]`), and all Linux capabilities dropped (`cap_drop: [ALL]`). All service Dockerfiles use non-root users (`appuser`, `neurosim`, etc.) with explicit UID/GID. Secrets (API keys, JWT secrets) are injected via environment variables, not baked into images.

## Consequences
- **Positive:** Defense-in-depth approach limits blast radius of container compromise; non-root execution with dropped capabilities follows container security best practices.
- **Negative:** Read-only filesystem requires explicit tmpfs mounts for any write operations; secret injection via environment variables is visible in `docker inspect` and process listings.
