# ADR 0004: Headless CI Integration

## Status
Accepted

## Context
Automated CI/CD pipelines need to scaffold, build, test, and deploy neuromorphic projects without GUI interaction. Interactive prompts, browser-based auth, and GUI-dependent features are incompatible with headless CI environments.

## Decision
Design all neurocli commands to be fully non-interactive with meaningful exit codes, optional JSON output mode for machine parsing, and environment variable configuration for all settings. This enables integration into GitHub Actions, GitLab CI, and local automation scripts alongside the monorepo's existing `test-workflows.sh` and `scripts/git/push-all.sh` scripts.

## Consequences
- **Positive:** Non-interactive design with JSON output enables straightforward CI pipeline integration; exit code conventions allow conditional pipeline logic.
- **Negative:** Non-interactive mode cannot handle edge cases that require user judgment; JSON output adds serialization overhead and must be maintained alongside human-readable output.
