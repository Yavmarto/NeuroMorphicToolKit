#pragma once

#include <ap_axi_sdata.h>
#include <ap_int.h>
#include <hls_stream.h>

// ---------------------------------------------------------------------------
// snn_overlay_v2 — fixed-function feedforward LIF engine for PYNQ-Z2
// ---------------------------------------------------------------------------
//
// What changed from v1, and why:
//
//   * v1 declared `weights` as `#pragma HLS INTERFACE bram`, which puts raw
//     BRAM ports on the IP.  The Vivado block design never attached a memory
//     controller to those ports, so every weight the engine read was zero and
//     the board could only ever return silence.  v2 reads weights through an
//     `m_axi` master (host DDR) and caches them in on-chip BRAM at ap_start.
//   * v1 reset the membrane potential for every neuron on every timestep, so
//     it had no state, no leak and no refractory period — a thresholded
//     matrix-multiply, not a spiking neuron.  v2 carries real LIF state across
//     timesteps.
//   * v1 encoded a firing neuron as its own index and silence as 0, making
//     neuron 0 indistinguishable from no spike at all.  v2 emits one word per
//     neuron per timestep, so position carries identity and value carries
//     firing.
//   * v1's engine consumed the input vector once per *output* neuron while the
//     host sent it once per timestep.  v2 fixes the protocol on both sides.
//   * v1 was capped at 256 neurons / 2 populations / one weight matrix by HLS
//     array constants, not by silicon.  v2 raises those.
//
// ---------------------------------------------------------------------------
// Capacity
// ---------------------------------------------------------------------------
//
// OVERLAY_V2_MAX_SYNAPSES is the on-chip weight cache, and is the dominant
// BRAM consumer (one int8 per synapse).  xc7z020 has roughly 612 KB of block
// RAM, so 256 KB of cache is about 42% of the device.  **If post-synthesis
// utilisation reports a BRAM overflow, halve this constant first** — it is the
// intended knob, and 131072 still accommodates a 784 -> 128 -> 10 network.

constexpr int OVERLAY_V2_MAX_NEURONS = 1024;    // per layer
constexpr int OVERLAY_V2_MAX_LAYERS = 4;        // weight matrices in the chain
constexpr int OVERLAY_V2_MAX_SYNAPSES = 262144; // int8 weights, on-chip cache

// Per-layer descriptor, read from host DDR via the `layer_config` master.
// Eight 32-bit words per layer, so layer L starts at word index L * 8.
constexpr int OVERLAY_V2_CONFIG_WORDS_PER_LAYER = 8;

constexpr int OVERLAY_V2_CFG_INPUT_SIZE = 0;   // neurons feeding this layer
constexpr int OVERLAY_V2_CFG_OUTPUT_SIZE = 1;  // neurons in this layer
constexpr int OVERLAY_V2_CFG_WEIGHT_OFFSET = 2; // int8 index into `weights`
constexpr int OVERLAY_V2_CFG_THRESHOLD = 3;    // firing threshold, integer
constexpr int OVERLAY_V2_CFG_LEAK_SHIFT = 4;   // v -= v >> shift; 0 = no leak
constexpr int OVERLAY_V2_CFG_REFRACTORY = 5;   // timesteps silent after firing
constexpr int OVERLAY_V2_CFG_RESERVED_6 = 6;
constexpr int OVERLAY_V2_CFG_RESERVED_7 = 7;

using axis_word_t = ap_axiu<32, 0, 0, 0>;
using axis_stream_t = hls::stream<axis_word_t>;

// ---------------------------------------------------------------------------
// Stream protocol — the single source of truth for both sides
// ---------------------------------------------------------------------------
//
// Input : `timestep_count` frames, each of `layer_config[0].input_size` words,
//         one word per input neuron.  Non-zero means the neuron spiked.
// Output: `timestep_count` frames, each of
//         `layer_config[layer_count-1].output_size` words, one word per output
//         neuron, 1 for a spike and 0 otherwise.  TLAST is asserted on the very
//         last word of the run, and nowhere else, so a single AXI-DMA simple
//         mode transfer covers the whole run.
//
// Layer sizes are taken exclusively from the descriptors.  There are no
// redundant neuron-count registers: v1 shipped a register map whose offsets
// disagreed with the hardware, and the cheapest way not to repeat that is to
// have only one place where a size is written down.

void snn_overlay_engine(
    axis_stream_t& in_stream,
    axis_stream_t& out_stream,
    const ap_int<8>* weights,
    const ap_uint<32>* layer_config,
    unsigned int layer_count,
    unsigned int weight_count,
    unsigned int timestep_count);
