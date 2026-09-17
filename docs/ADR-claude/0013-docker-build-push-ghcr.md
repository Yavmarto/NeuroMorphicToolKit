# ADR 0013: Docker Build and Push to GHCR

## Status
Accepted

## Context
NMTK modules are distributed as Docker images for deployment in lab environments, CI pipelines, and production. Images must be versioned, discoverable, and hosted on a registry accessible to all team members.

## Decision
Use GitHub Container Registry (ghcr.io) for Docker image hosting. The `release-docker.yml` workflow uses `docker/build-push-action` to build images for each module. Images are tagged with both the semantic version (`v1.2.3`) and the git SHA short hash for precise identification. Special handling exists for variant builds (e.g., `neurocnl-physics` with MuJoCo dependencies).

## Consequences
- **Positive:** GHCR integrates natively with GitHub authentication and repository permissions; dual tagging enables both release management and exact commit traceability.
- **Negative:** GHCR has no built-in image retention/cleanup policy, leading to storage growth over time; multi-arch builds require Docker Buildx setup on all CI runners.
