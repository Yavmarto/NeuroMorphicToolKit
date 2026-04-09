# ADR 0012: Self-Hosted CI Runners

## Status
Accepted

## Context
NMTK targets three platforms (macOS ARM64, Windows x64, Linux x64) and requires specific toolchains (Flutter SDK, Python 3.11+, Poetry, platform-specific hardware SDKs). GitHub-hosted runners lack pre-installed neuromorphic toolchains and Apple Silicon hardware.

## Decision
Use self-hosted GitHub Actions runners on all three target platforms. CI workflows use `dorny/paths-filter` for change detection to only run jobs for modified modules. Cross-platform matrix strategies handle platform-specific issues (e.g., `Add Git to PATH` step on Windows, `AGENT_TOOLSDIRECTORY` workaround). Jobs are conditional on change detection: `if: needs.detect-changes.outputs.<module> == 'true'`.

## Consequences
- **Positive:** Self-hosted runners provide exact hardware/OS match for the target platforms; change detection avoids running all module tests on every push.
- **Negative:** Self-hosted runners require manual provisioning, updates, and security hardening; runner unavailability blocks the entire CI pipeline with no automatic fallback.
