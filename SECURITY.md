# Security scanning and dependency updates

## Automated scans

- `.github/workflows/security-scan.yml` runs on every push/PR to `main`/`dev` and weekly:
  - `pip-audit` against the root project and every `requirements.txt` in the repo. A real, non-ignored finding fails the job and blocks the PR.
  - OWASP Dependency-Check (report only, uploaded as a workflow artifact).
  - A Trivy config scan of every Dockerfile in the repo. A `CRITICAL`/`HIGH` finding fails the job.
- `.github/workflows/release-docker.yml` runs a Trivy image scan on each built image before it is pushed to `ghcr.io`, on every `v*` tag. A `CRITICAL`/`HIGH` finding blocks the push.

## Accepting a known finding

Do not silence a scanner with a blanket suppression. Add the specific ID to the relevant ignore-list, with a comment linking to the issue/PR that accepted the risk:

- Python (`pip-audit`): `.pip-audit-ignore`, one CVE/GHSA ID per line.
- Containers (Trivy, both scans): `.trivyignore`, one CVE/GHSA/AVD ID per line.

## Dependency update review

Dependabot watches `pip`, `pub`, `github-actions`, and `docker` (one entry per Dockerfile directory), all on a weekly schedule (`.github/dependabot.yml`).

- The Engineer agent reviews and merges open Dependabot PRs weekly, batched together rather than per-PR.
- Patch-level version bumps auto-merge once CI passes; no manual review required.
- Minor/major version bumps, and any PR touching a package with an active CVE finding, require Engineer sign-off before merge.
