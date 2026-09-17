"""Smoke-test the NIR -> Akida converter end to end.

Run inside an environment that has the Akida SDK (the Jupyter image does):

    python scripts/akida_nir_demo.py

This mirrors what the `Akida Exporter` pipeline node does after training, minus
the trained weights: quantize inputs, calibrate the activation steps, convert,
run on the software simulator, save. No hardware required.
"""

import os
import sys

import nir
import numpy as np

sys.path.insert(
    0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../neurocnl"))
)

from neurocnl.converter.akida_adapter import (
    calibrate_act_steps,
    nir_to_akida,
    quantize_inputs,
)

# A real run would start from a trained graph instead:
#     graph = nir.read("model.nir")
IN_FEATURES, OUT_FEATURES = 10, 20
rng = np.random.default_rng(0)
graph = nir.NIRGraph(
    nodes={
        "input": nir.Input(input_type={"input": np.array([IN_FEATURES])}),
        "linear": nir.Affine(
            weight=rng.normal(0, 0.3, (OUT_FEATURES, IN_FEATURES)).astype(np.float32),
            bias=np.zeros(OUT_FEATURES, dtype=np.float32),
        ),
        "lif": nir.IF(r=np.ones(OUT_FEATURES), v_threshold=np.ones(OUT_FEATURES)),
        "output": nir.Output(output_type={"output": np.array([OUT_FEATURES])}),
    },
    edges=[("input", "linear"), ("linear", "lif"), ("lif", "output")],
    type_check=False,
)
print("1. NIR graph ready.")

# Akida takes uint8 in (batch, 1, 1, features); the scale is needed so the
# converter can express thresholds in the same quantized units as the weights.
samples, input_scale = quantize_inputs(
    np.abs(rng.normal(0, 1, (32, IN_FEATURES))), input_bits=4
)

# Without this every layer keeps act_step = 1 and saturates on every sample.
print("2. Calibrating activation steps...")
act_steps = calibrate_act_steps(graph, samples, weight_bits=4, input_scale=input_scale)

print("3. Converting to Akida...")
model = nir_to_akida(graph, weight_bits=4, input_scale=input_scale, act_steps=act_steps)
model.summary()

print("4. Running on the Akida software simulator...")
outputs = np.asarray(model.forward(samples))
print("   output shape:", outputs.shape)
print("   saturated fraction:", f"{(outputs == 15).mean():.1%}")

model.save("nir_to_akida_model.fbz")
print("5. Saved nir_to_akida_model.fbz")
