# Deploy failed with "Root permissions required."

**Symptom.** With the register map fixed, the deploy reached the board and died there:

```
HTTP 500 - {"detail":{"detail":"Overlay loading failed: Root permissions required.",
            "error_code":"OVERLAY_LOAD_FAILED"}}
```

The board reported `ready` / `ok` / `hardware` throughout.

## Cause

PYNQ writes the bitstream through the FPGA manager, which only root may drive, so `Overlay(...)`
refuses outright for a non-root process. The agent was installed **in user space**, as `xilinx`.

The install script picks its mode with a passwordless-sudo probe
([provisioning_helpers.py:369](../../nmtk/launcher_control/provisioning_helpers.py)):

```sh
if sudo -n true >/dev/null 2>&1; then   # systemd service, runs as root
else                                     # user-space fallback
```

The stock PYNQ image has no passwordless sudo, so every board took the fallback — even though the
launcher holds a password for the board that *does* grant sudo (it already uses it to add the agent
user to the `video`/`render` groups). Nothing downstream noticed: a user-space agent enumerates the
device, passes preflight, and reports hardware mode. Only a real bitstream load fails, at the end of
a fully green setup.

## Fix

1. **Provisioning now promotes the install to a root service.**
   `_promote_pynq_install_to_systemd` in [pynq_service.py](../../nmtk/launcher_control/pynq_service.py)
   runs when the script lands anywhere other than `systemd`: probe for root, stage the bundle's unit
   with the interpreter the install actually chose, stop the user-space agent, `mv` the unit into
   `/etc/systemd/system`, `daemon-reload` / `enable` / `restart`, rewrite `installMode` in
   `install-status.json`, then wait for health. Root is probed **before** anything is torn down, and
   a failure anywhere after that restores the user-space agent.
2. **`_run_ssh_privileged`** picks the mechanism per board: stored password → `sudo -S` on stdin;
   key-paired board → `sudo -n` (which is how it would already have been a systemd install).
   `restart_pynq_runtime`'s systemd branch used bare `sudo systemctl restart`, which would have hung
   on a password prompt — it goes through the helper now.
3. **The board says something actionable** when it does end up without root: `PYNQ_ROOT_REQUIRED`
   (422, not 500) with "loading a bitstream requires root … Install the board runtime again from the
   app", in both the isolated worker and the in-process path.

## Verified on the board

- Re-provisioned through the launcher: `installMode: systemd`, `autoStartSupported: true`,
  preflight `ok`, runtime mode `hardware`.
- Real deploy of the MNIST 784→256→10 payload with `require_hardware: true`:
  `{"status":"success","message":"Overlay loaded and configured successfully.",
  "runtime_mode":"hardware","overlay_version":"2.0.0"}`

## Tests

- `tests/launcher_control/test_launcher_pynq_provisioning.py` — promotion happens and in the right
  order (unit staged before the agent is stopped); skipped without root, with the running agent left
  alone; a mid-way failure restores user space; the install-mode rewrite; systemd restart uses the
  password path. **303 pass** (was 297).
- `Neurochip/neurochip/tests/test_pynq_backend.py::TestPynqRootRequirement` — the translation, the
  untouched generic case, the code surviving the worker hop, and the 422. **63 pass**
  (`-p no:nengo`).

## Side effect

Auto-start after a board reboot now works, which is what the old user-space guidance kept warning
about.
