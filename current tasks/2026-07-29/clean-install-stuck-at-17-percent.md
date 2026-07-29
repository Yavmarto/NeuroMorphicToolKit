# Clean install stuck at 17% — 2026-07-29

## Symptom

"Set up a new server" from Backend Setup froze at **17% — Preparing the NMTK
deployment account** and never finished, failed, or offered a way out. The raw
SSH transcript ended with the rootless Podman API verify step succeeding, then
nothing.

## Root causes (three, stacked)

1. **The app waited on channel EOF, not on the script.**
   `_runAdministratorScript` (`client_deployment_service.dart`) awaited
   `Future.wait([stdout.asFuture(), stderr.asFuture()])` with no timeout after
   `waitForExit` returned. `waitForExit` resolves when sshd sends `exit-status`
   (i.e. when `bash` exits), but sshd keeps the channel open until every process
   that inherited the session's stdout/stderr has exited. Preparing rootless
   Podman deliberately leaves such processes behind — `loginctl enable-linger`,
   the socket-activated `podman system service`, and the pause process that the
   transcript shows failing to join a systemd scope. One survivor = permanent
   hang, with the server already correctly set up.

2. **Stall protection was disarmed exactly there.** The watchdog was armed on
   `NMTK_SETUP_STEP|start` and *cancelled* on `finish` with nothing armed in its
   place, so every gap between steps — and the whole tail after the last step —
   was unguarded.

3. **The stall was invisible and unrecoverable.** The notifier's staleness
   watchdog set `connectionLostReason` but kept `activeJob`, and
   `_buildStatusPanel` renders the job card first, so the reason was never
   displayed. Its clock was also unreachable: `updatedAt` was re-stamped by the
   5-second liveness heartbeat and by every poll. And there was no Retry
   control, even though the failure copy said "Select Retry".

A fourth instance of the same class was waiting later: `install.sh` ran
`compose pull` / `up -d` / `down` with no timeout under `nohup`, so a stalled
GHCR connection parked the status file at `pulling_images|45`.

## Fix

- `NMTK_SETUP_DONE|<exit>` emitted from the script's EXIT trap (all three exit
  paths) and treated as the authoritative end of the session; EOF is no longer
  required. Filtered out of the user-visible transcript as a protocol marker.
- `_drainTranscriptStreams` (3 s) and `_settleStreamedUpdates` (10 s) bound the
  post-exit waits; applied to `_runRemoteCommand` too. Status polls bounded at
  20 s so a wedged read can't silently stop every later poll.
- Idle watchdog rearmed on **every** received line: `timeoutSeconds + 7` with an
  operation active, 90 s otherwise, failing with the new `administrator_stalled`
  code.
- `DeploymentJob.lastProgressAt` — stamped only by real progress (`_emit`,
  terminal output, operation transitions), never by the heartbeat or an
  unchanged poll. Staleness now measures it: 3 min, or 25 min for
  `pulling_images`.
- Job card renders a stalled state (headline, reason, last step, no live bar) and
  a **Retry setup** button that keeps host/engine/factory-reset, asks only for
  the administrator password, and cancels the stalled attempt first
  (`retryRemoteSetup`).
- `install.sh`: `compose_with_timeout` (down 5 min, pull 20 min, up 10 min,
  diagnostics 60 s), `fail_stage` for actionable timeout messages, and an
  elapsed-time heartbeat during the image pull.

## Non-finding

The `NMTK_SETUP_AUTOMATIC_RECOVERY=true \ capture_step …` assignment prefix was
suspected of leaking the flag into later steps. Bash does not persist assignment
prefixes across a shell-function call (verified), so the original form was left
in place.

## Verification

- `flutter test` in `nmtk/neuro_toolkit` — 161 passed (5 new service tests,
  2 new screen tests).
- `flutter test` in `nmtk_ui_core` — 171 passed.
- `python3 -m pytest tests/launcher_control` — 213 passed (1 new contract test;
  updated the `compose ps -a` assertion for `compose_with_timeout`).
- `python3 scripts/launcher_control_service.py --doctor --json` — `fatalCount: 0`.
- `install.sh` changed ⇒ `python3 scripts/sync_flutter_deployment_assets.py` run
  and `BUNDLE_VERSION` bumped 7 → 8, otherwise every deploy fails checksum
  verification.

## Still to do

End-to-end run against `192.168.2.51` with Podman has not been done — it needs
the administrator credential, which only the user has.
