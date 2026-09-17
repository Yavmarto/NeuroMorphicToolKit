# Working NeuroCNL Examples

Here are three complete examples that successfully pass all parsing, Layer 1 (physics), and Layer 2 (structural) validations.

## 1. Simple Sensory-Motor Relay
This specifies the complete behavior for both a sensory neuron and a motor neuron, including their connection. Both neurons define their threshold, refractory period, and membrane decay.

```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds
The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0
The motor neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The motor neuron membrane potential MUST decay WITH time constant of 0.02 seconds
The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 1.0
```

## 2. Incorporating an Interneuron
This expands the network by adding an intermediate interneuron between the sensory and motor output. Note how each defined component has its connections properly mapped so that no nodes are left "dangling".

```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds

The interneuron MUST fire ONLY IF membrane potential exceeds 1.0
The interneuron MUST NOT fire DURING the refractory period of 0.002 seconds
The interneuron membrane potential MUST decay WITH time constant of 0.02 seconds

The motor neuron MUST fire ONLY IF membrane potential exceeds 0.8
The motor neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The motor neuron membrane potential MUST decay WITH time constant of 0.02 seconds

The connection from sensory neuron to interneuron MUST have WITH synaptic weight of 1.2
The connection from interneuron to motor neuron MUST have WITH synaptic weight of 0.8
```

## 3. Applying STDP (Plasticity)
This network adds synaptic learning rules (STDP) to the connection, which is completely valid.

```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
The sensory neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds

The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0
The motor neuron MUST NOT fire DURING the refractory period of 0.002 seconds
The motor neuron membrane potential MUST decay WITH time constant of 0.02 seconds

The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 0.5
A synapse MUST strengthen IF pre-synaptic spike precedes post-synaptic spike by less than 20ms
```
