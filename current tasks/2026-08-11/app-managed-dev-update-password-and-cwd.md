# App-managed dev update password and working-directory failure

## Debug report

- **Symptom:** `make dev-update` asked for an unexplained password, accepted it,
  then printed `cannot chdir to /home/moosebun2` and could not find the
  app-managed launcher container.
- **Root cause:** The app runs the released Podman stack under the isolated
  `nmtk-deploy` account. The developer updater therefore needs a narrow
  privilege handoff, but its helper inherited the private SSH user's home as
  its working directory, so `runuser` failed before Podman could start.
- **Fix:** The helper changes to `/` before dropping privileges. Its first
  authorized run installs a root-owned, versioned helper and a sudo rule that
  permits only that helper; later updates use it non-interactively.
- **User contract:** The one-time prompt explicitly names the remote Linux
  account whose sudo password is required. Unreleased source is tested with
  `make dev-update`; GHCR plus the in-app update remains the released-image
  path.
- **Evidence:** The regression failed with the original `cannot chdir` message
  before the fix and now passes. All 12 focused tests, 271 launcher tests, and
  182 Flutter tests pass; launcher doctor reports `fatalCount: 0`.
- **Fresh reproduction:** The real update rebuilt `launcher-control` and
  reached the explicit one-time `moosebun2` password prompt without the former
  directory failure. The run was stopped at the prompt because credentials
  must be entered by the user directly, never shared with an agent.
- **Status:** DONE_WITH_CONCERNS — code and tests are complete; the existing dev
  host still needs the user's one-time sudo authorization to install the
  passwordless helper.

## Follow-up: false health failure after the first authorized update

- **Symptom:** The rebuilt launcher started, waited silently, then was rolled
  back as unhealthy even though no launcher traceback was shown.
- **Root cause:** On Podman 5.7, `podman compose` delegates to the external
  Docker Compose plugin. That provider changed the array health command from
  `python -c "import urllib.request; ..."` into separate arguments, so every
  scheduled health check failed while `http://127.0.0.1:8091/health` returned
  HTTP 200 and the launcher logs showed a normal startup.
- **Fix:** The privileged update helper now checks each service's real HTTP
  endpoint from inside the container instead of trusting the corrupted Podman
  health metadata. A genuine failure now prints bounded container state and
  logs before rollback.
- **Evidence:** An isolated Podman Compose project reproduced the corrupted
  health command and simultaneously returned HTTP 200 from the launcher. The
  regression test first failed by rolling back that condition, then passed
  after direct endpoint probing; 12 focused tests, 271 launcher tests, and 182
  Flutter tests pass, with launcher doctor `fatalCount: 0`.
- **Status:** DONE_WITH_CONCERNS — the existing host has helper v1, so installing
  helper v2 requires one final sudo authorization before later updates remain
  passwordless.
