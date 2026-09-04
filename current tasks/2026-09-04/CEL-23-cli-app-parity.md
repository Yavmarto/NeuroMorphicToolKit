# CEL-23 — Full feature parity between the CLI and the app

Date: 2026-09-04

## What was missing

`neurocli` could scaffold projects, build offline packages, drive Compose, run
Studio and talk to Neurohub, but it could not reach a *running* backend the way
the app does. Everything behind launcher-control — modules, workspaces,
deployment jobs, Akida hosts, PYNQ boards — was app-only, because the CLI had
no way to open the app's SSH tunnel or obtain the launcher admin token.

## What was built

`neurocli/neurocli/session.py`
: Resolves a backend session. Reads the app's own target list from its macOS
  preferences (`clientDeployment.targets.v1`), opens an SSH tunnel with a
  multiplexed control socket forwarding 8090/9000/8008 to loopback, and reads
  the admin token live over that connection using the same probe script the app
  uses (`remote_deployment_runner.buildAdminTokenProbeScript`).

`neurocli/neurocli/backend.py`
: A single `ROUTES` table naming every backend endpoint the app calls, and one
  generic command factory that materialises `neuro backend <group> <name>` for
  each. Groups: modules, launcher, workspace, deployment, akida, pynq, suite,
  jupyter. Plus `neuro backend api` as an escape hatch, `targets`, `connect`,
  and top-level `neuro login` / `neuro logout`.

## Credential handling

- The CLI writes no secret to any file.
- SSH password → OS keychain (`security` on macOS, `secret-tool` on Linux),
  handed to `ssh` via `SSH_ASKPASS`, never on a command line. Verified by test.
- SSH keys/agent need no login step.
- Launcher admin token → never stored; read live over the authenticated SSH
  channel each session.
- `NMTK_LAUNCHER_URL` + `NMTK_ADMIN_TOKEN` bypass discovery and the tunnel, for
  CI.

## Parity is enforced, not asserted

`tests/test_backend.py` fails the build if the Flutter app calls a
launcher-control path that `ROUTES` does not cover, and if launcher-control
serves one that `ROUTES` does not cover. Adding an endpoint to the app now
means adding one line to `ROUTES`.

## Verification

```bash
cd neurocli
.venv/bin/python -m ruff check neurocli tests   # clean
.venv/bin/python -m mypy neurocli               # clean, 13 files
.venv/bin/python -m pytest tests -q             # 81 passed
```

Live check against this machine's real app config: `neuro backend targets`
found the configured `remote-192-168-2-90` target, and `neuro backend connect`
correctly stopped with "No saved password … run `neuro login`".

## Not verified

No end-to-end run against the dev host at `moosebun2@192.168.2.90` — this
machine has no SSH key there and the account password is not available to the
agent. The tunnel path is covered by a test that stubs `ssh` on `PATH` and
asserts the argv, forwards, askpass wiring, and token parsing; a real login
still needs a human to run `neuro login` once.
