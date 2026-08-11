# New server setup aborted with "cannot chdir to /home/moosebun2"

Date: 2026-08-10
Status: fixed, tests green

## Symptom

Setting up a server from Backend Setup with sudo credentials died in
`Removing existing NMTK containers`:

```
$ runuser -u nmtk-deploy -- env HOME=/home/nmtk-deploy XDG_RUNTIME_DIR=/run/user/1001 podman info --format ...
cannot chdir to /home/moosebun2: Permission denied
[client: command exited 1]
```

UI showed "Podman installations could not be inspected" and told the user to
"review the named user in the terminal output" — text that never reached the
transcript.

## Root cause

The whole root bootstrap script is piped into `sudo -S -p "" bash`
(`administratorShellCommand`), so the root shell inherits the SSH login's
directory: the administrator's home, mode 0750 on Ubuntu 21.04+. The
`/etc/passwd` sweep then drops privileges with `runuser -u "$candidate" -- env
… podman info`. `runuser` does not chdir, so it refused before exec'ing anything
and exited 1. `capture_step` had no soft-fail path, so this ended the run with
`podman_inspection_failed` (exit 29) in `reconciling_existing_install` — strictly
upstream of `useradd nmtk-deploy`, so the deploy account and its key handoff
never happened.

`runuser -u moosebun2` a few lines earlier in the same log succeeded: that
account owns the directory. `nmtk-deploy` only becomes a sweep candidate after a
previous deploy populated its container storage, so this hit re-setup / retry /
factory-reset of an already-used host.

## Fix

`nmtk/neuro_toolkit/lib/services/deployment/client_deployment_service.dart`

1. `cd /` immediately after `set -euo pipefail` in `buildRemoteBootstrapScript`.
   Must be there, not on the `runuser` line — `runuser` fails before exec'ing
   `env`, so `env --chdir=/` would be too late. Covers all three privilege-drop
   sites. Verified nothing in the script uses a relative path.
2. `capture_step` split into `run_capture_step` (records `STEP_EXIT`, judges
   nothing) + `capture_step` (hard fail, unchanged signature) +
   `capture_optional_step` (reports failure to the caller). New `inspect_step`
   routes read-only inspection through the tolerant variant while
   `RUNTIME_SWEEP_OPTIONAL=1`. The `/etc/passwd` loop now skips and names an
   unreadable account instead of ending setup; destructive `rm` / `volume rm`
   steps, the root-level sweep, and everything from `installing_prerequisites`
   onward stay strict.
3. `podman_inspection_failed` copy rewritten (the old text pointed at filtered
   terminal output). `_bootstrapFailureDetails` now prepends the server's own
   sentence to `recovery` when it names an account.

`nmtk/launcher_control/provisioning_helpers.py`

4. Same latent bug in `_akida_install_script_text`: `sudo_cmd -u "$SERVICE_USER"`
   also preserves cwd and CPython calls `getcwd()` at startup. Added `cd /`
   *after* `BUNDLE_DIR` is resolved from `${BASH_SOURCE[0]}` (order matters —
   BUNDLE_DIR may be relative).

## Traps worth remembering

- `validated_container_ids` / `validated_volume_names` run inside `$( )`, so
  their `fail` → `exit 29` only exits the subshell. A naive `|| return 1` there
  turns exit 29 into exit 1. Both call sites now re-raise the real code and only
  `return 1` in tolerant mode.
- A function invoked in a `||` context has `set -e` and the ERR trap disabled
  throughout its body. Hard failures inside still work only because `fail`
  calls `exit` explicitly.
- `NMTK_SETUP_TERMINAL|` lines are dropped by `_bootstrapTranscriptLine` (pinned
  by test). Anything the user must read has to be plain stdout or reach
  `summary`/`recovery` — those are the only two fields the UI renders.

## Tests

`test/services/client_deployment_service_test.dart`

- Fake `runuser` now refuses when `$PWD != /` (`NMTK_FAKE_REQUIRE_ROOT_CWD`) and
  exports `NMTK_FAKE_VIA_RUNUSER` so the fake `podman` can fail for the
  candidate or for root independently. Fixture runs with an explicit non-`/`
  `workingDirectory`.
- New: privilege drops do not inherit the administrator home (confirmed failing
  with the exact production message when `cd /` is removed); an unreadable
  account is skipped instead of failing setup; the server's own unreadable
  Podman still stops setup with exit 29.
- Rewrote "unsafe active Podman runtime ownership" — now asserts skip + naming
  instead of exit 29, and still asserts `runuser` never touched that account.

Full `flutter test` in `nmtk/neuro_toolkit`: 182 passed.
`pytest tests/launcher_control -p no:nengo -k "akida or provision or bootstrap"`:
103 passed.

## Follow-up 2026-08-11: image pull had no retry

Confirmed fixed on the real host — `runuser -u nmtk-deploy … podman info` succeeded,
`nmtk-deploy` was created, deploy reached the image pull. It then failed there:

```
unable to copy from source docker://…/snn-mlir-compiler:latest: writing blob:
adding layer with blob "sha256:24dba2149b7b…": unpacking failed
(error: pigz: skipping: <stdin>: corrupted -- crc32 mismatch: exit status 1)
```

Verified the published blob is fine — fetched it anonymously from GHCR: 68,001,087
bytes, sha256 matches the manifest, `gzip -t` clean. So the layer was damaged in
transit, not at the registry. `install.sh` ran `compose pull` exactly once and
turned any failure into `fail_stage`, with no way for an end user to retry.

`nmtk/neuro_toolkit/assets/deployment/install.sh` — the pull now runs up to
`NMTK_DEPLOY_PULL_ATTEMPTS` (3) times with `NMTK_DEPLOY_PULL_RETRY_DELAY` (5s)
between attempts. Already-downloaded layers are reused, so a retry costs only the
damaged image. A timeout (exit 124) is still not retried: it already spent the
whole budget. Progress republishing moved inside the loop so the app can still
tell slow from dead.

`tests/launcher_control/test_remote_install_image_pull_retry.py` — runs the real
`install.sh` against a fake engine that fails the first N pulls with the exact
crc32 error. Asserts it completes and pulled N+1 times, and that a permanently
failing download reports "after 3 attempts" having actually tried three times.

Ran `scripts/sync_flutter_deployment_assets.py` to refresh
`deployment-manifest.json` (install.sh is checksum-verified before upload). Note:
that manifest's `docker-compose.yml` hash was already stale before this change —
the sync corrected it too.
