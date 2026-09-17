# PYNQ Z2 Overlay v2

Hardware scaffold for the `snn_overlay_v2` runtime contract used by Neurochip
and NeuroCNL.

## Why v2 exists

Overlay-v1 could not compute. It was synthesised and shipped without anything
ever having executed the kernel, and six defects survived to the bitstream:

1. **Weights never reached the fabric.** `weights` was declared
   `#pragma HLS INTERFACE bram`, which puts raw BRAM ports on the IP, and the
   block design never attached a memory controller to them. Every weight the
   engine read was zero, so the board could only return silence — which the app
   displayed as a successful hardware run.
2. **The manifest's register offsets were wrong.** It claimed 8/12/16/20 where
   Vitis HLS had placed the scalars at 0x10/0x18/0x20/0x28.
3. **The kernel was never started.** The host wrote a weight count into the
   `CTRL` register (whose bit 0 is `ap_start`) and then `0x01` into offset
   `0x08`, which is neither `CTRL` nor `GIER`.
4. **It was not a spiking neuron.** The membrane potential was re-initialised
   for every neuron on every timestep, with no leak and no refractory period —
   a thresholded matrix-multiply wearing a LIF label.
5. **Neuron 0 was unrepresentable.** A firing neuron emitted its own index and
   silence emitted 0, so neuron 0 firing was byte-identical to no spike.
6. **The two sides disagreed on the stream protocol.** The engine consumed the
   input vector once per *output neuron*; the host sent it once per timestep.

v2 fixes all six and raises the capacity that v1's HLS array constants — not
the silicon — had pinned at 256 neurons.

## Contract

- Board part: `xc7z020clg400-1`
- Overlay ID: `snn_overlay_v2`, version `2.0.0`
- Neuron model: LIF with persistent membrane state, shift-based leak, and an
  optional refractory period
- Weight format: `int8`, dense row-major, `post × pre`, delivered from host DDR
  over the engine's own AXI master and cached on-chip
- Max neurons: `4096` total, `1024` per layer
- Max synapses: `262144`
- Max layers (weight matrices): `4`

### Stream protocol

The single source of truth is `hls/snn_overlay_engine.hpp`; the manifest's
`stream_protocol` block mirrors it.

- **Input** — `timestep_count` frames, each of `layer_config[0].input_size`
  words, one word per input neuron. Non-zero means the neuron spiked.
- **Output** — `timestep_count` frames, each of
  `layer_config[layer_count-1].output_size` words, one word per output neuron,
  `1` for a spike. Position carries identity; value carries firing.
- `TLAST` is asserted on the final word of the run and nowhere else, so the
  whole run is one AXI-DMA simple-mode transfer.

Layer sizes come exclusively from the descriptors in `layer_config`. There are
deliberately no redundant neuron-count registers: defect 2 above is what
happens when a size is written down in two places.

## Capacity knob

`OVERLAY_V2_MAX_SYNAPSES` is the on-chip weight cache and the dominant BRAM
consumer, at one byte per synapse. 256 KB is roughly 42% of the xc7z020's block
RAM. **If post-synthesis utilisation reports a BRAM overflow, halve that
constant first** — 131072 still accommodates a 784 → 128 → 10 network.

## Checking behaviour without Vivado

```bash
hls/run_csim_local.sh
```

Compiles the kernel and its testbench with a plain host compiler (via
`hls/csim_compat`, a small stand-in for the Vitis headers) and runs the
behavioural checks: identity mapping, neuron 0 firing, sub-threshold
integration across timesteps, decay when input stops, refractory suppression,
multi-layer chaining, and stream framing. This needs no Vivado and no board.

Vitis HLS runs the same testbench via `csim_design` before synthesis.

## Building the bitstream

Linux x86_64 with Vivado 2022.x and Vitis HLS:

1. `scripts/build_overlay.sh` — runs HLS csim, HLS synthesis, the Vivado
   design, then resolves the manifest's register offsets from the generated
   `.hwh` and verifies them. It exports:
   - `build/out/snn_overlay.bit`
   - `build/out/snn_overlay.hwh`
   - `build/out/overlay_manifest.json`
2. `scripts/stage_overlay.sh` — copies those into the canonical staging
   directory at `../../overlay_staging/pynq_z2/`, from where the backend image
   picks them up.

`scripts/sync_manifest_offsets.py` can also be run standalone with `--check` to
prove a staged manifest still matches its bitstream.

## Layout

- `hls/` — HLS kernel, testbench, HLS build Tcl
- `hls/csim_compat/` — host-build stand-ins for the Vitis headers
- `rtl/` — notes for any RTL wrapper or bridge logic
- `vivado/` — block-design and bitstream build Tcl
- `scripts/` — Linux host build/stage wrappers and the manifest offset sync
- `build/out/` — generated artifacts; not tracked
