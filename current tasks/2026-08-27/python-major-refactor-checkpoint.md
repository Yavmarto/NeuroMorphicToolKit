# Python Major Refactor Checkpoint — 2026-08-27

## Progress

The behavior-preserving Python refactor is approximately **51% complete**, weighted by remaining
complexity. This checkpoint completes the PYNQ provisioning-coordinator and versioned-template
slices described in the [August 26 handoff](../2026-08-26/python-major-refactor-handoff.md).

## Completed in this slice

- Added `nmtk/launcher_control/pynq_provisioning.py` as the typed owner of PYNQ installation,
  preflight refresh, runtime status, overlay installation, user-space restart, systemd promotion,
  health polling, and provisioning diagnostics.
- Reduced `nmtk/launcher_control/pynq_service.py` from 1,133 lines to a 291-line compatibility
  façade for repositories, transport, provisioning, and runtime proxy services.
- Preserved routes, payloads, progress messages, persisted fields, serialized output, optional
  capability semantics, and private patch points used by existing tests.
- Updated tests to patch the owning provisioning module's retry clock and to enforce that the new
  boundary does not import `server.py`.
- Moved the PYNQ installation program and systemd unit out of Python string builders into tracked
  `pynq/v1` templates with a strict renderer that rejects missing and unused values.
- Added SHA-256 golden tests proving both rendered artifacts are byte-for-byte identical to the
  pre-extraction output, plus a release-image packaging check for the templates.
- Fixed Backend Setup diagnostics so the health card checks the host shown as connected instead of
  whichever saved deployment attempt happened to have the newest timestamp. A failed setup for
  `192.168.2.34` had caused a false outage while the app was connected to healthy `192.168.2.90`.

## Verification

- Focused PYNQ, template, packaging, and compatibility tests: **134 passed**.
- Complete launcher-control suite outside the socket-restricted sandbox: **340 passed**.
- Ruff check and formatting: **passed** for all launcher-control Python and tests.
- Strict mypy for `pynq_provisioning.py` and the new template renderer: **passed**.
- Python compilation and `git diff --check`: **passed**.
- Launcher doctor: **0 fatal findings**, with **1 degraded optional capability** for unavailable
  Studio SDK extras.
- Deployment asset synchronization check: **passed**.
- Targeted Dart analysis for the connected-host health fix: **passed**.

The canonical launcher guardrail's Python half passed, but its Flutter half failed to compile due
to concurrent `neurocnl` frontend work referencing missing `StudioAkidaModelJob`,
`StudioAkidaClassResult`, `NmtkShellTokens`, and `StudioResultVisualizer` symbols. Those failures
are outside this Python slice and were not modified here.

## Next safe slice

Continue launcher decomposition by extracting PYNQ status serialization. Keep `pynq_service.py` as
a compatibility façade and do not change public contracts or stored settings during that move.

After launcher-control is complete and the unrelated Flutter guardrail is green, continue with the
NeuroCNL notebook-generation split from the approved major-refactor plan.
