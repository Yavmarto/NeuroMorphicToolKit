# Security scanning and dependency updates

## Automated scans

- `.github/workflows/security-scan.yml` runs on every push/PR to `main`/`dev` and weekly:
  - `pip-audit` against the root project and every `requirements.txt` in the repo. A real, non-ignored finding fails the job and blocks the PR.
  - A Trivy filesystem scan (`scan-type: fs`, `scanners: vuln`) of every language dependency file in the repo, including `pubspec.lock` (Dart). A `CRITICAL`/`HIGH` finding fails the job.
  - A Trivy config scan of every Dockerfile in the repo. A `CRITICAL`/`HIGH` finding fails the job.
- `.github/workflows/release-docker.yml` runs a Trivy image scan on each built image before it is pushed to `ghcr.io`, on every `v*` tag. A `CRITICAL`/`HIGH` finding blocks the push.

## Scanner coverage

| Ecosystem | Gate (fails the job) | Updater |
| --- | --- | --- |
| Python (`requirements.txt`, installed project) | `pip-audit`, Trivy fs | Dependabot `pip` |
| Dart/Flutter (`pubspec.lock`) | Trivy fs | Dependabot `pub` |
| Container base images | Trivy config, Trivy image | Dependabot `docker` |
| GitHub Actions | none (update-only) | Dependabot `github-actions` |

## Accepting a known finding

Do not silence a scanner with a blanket suppression. Add the specific ID to the relevant ignore-list, with a comment linking to the issue/PR that accepted the risk:

- Python (`pip-audit`): `.pip-audit-ignore`, one CVE/GHSA ID per line.
- Trivy (filesystem, Dockerfile config, and image scans): `.trivyignore`, one CVE/GHSA/AVD ID per line.

## Dependency update review

Dependabot watches `pip`, `pub`, `github-actions`, and `docker` (one entry per Dockerfile directory), all on a weekly schedule (`.github/dependabot.yml`).

- The Engineer agent reviews and merges open Dependabot PRs weekly, batched together rather than per-PR.
- Patch-level version bumps auto-merge once CI passes; no manual review required.
- Minor/major version bumps, and any PR touching a package with an active CVE finding, require Engineer sign-off before merge.

## Decision log

### Removed OWASP Dependency-Check (2026-09-17, CEL-315)

The `owasp-dependency-check` job was removed from `security-scan.yml`. It was neither actionable nor working:

- **It gated nothing.** It produced an HTML artifact and its exit code was never read, so no merge was blocked.
- **It could not run.** It pinned `dependency-check/DependencyCheck_Action@v3`. The action's real repository is `dependency-check/Dependency-Check_Action` and it has no `v3` ref (latest is `1.1.0`), so the job failed at action resolution before doing any work.
- **It was noise by construction.** `--enableRetired` includes retired and withdrawn CVEs.
- **It needed NVD API access.** Since Dependency-Check 9.x the NVD data feed moved to the API. That is rate-limited and "extremely slow" without an `NVD_API_KEY`, which would add a new secret and a caching strategy to an otherwise gate-less job.

Coverage is not lost. Dependency-Check's relevant analyzers here are Python and Dart. Python stays gated by `pip-audit` (which also resolves the installed project and supports the per-ID accept-list); Dart/`pubspec.lock` is now gated by the Trivy filesystem scan, and Dependabot `pub` raises update PRs. Container and Actions coverage is unchanged.
