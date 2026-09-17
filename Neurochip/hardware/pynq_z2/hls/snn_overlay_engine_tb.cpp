// Testbench for snn_overlay_v2.
//
// Runs under Vitis HLS (`csim_design`) and, via hls/csim_compat, under a plain
// host compiler — see hls/run_csim_local.sh.  Overlay-v1's kernel was never
// executed by anything before it was synthesised and shipped; these cases exist
// so that cannot happen again.
//
// Each case names the v1 defect it pins down.

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "snn_overlay_engine.hpp"

namespace {

int failures = 0;

void check(bool condition, const std::string& what) {
    if (!condition) {
        std::printf("  FAIL  %s\n", what.c_str());
        ++failures;
    }
}

struct Layer {
    unsigned int input_size;
    unsigned int output_size;
    unsigned int weight_offset;
    int threshold;
    unsigned int leak_shift;
    unsigned int refractory;
};

std::vector<ap_uint<32> > build_config(const std::vector<Layer>& layers) {
    std::vector<ap_uint<32> > config(
        layers.size() * OVERLAY_V2_CONFIG_WORDS_PER_LAYER, ap_uint<32>(0));
    for (std::size_t index = 0; index < layers.size(); ++index) {
        const std::size_t base = index * OVERLAY_V2_CONFIG_WORDS_PER_LAYER;
        const Layer& layer = layers[index];
        config[base + OVERLAY_V2_CFG_INPUT_SIZE] = layer.input_size;
        config[base + OVERLAY_V2_CFG_OUTPUT_SIZE] = layer.output_size;
        config[base + OVERLAY_V2_CFG_WEIGHT_OFFSET] = layer.weight_offset;
        config[base + OVERLAY_V2_CFG_THRESHOLD] =
            static_cast<unsigned int>(layer.threshold);
        config[base + OVERLAY_V2_CFG_LEAK_SHIFT] = layer.leak_shift;
        config[base + OVERLAY_V2_CFG_REFRACTORY] = layer.refractory;
    }
    return config;
}

// Runs the engine and returns output spikes as [timestep][neuron].
std::vector<std::vector<int> > run_engine(
    const std::vector<Layer>& layers,
    const std::vector<int>& weight_values,
    const std::vector<std::vector<int> >& input_frames) {
    std::vector<ap_int<8> > weights(weight_values.size());
    for (std::size_t i = 0; i < weight_values.size(); ++i) {
        weights[i] = weight_values[i];
    }
    std::vector<ap_uint<32> > config = build_config(layers);

    axis_stream_t in_stream;
    axis_stream_t out_stream;
    for (std::size_t t = 0; t < input_frames.size(); ++t) {
        for (std::size_t i = 0; i < input_frames[t].size(); ++i) {
            axis_word_t word;
            word.data = static_cast<unsigned int>(input_frames[t][i]);
            word.keep = 0xF;
            word.strb = 0xF;
            word.last = 0;
            in_stream.write(word);
        }
    }

    snn_overlay_engine(
        in_stream,
        out_stream,
        weights.empty() ? 0 : &weights[0],
        &config[0],
        static_cast<unsigned int>(layers.size()),
        static_cast<unsigned int>(weights.size()),
        static_cast<unsigned int>(input_frames.size()));

    const unsigned int output_size = layers.back().output_size;
    std::vector<std::vector<int> > frames;
    while (!out_stream.empty()) {
        std::vector<int> frame;
        for (unsigned int j = 0; j < output_size && !out_stream.empty(); ++j) {
            frame.push_back(static_cast<int>(out_stream.read().data));
        }
        frames.push_back(frame);
    }
    return frames;
}

// ---------------------------------------------------------------------------
// v1 defect 1 (weights never reached the engine) and 5 (neuron 0 unrepresentable)
// ---------------------------------------------------------------------------
void test_identity_matrix_and_neuron_zero() {
    std::printf("identity matrix, neuron 0 firing\n");

    // 4 -> 4 identity, weight 10, threshold 10, no leak, no refractory.
    std::vector<Layer> layers;
    Layer layer = {4, 4, 0, 10, 0, 0};
    layers.push_back(layer);

    std::vector<int> weights(16, 0);
    for (int n = 0; n < 4; ++n) {
        weights[n * 4 + n] = 10;
    }

    // Only input neuron 0 spikes.
    std::vector<std::vector<int> > inputs;
    std::vector<int> frame(4, 0);
    frame[0] = 1;
    inputs.push_back(frame);

    std::vector<std::vector<int> > out = run_engine(layers, weights, inputs);

    check(out.size() == 1, "one output frame for one timestep");
    check(out[0].size() == 4, "one output word per neuron");
    check(out[0][0] == 1, "neuron 0 fired and is distinguishable from silence");
    check(out[0][1] == 0 && out[0][2] == 0 && out[0][3] == 0,
          "no other neuron fired");
}

// ---------------------------------------------------------------------------
// v1 defect 4: membrane was reset every timestep, so it could not integrate.
// ---------------------------------------------------------------------------
void test_integrates_across_timesteps() {
    std::printf("sub-threshold input integrates across timesteps\n");

    // Each spike adds 3; threshold is 10.  A stateless engine never fires.
    std::vector<Layer> layers;
    Layer layer = {1, 1, 0, 10, 0, 0};
    layers.push_back(layer);

    std::vector<int> weights(1, 3);
    std::vector<std::vector<int> > inputs(6, std::vector<int>(1, 1));

    std::vector<std::vector<int> > out = run_engine(layers, weights, inputs);

    check(out.size() == 6, "six output frames");
    // 3, 6, 9, 12 -> fires at timestep 3, resets, then 3, 6.
    check(out[0][0] == 0 && out[1][0] == 0 && out[2][0] == 0,
          "stays silent while sub-threshold");
    check(out[3][0] == 1, "fires once the accumulated potential crosses");
    check(out[4][0] == 0 && out[5][0] == 0, "resets after firing");
}

// ---------------------------------------------------------------------------
// v1 defect 4, second half: there was no leak term at all.
// ---------------------------------------------------------------------------
void test_membrane_decays_without_input() {
    std::printf("membrane decays when input stops\n");

    std::vector<Layer> layers;
    Layer leaky = {1, 1, 0, 20, 1, 0};  // halve the potential each timestep
    layers.push_back(leaky);

    std::vector<int> weights(1, 8);

    // Spike, spike, then silence.  8 -> 12 -> 6 -> 3: never reaches 20.
    std::vector<std::vector<int> > inputs;
    inputs.push_back(std::vector<int>(1, 1));
    inputs.push_back(std::vector<int>(1, 1));
    inputs.push_back(std::vector<int>(1, 0));
    inputs.push_back(std::vector<int>(1, 0));

    std::vector<std::vector<int> > leaky_out =
        run_engine(layers, weights, inputs);
    for (std::size_t t = 0; t < leaky_out.size(); ++t) {
        check(leaky_out[t][0] == 0, "a leaky neuron never reaches threshold");
    }

    // The same input with no leak accumulates to 8 -> 16 and holds at 16.
    layers[0].leak_shift = 0;
    std::vector<std::vector<int> > held_out =
        run_engine(layers, weights, inputs);
    for (std::size_t t = 0; t < held_out.size(); ++t) {
        check(held_out[t][0] == 0, "still below threshold without leak");
    }

    // Three spikes with no leak crosses 20; with leak it does not.
    std::vector<std::vector<int> > three(3, std::vector<int>(1, 1));
    std::vector<std::vector<int> > no_leak = run_engine(layers, weights, three);
    check(no_leak[2][0] == 1, "8 + 8 + 8 crosses a threshold of 20");

    layers[0].leak_shift = 1;
    std::vector<std::vector<int> > with_leak =
        run_engine(layers, weights, three);
    check(with_leak[2][0] == 0, "the same input leaks away below threshold");
}

// ---------------------------------------------------------------------------
// Refractory period — new in v2, and the reason `refractory` is a descriptor
// field rather than a hardcoded zero.
// ---------------------------------------------------------------------------
void test_refractory_period_suppresses_firing() {
    std::printf("refractory period suppresses consecutive spikes\n");

    std::vector<Layer> layers;
    Layer layer = {1, 1, 0, 10, 0, 2};  // 2 silent timesteps after each spike
    layers.push_back(layer);

    std::vector<int> weights(1, 100);  // every input spike is supra-threshold
    std::vector<std::vector<int> > inputs(7, std::vector<int>(1, 1));

    std::vector<std::vector<int> > out = run_engine(layers, weights, inputs);

    check(out[0][0] == 1, "fires on the first timestep");
    check(out[1][0] == 0 && out[2][0] == 0, "silent through the refractory period");
    check(out[3][0] == 1, "fires again once refractory expires");
    check(out[4][0] == 0 && out[5][0] == 0, "and is silent again");
    check(out[6][0] == 1, "and fires on the expected cadence");
}

// ---------------------------------------------------------------------------
// Multi-layer chains — v1 supported exactly one weight matrix.
// ---------------------------------------------------------------------------
void test_two_layer_chain() {
    std::printf("two-layer chain with a weight offset\n");

    // 2 -> 2 -> 1.  Layer 0 weights occupy [0, 4), layer 1 occupies [4, 6).
    std::vector<Layer> layers;
    Layer first = {2, 2, 0, 10, 0, 0};
    Layer second = {2, 1, 4, 10, 0, 0};
    layers.push_back(first);
    layers.push_back(second);

    std::vector<int> weights(6, 0);
    weights[0] = 10;  // hidden 0 <- input 0
    weights[1] = 0;
    weights[2] = 0;
    weights[3] = 10;  // hidden 1 <- input 1
    weights[4] = 10;  // output 0 <- hidden 0
    weights[5] = 0;   // output 0 ignores hidden 1

    // Input 0 spikes: hidden 0 fires, output fires.
    std::vector<std::vector<int> > drive_zero;
    std::vector<int> frame_zero(2, 0);
    frame_zero[0] = 1;
    drive_zero.push_back(frame_zero);
    std::vector<std::vector<int> > out_zero =
        run_engine(layers, weights, drive_zero);
    check(out_zero[0].size() == 1, "the last layer sets the output width");
    check(out_zero[0][0] == 1, "a spike propagates through both layers");

    // Input 1 spikes: hidden 1 fires, but the output ignores it.
    std::vector<std::vector<int> > drive_one;
    std::vector<int> frame_one(2, 0);
    frame_one[1] = 1;
    drive_one.push_back(frame_one);
    std::vector<std::vector<int> > out_one =
        run_engine(layers, weights, drive_one);
    check(out_one[0][0] == 0, "the second layer's weights actually gate output");
}

// ---------------------------------------------------------------------------
// v1 defect 6: the two sides disagreed on how many words a run moves.
// ---------------------------------------------------------------------------
void test_stream_framing() {
    std::printf("stream framing is one input frame and one output frame per timestep\n");

    std::vector<Layer> layers;
    Layer layer = {3, 2, 0, 1000, 0, 0};  // threshold high: never fires
    layers.push_back(layer);

    std::vector<int> weights(6, 0);
    std::vector<std::vector<int> > inputs(5, std::vector<int>(3, 0));

    std::vector<ap_int<8> > weight_words(weights.size());
    std::vector<ap_uint<32> > config = build_config(layers);

    axis_stream_t in_stream;
    axis_stream_t out_stream;
    for (std::size_t t = 0; t < inputs.size(); ++t) {
        for (std::size_t i = 0; i < inputs[t].size(); ++i) {
            axis_word_t word;
            word.data = 0;
            in_stream.write(word);
        }
    }

    snn_overlay_engine(in_stream, out_stream, &weight_words[0], &config[0], 1,
                       static_cast<unsigned int>(weight_words.size()), 5);

    check(in_stream.empty(),
          "the engine consumed exactly input_size words per timestep");
    check(out_stream.size() == 10,
          "the engine emitted output_size words per timestep");

    int last_flags = 0;
    std::size_t index = 0;
    const std::size_t total = out_stream.size();
    while (!out_stream.empty()) {
        axis_word_t word = out_stream.read();
        if (word.last != 0) {
            ++last_flags;
            check(index + 1 == total, "TLAST lands on the final word");
        }
        ++index;
    }
    check(last_flags == 1, "TLAST is asserted exactly once for the whole run");
}

}  // namespace

int main() {
    test_identity_matrix_and_neuron_zero();
    test_integrates_across_timesteps();
    test_membrane_decays_without_input();
    test_refractory_period_suppresses_firing();
    test_two_layer_chain();
    test_stream_framing();

    if (failures == 0) {
        std::printf("\nall snn_overlay_v2 checks passed\n");
        return 0;
    }
    std::printf("\n%d snn_overlay_v2 check(s) failed\n", failures);
    return 1;
}
