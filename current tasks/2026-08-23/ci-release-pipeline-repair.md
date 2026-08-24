# CI/CD release pipeline repair — 2026-08-23

## Starting state

- `gh api repos/:owner/:repo/actions/runners` → `total_count: 0`. One runner
  (a MacBook Pro) is registered at the **org** level; Windows and Linux runners
  do not exist yet.
- Every workflow declared `runs-on: self-hosted`, so runs sat `queued` for 24 h
  and were cancelled. The nightly Akida manifest gate had been queued 17 h.
- The GHCR images are already published, so the Docker path had been run some
  other way.

## Done

Release path now works with zero self-hosted hardware, and moves in-house one
platform at a time via repository variables.

- Runner selection: `RELEASE_RUNNER_{LINUX,WINDOWS,MACOS,DOCKER}` repository
  variables, GitHub-hosted fallbacks. Applied to `release-desktop.yml`,
  `release-docker.yml`, `release-promote.yml`, `verify-akida-manifest.yml`.
- `release-desktop.yml` rewritten: new `version` job resolves the version once
  (tag, else pubspec) and feeds every platform; Inno Setup installed on hosted
  Windows; broken duplicate signing step removed; `prerelease` expression
  interpolated; SHA256SUMS added; `if-no-files-found: error` on every upload.
- Signing secrets moved to job-level `env` — a step's own `env` is invisible to
  its own `if`, so signing had been skipped on every release.
- `build-standalone.ps1` takes `-Version` and passes `/DMyAppVersion` to ISCC
  (installers were all named 1.0.0).
- `build-standalone.sh` takes `--version` instead of the hardcoded `"dev"`
  (DMGs were all named `-dev-`).
- `release-promote.yml`: submodule step now gets `VERSION` (it was tagging with
  an empty string and swallowing the error), and checkout uses
  `NMTK_SUBMODULE_TOKEN` — `GITHUB_TOKEN` cannot touch sibling repos.
- `release-docker.yml`: disk-reclaim step for hosted runners (torch images do
  not fit in the default ~14 GB).
- `neurocli` added to `release.sh` version bumps; wheel + sdist now built and
  attached to the release.
- Wake-on-LAN runner design: `scripts/ci/runner-wake.sh` (poller for the
  always-on box), `scripts/ci/runner-idle-suspend.sh` (WSL2-aware host
  suspend), systemd units, and `docs/ci-runners.md`.

## Not done / needs a decision

- `ci.yml` (890 lines) and `nmtk-ci.yml` still target `self-hosted` across
  mac/win/linux matrices. Moving those to hosted runners would be the expensive
  part of the minutes bill; left alone deliberately.
- Android APK/AAB: needs an upload keystore in secrets.
- iOS: GitHub Releases cannot distribute a signed iOS build — TestFlight only.
- Web: 13 `lib/` files import `dart:io`, so `flutter build web` cannot compile.
- No `.deb`/`.rpm`, only the AppImage.

## Verification

- All four workflow files parse (`yaml.safe_load`).
- `bash -n` clean on the new scripts and the edited macOS installer script.
- `tests/test_windows_installer_signing.py`, `tests/test_macos_installer_signing.py`
  → 11 passed, 4 skipped (skips need pwsh, absent on this Mac).
- jq label filter and the WoL packet builder exercised directly with fixtures.
- Not verified: no actual tagged release has been run since the change, and the
  PowerShell edit is unexecuted (no pwsh locally).
