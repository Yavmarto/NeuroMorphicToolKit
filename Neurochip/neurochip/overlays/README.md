# PYNQ Overlay Assets

This directory is the board-local runtime location for canonical PYNQ overlay
assets after they have been installed onto a board-hosted Neurochip service.

Place the board-ready PYNQ-Z2 overlay package in this directory:

- `snn_overlay.bit`
- `snn_overlay.hwh`

Neurochip resolves relative PYNQ bitstream names against this directory and
uses the `.hwh` sidecar to determine whether the real-board runtime is ready.

These files are intentionally not committed here because they come from an
external Vivado synthesis flow. Until both files are present, the toolkit can
only truthfully claim simulator-backed PYNQ deployment.

For launcher-managed install from the host machine, stage the externally built
files under `Neurochip/overlay_staging/pynq_z2/` first. The launcher's
`Install Overlay` step copies that staged package to this canonical runtime
directory on the board.

Once the files are present on the board-hosted Neurochip service, verify
readiness with:

```bash
curl http://<board-ip>:8002/hardware/pynq/preflight
```

Only a `preflight_status` of `ok` should be treated as real-board readiness.
