# PYNQ-Z2 as a real deploy target

Turned PYNQ-Z2 from a verdict-only Studio target into one that pairs a board,
installs its runtime and overlay, loads a network onto the FPGA, runs it and
verifies it — all from the app, no terminal.

## What already existed (and was not the problem)

Almost the whole stack was built and unreachable:

- **Overlay bitstream.** `Neurochip/hardware/pynq_z2/` (HLS kernel + Vivado Tcl);
  `scripts/vivado.log` shows `write_bitstream completed successfully`
  (2026-04-17). Overlay-v1 is fixed-function, so **no FINN work is involved** —
  the bitstream is synthesised once, not per network.
- **Board runtime.** `Neurochip/neurochip/app/routers/pynq.py` +
  `pynq_backend.py` → `pynq_worker.py` do a real `pynq.Overlay(...)` load, MMIO
  writes and AXI-DMA transfers inside the board's `pynq-venv`.
- **Launcher control plane.** `nmtk/launcher_control/pynq_service.py` (939 lines)
  and `http_server.py:132-514` already exposed pair / connectivity-test /
  provision / install-overlay / restart-runtime / preflight / status and proxied
  deploy / run / verify.
- **Backend payload.** `POST /api/deploy/pynq/network` already ran
  parse → lower → `plan_pynq_exportability` → `export_pynq_artifact_from_ir` →
  `build_pynq_deploy_payload` and returned a real `deploy_payload`.

The gap was wiring plus three defects.

## Capacity reality

Overlay-v1 is hard-limited to **256 neurons, 2 real populations, 15360 synapses,
LIF only, int8**, and to a **single dense weight matrix**. The workable shape is
`input port → LIF pop A → LIF pop B → output port`, e.g. `64 → 128 → 10`
(138 neurons, one 128×10 matrix). MNIST-scale networks do not fit and must not
be promised.

## Defects fixed

**Port populations were counted as neurons.** `neurocnl/neurocnl/planner.py`
summed `pop.size` over *every* population, so a declared input port ate the
256-neuron budget and a 784-pixel input rejected outright — while
`export_pynq_from_ir` had always dropped ports from both its population list and
its weight matrix. The planner was strictly more pessimistic than the exporter it
gates. Now `_real_populations()` / `_estimate_synapse_count(exclude_ports: true)`
/ `_flatten_connection_weights(exclude_ports: true)` measure what the exporter
emits, and `network_summary` reports those same counts. `exclude_ports` defaults
to false so Teensy and Akida semantics are untouched — whether an I/O projection
spends on-chip weight memory is a per-target question.

**Reachability dot was permanently red.**
`neurocnl/backend/app/routers/target_reachability.py` had no `pynq` case, so it
answered `unknown target: pynq`. A board is a separate networked machine, so that
container can never probe one — same trap already documented for Akida. Added a
`pynq` case that says so, and routed the Setup dot through a new
`pynqBoardReadinessProvider` (launcher preflight, tap to re-check), mirroring
`akidaHostReadinessProvider`. It falls back to the stored board record when
preflight fails, so a freshly paired board reads "not provisioned yet" instead of
a transport error.

**Review unlocked on a verdict.** `deployTargetHasResultProvider('pynq')` treated
any completed check — including `unsupported` — as a result, so Review claimed a
hardware result for a network that never left the backend. Now requires a run or
verify result.

## Overlay now ships with the backend

`Neurochip/overlay_staging/pynq_z2/.gitignore` ignored `*`, so the 4.4 MB overlay
was absent from clean checkouts and from image builds, and
`install_pynq_overlay_assets` reads that directory *inside the launcher-control
container* — unreachable for an end user. The old README told the user to copy
files in by hand, which breaks the no-terminal rule.

- The three files (`snn_overlay.bit`, `snn_overlay.hwh`,
  `overlay_manifest.json`) are now tracked.
- `Dockerfile.control` copies them to
  `/app/artifacts/neurochip/overlay_staging/pynq_z2/`.
- `PynqLauncherRuntimeContract.overlay_staging_candidates()` checks the Neurochip
  module root first, then `$NMTK_NEUROCHIP_ARTIFACT_DIR` — so a developer's
  freshly synthesised overlay wins, and the container (which has **no**
  `/app/Neurochip` at all — verified on the dev host) uses the shipped copy.
- The "stage a bitstream yourself" error was replaced with one that names a
  broken backend install, because that is what a missing overlay now means.

## New Studio surface

- **Pairing.** `'pynq'` branch in `add_hardware_target_form.dart` (address,
  SSH user defaulting to `xilinx`, auth with saved-password handling, runtime-URL
  override under Advanced); `pynq` cases in `studio_screen.dart`'s
  `_loadHardwareTargetDialogData` / `_saveHardwareTarget` (which previously threw
  `UnsupportedError`) / `_selectHardwareDevice` / `_syncSelectedHardwareProvider`;
  `pynq` added to `_isHardwareTargetWithManageFlowId` so the gear icon appears.
- **Selection persistence.** New `selectedPynqBoardId` launcher setting mirroring
  `selectedAkidaHostId`, maintained on create/delete. Without it the app and
  launcher control could disagree about which board a deploy targets.
- **Service + controller.** `studio_pynq_deploy_service.dart` and
  `studio_pynq_deploy_provider.dart`, mirroring the Akida pair. The old
  `pynq_deploy_provider.dart` parsed `PynqNetworkResponse` and **discarded
  `deployPayload`**; the new one keeps it and drives
  validate → deploy → run → verify.
- **Workspace.** `pynq_workspace.dart` / `pynq_setup_pane.dart` /
  `pynq_execution_pane.dart` / `pynq_results_view.dart`, replacing the one-line
  route to the verdict-only `PynqDeployPanel`. Setup offers only the step the
  board is actually blocked on; Review renders run output, timings and per-case
  verification, plus a provenance badge.
- **Registry.** Added the launcher routes that had no Dart caller: board
  get/delete, select + read-selected, connectivity-test, provision,
  install-overlay, restart-runtime, preflight, deploy, run, verify,
  runtime-status. `fetchPynqBoards` / `savePynqBoard` already existed and were
  dead code.
- **Simulator masquerade rejected.** Deploy always sends
  `require_hardware: true`, and `StudioPynqDeployService.deploy` *also* rejects an
  ack whose `runtime_mode` is not `hardware`. A simulator-satisfied deploy returns
  a 200 identical to silicon in every other field.
- **Deep link fixed.** `?target=pynq` was silently ignored —
  `supportedDeployTargets` in `workspace_provider.dart` omitted it — and landed
  on the default target.

## Trained weights: found broken, then fixed

Writing the guide exposed that the deploy payload derives from the **CNL spec**, and CNL carries
tensor *shape* only — `neurocnl/nir_cnl/renderer.py:381-385` ("CNL only carries tensor shape; exact
tensor payloads belong in NIR/canvas sidecars") and the round-trip contract in
`tests/nir_native_cnl/_round_trip.py` ("zero-filled recovered tensor"). Measured on the real path:
128 trained values in, **0 non-zero out**. A trained network deployed, loaded the overlay and fired
nothing.

Fixed by carrying the weights through the artifact that already had them.

**Source of truth: the NIR Exporter node's `model.nir`.** `notebook.py:2456` already loads
`best_model.pt`, overlays the learned weights onto the NIR graph and calls `nir.write`. Nothing
served that file, so nothing could use it. (The Akida bundle is the same idea; PYNQ has no bundle
format, so this reuses the NIR interchange instead of inventing a second one.)

- **`GET /api/notebook/artifacts/latest-trained-nir`** — sibling of `latest-akida-bundle`. Rather
  than copy its ~110 lines of Jupyter-Contents-API-plus-local-disk discovery, that body was
  extracted into `_discover_workspace_artifact(suffix, max_bytes, …)` and both endpoints now call
  it. `latest-akida-bundle` behaviour is unchanged.
- **`backend/app/services/pynq_trained_weights.py`** — reads the graph from bytes and writes the
  single dense matrix onto the matching `ConnectionIR.weight`. Overlay-v1 stores exactly one matrix,
  so matching is by shape and is unambiguous; port projections are excluded because the exporter
  drops them. Refuses a shape mismatch with both shapes named (the usual cause is a checkpoint from
  before the last canvas edit) and refuses two same-shaped candidates rather than guessing.
- **`POST /api/deploy/pynq/network`** takes optional `trained_nir_base64` and returns
  `trained_weights` describing what was applied. The overlay runs *before* the gate, because the
  quantizability check reads actual values — gating zeros then swapping in trained weights would
  verify a network nobody deploys.

### The quantisation gate was wrong, and only real weights revealed it

Both the planner (`planner.py` §9) and the exporter demanded that every scaled weight land exactly
on an integer, which contradicts the `np.round` inside `quantise_weights_array` they guarded. int8
quantisation is lossy by construction, so this is a test almost no trained matrix passes — it had
been invisible because PYNQ weights were always zeros (`max_abs == 0` skipped the loop) or
hand-picked literals. Every trained network was rejected `WEIGHT_NOT_QUANTIZABLE`.

Replaced with `quantisation_fidelity()` in `transforms/quantise.py`, which measures scale, max
round-trip error, and how many non-zero weights collapse to zero:

- **reject** only non-finite weights (no fixed-point image at all);
- **warn** with the collapse count, e.g. *"2 of 128 non-zero weights (1.6%) round to zero at 8-bit
  precision and will not fire on the board"*.

`is_total_loss` is kept as a defensive guard but is unreachable under max-abs scaling — the largest
weight always maps to ±127 — which is why the test for it was replaced with one asserting a wide
dynamic range stays *deployable*.

### Measured after the fix

```
overlay : True | Loaded trained weights from fc (4×32, 128 non-zero).
verdict : exportable_with_warnings
warnings: ['2 of 128 non-zero weights (1.6%) round to zero at 8-bit precision …']
payload : 128 weights, 126 nonzero, range -127 .. 113
```

### Studio side

`latestTrainedNir` on the API client, `fetchLatestTrainedNir` on the deploy service (absence and
transport failure both fall back to a zero-weight deploy rather than blocking bring-up),
`trainedNir` on the controller state, and a **weight-provenance badge** under *Network fit* reading
*Trained weights* / *Untrained weights* / *Trained model is empty*. A zero-weight run in Review now
says that is the only possible outcome instead of blaming the input or the threshold.

## Deliberately not done

## Deliberately not done

- **FINN.** `pynq_compiler.py` needs `NEUROCHIP_PYNQ_FINN_COMPILE_CMD`, and no
  `finn` / `brevitas` / `qonnx` dependency exists anywhere in the repo.
  Overlay-v1 does not need it.
  `neurocnl/issues-archive/005-pynq-finn-compilation-pipeline.md` and
  `Neurochip/issues-archive/003-pynq-z2-finn-compilation.md` stay open.
- **Deploy records.** `record_deployment` cannot be used from either side:
  `deployment_store.py` writes a SQLite file inside the installed package, and
  `/hardware/pynq/deploy` runs on the board, whose agent does not even mount
  `/api/neurochip/deployments`. Akida does not record either. Needs new
  persistence + endpoint + UI in launcher-control, covering both targets.
- Multi-board / generic-FPGA generalisation (see
  `current tasks/2026-07-23/pynq-fpga-generalization-notes.md`), notebook → PYNQ
  bundle producer, and benchmark charts.
- The legacy `pynq_deploy_panel.dart` / `pynq_deploy_provider.dart` are now
  referenced only by their own test, matching how `akida_deploy_panel.dart` was
  left. Removing both targets' legacy panels belongs in one cleanup.

## Verification

Green:
- `pytest tests/launcher_control/ tests/test_launcher_control_contracts.py` — 282
  passed, including two new cases for the container overlay fallback and
  module-root precedence.
- `pytest neurocnl/contracts/ neurocnl/export/test_pynq_exporter.py
  neurocnl/handoff/test_neurochip_pynq_handoff.py -p no:nengo` — 107 passed,
  including five new port-population regression cases.
- `flutter test` in `neurocnl/frontend` — 1787 passed, including the new
  `test/widgets/pynq_deploy_no_nested_cards_test.dart` (a file
  `sc_neurocore_lava_workspace_no_section_card_test.dart:5` had referenced since
  before it existed) and three PYNQ pairing cases in `studio_screen_test.dart`.
- `flutter analyze` clean in `neurocnl/frontend` and `nmtk_ui_core`.

Pre-existing, unrelated, not caused here: 15 failures in
`neurocnl/neurocnl/{layers,runtime,tests/nir_native_cnl}` (none reference the
planner); one `nmtk_ui_core/test/desktop_scaffold_test.dart` avatar-initials
failure; `neurocnl/backend/tests` cannot collect (`No module named 'nmtk_sdk'`);
`Neurochip`'s suite cannot collect in the ambient conda env (broken matplotlib) —
no Neurochip Python was changed.

Still outstanding — **on-hardware end-to-end has not been run.** The dev host
`192.168.2.90` bind-mounts `nmtk/launcher_control`, so the Python changes are
already live there (`/health` returns `selectedPynqBoardId`), but the overlay
arrives via `Dockerfile.control`, so **launcher-control needs an image rebuild**
before Install Overlay has anything to copy — confirmed absent:
`/app/artifacts/neurochip/overlay_staging/pynq_z2/` does not exist in the running
container, and neither does `/app/Neurochip`. After that rebuild:

1. `flutter run -d macos` from `nmtk/neuro_toolkit`, connect to `192.168.2.90`.
2. Setup → tick PYNQ-Z2 → gear → pair the board (address, `xilinx`, password).
3. Deploy step → Install board runtime → Install overlay → Check readiness green.
4. Build a `64 → 128 → 10` network on the canvas → Deploy → Run → Verify.
5. Confirm the badge reads "Loaded on PYNQ-Z2 FPGA" — a simulator fallback is
   rejected outright rather than shown as hardware.
6. `PYNQ_HARDWARE_TEST=true pytest -m pynq_hardware
   tests/integration/test_golden_path_pynq_hardware.py`.
