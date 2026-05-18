import nir
import numpy as np
import os
import sys

# Add neurocnl to path if running directly
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../neurocnl')))
from neurocnl.converter.akida_adapter import nir_to_akida

# ---------------------------------------------------------
# 1. LOAD OR CREATE YOUR NIR GRAPH
# ---------------------------------------------------------
# Scenario A: Loading an existing NIR model (e.g., exported from snnTorch/Norse)
# graph = nir.read("my_trained_model.nir")

# Scenario B: For testing, let's just create a mock NIR graph manually.
# Let's say it takes an input of size 10, passes it to a dense layer of 20,
# and fires spiking neurons.
nodes = {
    "input": nir.Input(input_type={'input': np.array([10])}),
    "linear": nir.Affine(
        weight=np.random.randn(20, 10).astype(np.float32),
        bias=np.zeros(20)
    ),
    "lif": nir.IF(r=np.array([1.0]), v_threshold=np.array([1.0])),
    "output": nir.Output(output_type={'output': np.array([20])})
}
edges = [("input", "linear"), ("linear", "lif"), ("lif", "output")]
graph = nir.NIRGraph(nodes=nodes, edges=edges)

print("1. NIR Graph created/loaded successfully.")

# ---------------------------------------------------------
# 2. CONVERT NIR TO AKIDA
# ---------------------------------------------------------
print("2. Converting NIR graph to BrainChip Akida format...")
akida_model = nir_to_akida(graph, weight_bits=8)

# Show the architecture that Akida built
akida_model.summary()

# ---------------------------------------------------------
# 3. RUN / TEST THE AKIDA MODEL
# ---------------------------------------------------------
# Let's create some dummy binary spike data to feed into the chip simulator.
# Akida expects inputs in the shape: (batch_size, width, height, channels)
# Because our input was 1D (size 10), the adapter reshaped it to (1, 1, 10)
dummy_input_spikes = np.random.randint(0, 2, size=(1, 1, 1, 10)).astype(np.uint8)

# Run a forward pass on the Akida software simulator!
print("\n3. Running forward pass on Akida simulator...")
outputs = akida_model.predict(dummy_input_spikes)

print("Akida Output shape:", outputs.shape)
print("Akida Output values:", outputs)

# ---------------------------------------------------------
# 4. SAVE FOR HARDWARE DEPLOYMENT
# ---------------------------------------------------------
# Once tested, save it to BrainChip's native format so you can load it onto the actual PCIe board/edge device.
akida_model.save("nir_to_akida_model.fbz")
print("\n4. Model saved to nir_to_akida_model.fbz ready for hardware.")
