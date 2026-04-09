# ADR 0011: Release Versioning Strategy

## Status
Accepted

## Context
The NMTK monorepo must coordinate releases across 10+ modules with independent version numbers, Flutter `pubspec.yaml` versions, Python `pyproject.toml` versions, and Docker image tags. Manual version bumping across all files is error-prone and leads to version drift.

## Decision
Use `scripts/release.sh` to orchestrate the release process, which calls `scripts/bump_all.py` to synchronize version numbers across all `pubspec.yaml` and `pyproject.toml` files in the monorepo. Docker images are tagged with both the semantic version and the git SHA short hash via `release-docker.yml`. The `push-all.sh` script commits and pushes version bumps atomically across all submodule repositories.

## Consequences
- **Positive:** Automated version synchronization prevents drift between module versions; dual Docker tagging (semver + SHA) enables both human-readable and precise artifact identification.
- **Negative:** Atomic cross-submodule pushes can partially fail, leaving repositories in inconsistent states; no automated rollback if a release is found to be broken after push.
