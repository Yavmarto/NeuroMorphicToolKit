# Host-Staged PYNQ Z2 Overlay Package

The built overlay-v1 package lives here and **is tracked in git**:

- `snn_overlay.bit`
- `snn_overlay.hwh`
- `overlay_manifest.json`

This is the source the launcher's `Install Overlay` action copies to the board
over SCP, and the backend image ships a copy of it (see `Dockerfile.control`),
so an end user gets a working overlay with no terminal and no synthesis
toolchain. Nothing to stage by hand.

The launcher looks in two places, in this order:

1. `<Neurochip module root>/overlay_staging/pynq_z2` — this directory, used in a
   source checkout.
2. `$NMTK_NEUROCHIP_ARTIFACT_DIR/overlay_staging/pynq_z2` — the copy baked into
   the launcher-control image, which has no Neurochip source tree.

The first *complete* package wins, so a freshly synthesised overlay dropped in
here overrides the one shipped in the image.

## Replacing the overlay (developers)

Only needed when the overlay contract itself changes — the bitstream is
fixed-function, so a new network does **not** need a new bitstream.

1. On a Linux x86_64 host with Vivado 2022.x and Vitis HLS, run
   `../../hardware/pynq_z2/scripts/build_overlay.sh`.
2. Run `../../hardware/pynq_z2/scripts/stage_overlay.sh` to copy
   `build/out/snn_overlay.{bit,hwh}` and `overlay_manifest.json` here.
3. Commit the three files, and bump `overlay_version` in the manifest if the
   register map or capacity limits moved — the launcher validates the staged
   manifest against `EXPECTED_PYNQ_OVERLAY_MANIFEST` in `pynq_service.py` and
   refuses to install a mismatched package.
