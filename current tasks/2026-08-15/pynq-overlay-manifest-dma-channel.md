# PYNQ-Z2 "Overlay Missing" — the v2 manifest lost `register_map.dma_channel`

2026-08-15. Fixed and deployed to the dev backend (`moosebun2@192.168.2.90`).

## What was wrong

`make dev-update` had worked. The v2 bitstream was built, committed, rsynced, and baked into a
launcher-control image rebuilt minutes before the report. The overlay was rejected for one absent
JSON key:

```
"manifestValid": false,
"issues": ["overlay manifest is invalid: register_map.dma_channel must match dma_ip_name"]
```

`write_manifest()` in `hardware/pynq_z2/scripts/sync_manifest_offsets.py` assigned a freshly built
`register_map` over the existing one. `build_register_map()` only produces hardware-derived values
(base address + offsets), so every contract key in that object — `dma_channel`, `timestep_us` — was
deleted the moment the v2 build ran `--write`.

Three validators disagreed, which is why nothing caught it:

| Validator | Verdict | Why |
|---|---|---|
| `sync_manifest_offsets.py --check` | green | only compared keys it builds itself |
| `PynqOverlayManifestContract` (Pydantic) | green | `dma_channel` had a **default**, silently filled in |
| `_validate_pynq_overlay_manifest` (launcher) | **red** | requires the key to be literally present |

Only the launcher's runs in production. No test validated the real shipped manifest with it — every
fixture was synthetic, and the two that omitted the key passed on the Pydantic default.

Second defect, which hid the first: `_inspect_local_pynq_overlay_package` fell back to
`inspected[0]` when no candidate was ready. In the container that is `/app/Neurochip`, a path the
image never ships, so the user was told the package was missing and to update a backend that was
already current.

## What changed

- `hardware/pynq_z2/scripts/sync_manifest_offsets.py` — `write_manifest` merges instead of
  replacing; new `CONTRACT_REGISTER_KEYS`; `--check` now fails when one is absent.
- Both `overlay_manifest.json` copies regenerated through the fixed script; byte-identical; no
  version bump (the bitstream never changed).
- `nmtk/launcher_control/pynq_service.py` — failure reporting prefers a candidate that exists on
  disk, and the message distinguishes "files absent" from "files present but rejected".
- `neurochip/contracts/pynq_runtime_artifact_contract.py` — a manifest that *names* a `register_map`
  must name its contract keys; constructing a fresh default manifest still works.
- Tests: real shipped manifest validated by the launcher validator; master/staged byte-equality;
  `--write` preserves contract keys; `--check` catches their removal; reporting prefers the package
  that exists. Two fixtures that omitted `dma_channel` were corrected.

## State

- Deployed. `_inspect_staged_pynq_overlay_package` in the running container returns
  `ready: true, manifestValid: true, issues: []`.
- `tests/launcher_control/` — 289 passed.
- `make dev-update` needed `ARGS='--skip-tests'`: the Neurochip stage has 15 failures that are
  red at HEAD and unrelated (SpiNNaker/BrainScaleS export, serial ports, optional SDK imports).
- Still open: `test_pynq_compile.py` fails twice with `PYNQ_COMPILE_MANIFEST_MISMATCH` — pre-existing,
  in the compile path rather than the install path, not investigated here.
- Stale wording elsewhere still calls the tracked package "overlay-v1" (`Dockerfile.control:37`,
  `overlay_staging/pynq_z2/README.md` and `.gitignore`, ADR-0010), and the `2026-08-14` notes still
  say the bitstream was never built.
