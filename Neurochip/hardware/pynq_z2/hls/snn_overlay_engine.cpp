#include "snn_overlay_engine.hpp"

namespace {

struct LayerDescriptor {
    unsigned int input_size;
    unsigned int output_size;
    unsigned int weight_offset;
    ap_int<32> threshold;
    unsigned int leak_shift;
    ap_uint<8> refractory;
};

unsigned int clamp_u(unsigned int value, unsigned int limit) {
    return (value > limit) ? limit : value;
}

}  // namespace

void snn_overlay_engine(
    axis_stream_t& in_stream,
    axis_stream_t& out_stream,
    const ap_int<8>* weights,
    const ap_uint<32>* layer_config,
    unsigned int layer_count,
    unsigned int weight_count,
    unsigned int timestep_count) {
#pragma HLS INTERFACE axis port=in_stream
#pragma HLS INTERFACE axis port=out_stream
#pragma HLS INTERFACE m_axi port=weights offset=slave bundle=gmem \
    depth=OVERLAY_V2_MAX_SYNAPSES
#pragma HLS INTERFACE m_axi port=layer_config offset=slave bundle=gmem \
    depth=32
#pragma HLS INTERFACE s_axilite port=weights bundle=control
#pragma HLS INTERFACE s_axilite port=layer_config bundle=control
#pragma HLS INTERFACE s_axilite port=layer_count bundle=control
#pragma HLS INTERFACE s_axilite port=weight_count bundle=control
#pragma HLS INTERFACE s_axilite port=timestep_count bundle=control
#pragma HLS INTERFACE s_axilite port=return bundle=control

    // On-chip weight cache.  Weights live in host DDR and are burst-copied here
    // once per run, so the per-timestep inner loop reads BRAM rather than
    // re-fetching the same rows across the AXI master every timestep.
    ap_int<8> weight_cache[OVERLAY_V2_MAX_SYNAPSES];

    // Persistent LIF state.  This is the whole point of v2: it survives across
    // timesteps within a run, and is cleared at ap_start rather than per
    // neuron per timestep.
    ap_int<32> membrane[OVERLAY_V2_MAX_LAYERS][OVERLAY_V2_MAX_NEURONS];
    ap_uint<8> refractory[OVERLAY_V2_MAX_LAYERS][OVERLAY_V2_MAX_NEURONS];

    bool current_spikes[OVERLAY_V2_MAX_NEURONS];
    bool next_spikes[OVERLAY_V2_MAX_NEURONS];

    LayerDescriptor layers[OVERLAY_V2_MAX_LAYERS];

    const unsigned int safe_layer_count =
        (layer_count == 0) ? 1U
                           : clamp_u(layer_count, OVERLAY_V2_MAX_LAYERS);
    const unsigned int cached_weights =
        clamp_u(weight_count, OVERLAY_V2_MAX_SYNAPSES);

load_weights:
    for (unsigned int i = 0; i < cached_weights; ++i) {
#pragma HLS LOOP_TRIPCOUNT min=1024 max=OVERLAY_V2_MAX_SYNAPSES
#pragma HLS PIPELINE II=1
        weight_cache[i] = weights[i];
    }

load_descriptors:
    for (unsigned int layer = 0; layer < safe_layer_count; ++layer) {
#pragma HLS LOOP_TRIPCOUNT min=1 max=OVERLAY_V2_MAX_LAYERS
        const unsigned int base = layer * OVERLAY_V2_CONFIG_WORDS_PER_LAYER;

        layers[layer].input_size = clamp_u(
            layer_config[base + OVERLAY_V2_CFG_INPUT_SIZE].to_uint(),
            OVERLAY_V2_MAX_NEURONS);
        layers[layer].output_size = clamp_u(
            layer_config[base + OVERLAY_V2_CFG_OUTPUT_SIZE].to_uint(),
            OVERLAY_V2_MAX_NEURONS);
        layers[layer].weight_offset = clamp_u(
            layer_config[base + OVERLAY_V2_CFG_WEIGHT_OFFSET].to_uint(),
            OVERLAY_V2_MAX_SYNAPSES);
        layers[layer].threshold = static_cast<ap_int<32> >(
            static_cast<int>(
                layer_config[base + OVERLAY_V2_CFG_THRESHOLD].to_uint()));
        layers[layer].leak_shift = clamp_u(
            layer_config[base + OVERLAY_V2_CFG_LEAK_SHIFT].to_uint(), 31U);
        layers[layer].refractory = static_cast<ap_uint<8> >(clamp_u(
            layer_config[base + OVERLAY_V2_CFG_REFRACTORY].to_uint(), 255U));
    }

reset_state:
    for (unsigned int layer = 0; layer < OVERLAY_V2_MAX_LAYERS; ++layer) {
        for (unsigned int neuron = 0; neuron < OVERLAY_V2_MAX_NEURONS;
             ++neuron) {
#pragma HLS PIPELINE II=1
            membrane[layer][neuron] = 0;
            refractory[layer][neuron] = 0;
        }
    }

    const unsigned int input_size = layers[0].input_size;
    const unsigned int output_size = layers[safe_layer_count - 1].output_size;

timestep_loop:
    for (unsigned int timestep = 0; timestep < timestep_count; ++timestep) {
#pragma HLS LOOP_TRIPCOUNT min=1 max=1000

        // One input frame per timestep — not one per output neuron, which is
        // what v1's engine consumed while the host sent one per timestep.
    read_input:
        for (unsigned int i = 0; i < input_size; ++i) {
#pragma HLS LOOP_TRIPCOUNT min=1 max=OVERLAY_V2_MAX_NEURONS
#pragma HLS PIPELINE II=1
            const axis_word_t input_word = in_stream.read();
            current_spikes[i] = (input_word.data != 0);
        }

    layer_loop:
        for (unsigned int layer = 0; layer < safe_layer_count; ++layer) {
#pragma HLS LOOP_TRIPCOUNT min=1 max=OVERLAY_V2_MAX_LAYERS
            const unsigned int fan_in = layers[layer].input_size;
            const unsigned int fan_out = layers[layer].output_size;
            const unsigned int weight_base = layers[layer].weight_offset;
            const ap_int<32> threshold = layers[layer].threshold;
            const unsigned int leak_shift = layers[layer].leak_shift;
            const ap_uint<8> refractory_reload = layers[layer].refractory;

        neuron_loop:
            for (unsigned int j = 0; j < fan_out; ++j) {
#pragma HLS LOOP_TRIPCOUNT min=1 max=OVERLAY_V2_MAX_NEURONS
                const unsigned int row = weight_base + j * fan_in;

                ap_int<32> accumulator = 0;
            synapse_loop:
                for (unsigned int i = 0; i < fan_in; ++i) {
#pragma HLS LOOP_TRIPCOUNT min=1 max=OVERLAY_V2_MAX_NEURONS
#pragma HLS PIPELINE II=1
                    const unsigned int index = row + i;
                    if (current_spikes[i] &&
                        index < OVERLAY_V2_MAX_SYNAPSES) {
                        accumulator += static_cast<ap_int<32> >(
                            weight_cache[index]);
                    }
                }

                ap_int<32> potential = membrane[layer][j];

                // Leak toward zero.  The shift is arithmetic, so a negative
                // potential decays upward by the same fraction.
                if (leak_shift > 0) {
                    potential -= (potential >> leak_shift);
                }
                potential += accumulator;

                bool fired = false;
                if (refractory[layer][j] > 0) {
                    refractory[layer][j] = refractory[layer][j] - 1;
                    potential = 0;
                } else if (potential >= threshold) {
                    fired = true;
                    potential = 0;  // reset-to-zero
                    refractory[layer][j] = refractory_reload;
                }

                membrane[layer][j] = potential;
                next_spikes[j] = fired;
            }

            // This layer's output becomes the next layer's input.
        forward_spikes:
            for (unsigned int j = 0; j < fan_out; ++j) {
#pragma HLS LOOP_TRIPCOUNT min=1 max=OVERLAY_V2_MAX_NEURONS
#pragma HLS PIPELINE II=1
                current_spikes[j] = next_spikes[j];
            }
        }

        // One word per output neuron: position carries identity, value carries
        // firing.  v1 emitted the neuron index and 0 for silence, which made a
        // firing neuron 0 byte-identical to no spike at all.
    write_output:
        for (unsigned int j = 0; j < output_size; ++j) {
#pragma HLS LOOP_TRIPCOUNT min=1 max=OVERLAY_V2_MAX_NEURONS
#pragma HLS PIPELINE II=1
            axis_word_t output_word;
            output_word.data = current_spikes[j] ? 1 : 0;
            output_word.keep = -1;
            output_word.strb = -1;
            output_word.user = 0;
            output_word.id = 0;
            output_word.dest = 0;
            // TLAST only on the final word of the final timestep, so the whole
            // run is a single AXI-DMA simple-mode transfer.
            output_word.last = ((timestep + 1U == timestep_count) &&
                                (j + 1U == output_size))
                                   ? 1
                                   : 0;
            out_stream.write(output_word);
        }
    }
}
