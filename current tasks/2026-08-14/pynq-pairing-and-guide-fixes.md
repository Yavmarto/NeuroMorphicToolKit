# PYNQ pairing, run input format, and both guides

Date: 2026-08-14
Follows: `pynq-overlay-v2-rebuild.md` (same day)

## Why

Two things reported against `../2026-08-13/GUIDE-pynq-z2-hardware.md`:

1. Its network sizes were unusable as instructions — "`32 → 4`" and "`128 → 100`" with no node or
   field named, unlike every other guide here.
2. "Save and test connection" does not exist for a PYNQ board; the status dot stays grey and
   re-checking says *Unpaired*.

Confirming those turned up two more defects that made the guide undocumentable, and a third found
while writing it.

## What was actually wrong

1. **No connectivity test for PYNQ.** `studio_screen.dart` passed `onTestTarget` only when
   `targetId == 'akida'`, and both the form's "Save and test connection" button and the per-row Test
   icon are gated on that callback. The launcher-control endpoint
   (`POST /api/launcher/pynq/boards/<id>/connectivity-test`) and the Dart client method
   (`testPynqBoardConnection`) both already existed with no caller.
2. **A paired board read as "Unpaired".** `create_pynq_board` stores
   `DEFAULT_PYNQ_BOARD_STATE = "unpaired"` and nothing advanced it. Readiness alone cannot: preflight
   needs the board agent, which is not installed yet, so it fails and the provider falls back to the
   stored record. Tapping the dot therefore returned the same word forever — and that word said the
   board was not paired when it was.
3. **Run could not succeed.** The execution pane collected sparse spike *indices* and sent them
   verbatim — the v1 protocol. Overlay-v2 takes one word per input neuron per timestep, and both the
   board worker and the simulator reject a short transfer with `Expected N input words`.
4. **Trained weights were still capped at one matrix.** `pynq_trained_weights.py` refused any network
   with more than one population-to-population connection ("Overlay-v1 stores exactly one weight
   matrix"). The planner now accepts up to 4, so an MNIST-scale `784 → 256 → 10` chain passed the fit
   check and then had its trained weights refused.
5. **Both guides' capacity claims were v1.** The PYNQ guide printed 256 / 2 populations / 15360
   synapses; the MNIST guide said in two places that its network cannot reach the board.

## What changed

- `studio_screen.dart` — `onTestTarget` is a switch over target type, plus
  `_testPynqBoardConnection`. No provision follows the test: SSH `python3 --version` answers in
  seconds and a cold provision needs 90–100 s, so installing the runtime stays an explicit choice.
- `pynq_deployment_model.dart` — `PynqBoardState.unpaired.label` is now **"Not checked yet"**
  (`apiValue` unchanged). Added `PynqLayerDescriptor` and a typed `layers` field on
  `PynqDeployPayload`; it previously survived only by falling into `additionalFields`.
- `setup_step.dart` — `_recheckPynq` runs the SSH test first for a board nothing has contacted, so
  the dot can advance from where the board was paired. Every non-ready state now names the in-app
  button that clears it (`_pynqNextStep`), never a terminal command.
- `studio_pynq_deploy_provider.dart` — `buildInputFrames()` expands the typed indices into
  `input_size × timesteps` words, with each named neuron spiking on every timestep. An index past the
  input width is now named in the error rather than silently dropped.
- `pynq_execution_pane.dart` — field relabelled "Input neurons that spike", with helper text naming
  the valid range.
- `pynq_trained_weights.py` — fills in **every** layer. Both sides are put into chain order and
  zipped, so position identifies a layer; that is also the only thing that can separate two layers of
  identical shape (`256 → 256 → 256`). Errors name which layer, both shapes, and the count when the
  file holds a different number of matrices than the network has layers.
- `test_deploy_endpoints.py` — asserted `snn_overlay_v1` / `1.0.1` / `15360`; now reads
  `PYNQ_LIMITS`, which is what stopped it drifting in the first place.
- Both guides rewritten where they were wrong — see below.

## Guide changes

`../2026-08-13/GUIDE-pynq-z2-hardware.md`:

- §1 — v2 limits from `overlay_manifest.json`, and the topology rule stated once.
- **§4b — the reported gap.** Explicit node/field tables for `32 → 4` and `784 → 256 → 10`, with the
  convention spelled out: **on a Linear, `Rows` is the LIF after it and `Cols` is the LIF before it.**
  Also states why every Linear has to sit between two LIF populations — a matrix whose source is a
  declared port is the fixed DMA path, not a layer.
- §4 — the buttons that now exist; §4's dot table and re-check note updated.
- §6 — what the input field actually means, and the current verify case names.
- §9 — rewritten as an honest status: v2 is source-complete, the bitstream is unbuilt, the staged
  overlay is v1 and refused by design, so on-board deploy is blocked. The header now leads with that.

`../2026-07-28/GUIDE-mnist-fcn-studio.md` — the two places claiming its network cannot reach PYNQ now
say what is true: `784 → 1000 → 10` still does not fit (784000 synapses against a 262144 cache),
`784 → 256 → 10` now does.

## Verification

| Suite | Result |
|---|---|
| `neurocnl/frontend` `flutter test` | 1808 passed, 1 skipped |
| `nmtk_ui_core` `flutter test` | 198 passed |
| `flutter analyze lib test`, both packages | no issues |
| `neurocnl/backend/tests -k pynq` | 19 passed |
| neurocnl pynq contracts / export / handoff | 107 passed |
| `Neurochip/neurochip/tests -k pynq` | 141 passed, 1 skipped |
| `tests/launcher_control` | 279 passed |
| golden-path + handoff VCR | 2 passed, 5 skipped |

New tests: `nmtk_ui_core/test/pynq_deploy_payload_layers_test.dart`,
`neurocnl/frontend/test/providers/studio_pynq_input_frames_test.dart`, three PYNQ cases in
`studio_screen_test.dart`, three chain cases in `test_pynq_trained_weights.py`.

## Still not done

- On-silicon self-test and accuracy benchmarking (overlay-v2 plan Phases 3 and 4).
- The bitstream. Nothing here needed Vivado or a board, and nothing here unblocks on-board deploy.

## Watch out

- `PynqBoardState.unpaired` is now labelled "Not checked yet" but its `apiValue` is still
  `"unpaired"`. Match on the enum, never the label.
- The execution pane's field is indices; the wire format is frames. `buildInputFrames` is the only
  place that conversion should live.
- Trained-weight layers are matched by **position**, not name. A change that reorders either side
  silently deploys the wrong matrix to the wrong layer — `test_chain_order_comes_from_the_graph_not_the_node_dict`
  is the guard.
