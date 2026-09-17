# ADR 0010: PYNQ Overlay v1.0.1 Word-MMIO Contract

## Status

Accepted

## Context

The staged `snn_overlay_v1` bitstream exposes a 64 KiB AXI-Lite register
window for `snn_engine_0`. Earlier software contracts advertised 65,536
synapses with `int8` byte stride, but the board runtime wrote weights through
the AXI-Lite word interface. With `weight_base_offset = 0x1000`, that address
space can safely hold only `(0x10000 - 0x1000) / 4 = 15360` word-spaced weight
entries.

Keeping the 65,536 claim would require a rebuilt overlay that exposes the full
weight BRAM to the processing system or a separate loader path for that memory.
This cleanup intentionally avoids a bitstream rebuild.

## Decision

Overlay `snn_overlay_v1` version `1.0.1` defines the conservative deployable
software contract:

- max synapses: `15360`
- `register_map.weight_base_offset`: `0x1000`
- `weight_layout.format`: `int8_dense_row_major_word_mmio`
- `weight_layout.stride_bytes`: `4`
- weights remain signed int8 values, written into the low byte of each 32-bit
  MMIO word

Neurochip, NeuroCNL, launcher UI models, staged manifests, and tests must use
this contract as the source of truth until a BRAM-accessible overlay supersedes
it.

## Consequences

The deploy path becomes truthful for the current installed overlay assets and
cannot write past the SNN IP register window. Some networks previously marked
exportable under the 65,536-synapse claim are now rejected at export time. A
future overlay version may restore the larger capacity, but only with matching
bitstream, manifest, runtime writer, and cross-module tests.
