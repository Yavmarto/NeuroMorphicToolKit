# PYNQ-Z2 overlay v2 — making the FPGA path actually compute

Date: 2026-08-14
Follows: `current tasks/2026-08-13/pynq-z2-as-real-deploy-target.md`

## Why

The 2026-08-13 sprint made PYNQ-Z2 reachable from the app: pair a board, install
the runtime and overlay over SSH, deploy trained weights, run, see results. The
next question was whether to add a new chip or deepen this target. Deepening won.

Reading the actual HLS source, the Vivado block-design script, the synthesised
`.hwh` and the board-side worker turned up something larger than the 256-neuron
capacity limit: **overlay-v1 could not produce a correct result on silicon, and
never could.** Everything in the app above the FPGA boundary was wired
correctly. This is consistent with the fact that on-hardware end-to-end had
never been run.

## The six defects (all provable from source, before touching a board)

1. **Weights never reached the fabric.** `weights` was declared
   `#pragma HLS INTERFACE bram`, which puts raw BRAM ports on the IP, and
   `build_overlay.tcl` never attached a memory controller to them. The shipped
   `snn_overlay.hwh` confirms it — seven modules, none of them memory. Meanwhile
   the worker wrote weights to AXI-Lite `0x40000000 + 0x1000 + i*4`, an offset
   the control bundle does not map. Every weight the engine read was zero, so
   the board returned silence that the app displayed as a successful run.
2. **The manifest's register offsets were wrong.** It claimed 8/12/16/20; the
   `.hwh` puts the scalars at 0x10/0x18/0x20/0x28. The base address was right.
3. **The kernel was never started.** `_configure_hardware` wrote the weight
   count into `CTRL` (whose bit 0 is `ap_start`), and `_run_hardware` wrote
   `0x01` to offset `0x08`, which is neither `CTRL` nor `GIER`.
4. **It was not a spiking neuron.** The membrane was re-initialised for every
   neuron on every timestep — no leak, no refractory, no state. A thresholded
   matrix-multiply wearing a LIF label.
5. **Neuron 0 was unrepresentable.** A firing neuron emitted its own index and
   silence emitted 0.
6. **The two sides disagreed on the stream protocol.** The engine consumed the
   input vector once per *output neuron*; the host sent it once per timestep and
   sized the output buffer from the input length.

Fixing (1) changes the HLS interface, which forces a re-synthesis, so all six
were fixed in one new overlay rather than shipping two bitstreams.

## What was built

### Phase 1 — `snn_overlay_v2` (complete)

- `hls/snn_overlay_engine.{hpp,cpp}` rewritten: weights arrive over an `m_axi`
  DDR master and are cached on-chip; persistent membrane state with a
  shift-based leak and a refractory counter; per-layer thresholds; one output
  word per neuron per timestep; up to 4 layers, 1024 neurons per layer, 262144
  synapses.
- `hls/snn_overlay_engine_tb.cpp` — behavioural testbench covering all six
  defects. Wired into `build_hls.tcl` as a `csim_design` step *before*
  synthesis.
- `hls/csim_compat/` + `hls/run_csim_local.sh` — run that testbench with a plain
  host compiler, no Vivado and no board. **All six checks pass.**
- `vivado/build_overlay.tcl` — connects the engine's weight master to
  `S_AXI_HP2`, and errors out rather than building a bitstream whose engine has
  no weight port.
- `scripts/sync_manifest_offsets.py` — derives the manifest's register offsets
  from the built `.hwh` (`--write`) and fails on drift (`--check`). Wired into
  `build_overlay.sh`. Until a build runs, the manifest's offsets are explicitly
  `null`, and both contracts refuse to drive hardware from an unresolved map.

### Phase 2 — everything above the boundary (complete)

- Both `pynq_runtime_artifact_contract.py` files (Neurochip and neurocnl) and
  `pynq_deployment_contract.py` migrated to v2, with `resolved_from_hwh` as a
  first-class state and an all-or-nothing register-map validator.
- `planner.py` — single-matrix restriction replaced by a layer-chain check
  (`_is_linear_chain`), plus a per-layer neuron limit. Memory estimate now
  delegates to the contract and no longer charges 8 bytes per synapse for index
  pairs a dense matrix does not store.
- `pynq_exporter.py` — `_assert_layer_chain` replaces the two copies of the
  one-matrix rule.
- `neurochip_pynq_handoff.py` — `build_pynq_deploy_payload` now emits per-layer
  descriptors in chain order with contiguous weight offsets, scales thresholds
  by the quantisation factor, and maps `tau` onto the engine's leak shift.
- `pynq_worker.py` — resolves every offset before allocating, hands the engine
  DDR buffer addresses, asserts `ap_start`, polls `ap_done`, and sizes buffers
  from the layer descriptors.
- `pynq_simulator.py` — rewritten as a faithful reimplementation of the HLS
  engine. `test_pynq_simulator_matches_engine.py` runs the same six cases as the
  C++ testbench and gets identical results.
- `pynq_backend.py` — the in-process register-write path is gone; it carried a
  second copy of the v1 run defects and cannot deliver a DDR buffer anyway.
- `pynq_sitl_verifier.py` — default stimulus is generated from the configured
  network's input width instead of a fixed list of spike indices.
- `launcher_control/server.py` — expects v2, and refuses a v1 board with a
  plain-language reason and no terminal instructions.

## Verification

| Suite | Result |
|---|---|
| `hls/run_csim_local.sh` | all snn_overlay_v2 checks pass |
| Neurochip pynq tests | 141 passed, 1 skipped |
| neurocnl pynq + planner | 108 passed, 5 skipped |
| launcher_control | 278 passed |

## Not done

- **Phase 3 — on-silicon self-test.** `POST /hardware/pynq/selftest` with a
  known weight matrix and exact expected output, run automatically at overlay
  install so an all-zero result fails loudly. Not started.
- **Phase 4 — accuracy benchmarking.** `POST /hardware/pynq/benchmark` and the
  Flutter results view to match Akida's. Not started.
- **The bitstream has not been built.** Everything here is source; the overlay
  in `Neurochip/overlay_staging/pynq_z2/` is still v1, and its manifest is now
  rejected by design. `scripts/build_overlay.sh` must run on the Linux Vivado
  2022.2 host, then `stage_overlay.sh`, then `make dev-update`.
- Nothing has run on the physical board.

## Watch out

- `OVERLAY_V2_MAX_SYNAPSES` (262144) is the on-chip weight cache and the
  dominant BRAM consumer — roughly 42% of the xc7z020. If post-synthesis
  utilisation overflows, halve it first; 131072 still fits 784 → 128 → 10.
- The v2 output format is one word per neuron per timestep, not a list of neuron
  indices. Any consumer still expecting indices will silently misread it.
