# CNL and NIR Explained in Plain English

This document explains, in plain English, what the Computational Network
Language (CNL) is, how it gets turned into a neural circuit file (NIR), and
how that file can be turned back into CNL. No code knowledge is required to
read this.

---

## What problem does this solve?

Neuromorphic hardware — chips that process information the way a brain does —
is extremely powerful, but describing what you want it to do is hard. The
traditional approach is to write low-level configuration files that look more
like assembly language than English. This is error-prone, hard to share, and
nearly impossible to verify against biological intent.

NeuroCNL solves this by letting you describe a neural network in plain English
sentences. Those sentences are then automatically compiled into the exact
binary format that hardware and simulators understand.

---

## What is CNL?

CNL stands for **Computational Network Language**. It is a restricted, formal
subset of English — meaning you write real English sentences, but only certain
sentence shapes are allowed. Think of it like the grammar rules of a contract:
every sentence must follow a specific pattern so that a computer can read it
precisely.

### A CNL sentence looks like this

```
The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
```

Every sentence has the same skeleton:

> **[The / A]** `<what you are describing>` **MUST** `<what it must do>` **[condition or value]**

You can also write **MUST NOT** to express a constraint:

```
The motor neuron MUST NOT respond to input DURING the refractory period
```

### What you can describe

CNL can currently describe 21 types of facts about a neural network. Here are
the most common ones in plain terms:

| What you want to say | CNL concept |
|---|---|
| When a neuron fires | `threshold_firing` |
| How long it rests after firing | `refractory_period` |
| How fast the charge leaks away | `membrane_potential_decay` |
| How strong a connection is | `synaptic_weight` |
| How long a signal takes to travel | `axonal_delay` |
| How the timing of the network is set | `timing_declaration` |
| Whether a connection strengthens or weakens over time | `stdp_learning` |
| Whether a connection is inhibitory (suppressing) | `inhibitory_connection` |
| How many neurons are in a group | `population_coding` / `network_topology` |
| Whether neurons compete with their neighbours | `lateral_inhibition` |
| Whether a neuron tries to keep a steady activity rate | `homeostatic_plasticity` |
| Whether connections get tired or get excited temporarily | `short_term_plasticity` |
| Whether a chemical like Dopamine adjusts connection strengths | `neuromodulation` |
| Whether signals travel through specific receptor types | `receptor_dynamics` |

### What CNL is not

CNL is not a programming language. You do not write loops, functions, or
variables. You write individual sentences, one per biological fact, and the
system assembles them into a complete network description.

CNL is also not a simulation language. It describes *what* the network must
do, not *how* to compute it step by step.

---

## What is NIR?

NIR stands for **Neural Intermediate Representation**. It is a standardised
open file format, used across the neuromorphic research community, that stores
an exact description of a spiking neural network as a mathematical graph.

You can think of a NIR file like a blueprint:

- Every **neuron population** is a node on the blueprint, labelled with
  its exact size, voltage threshold, and leak rate.
- Every **connection** is an arrow between nodes, labelled with an exact
  weight matrix.
- Every **delay** is a small delay box sitting on an arrow.
- Every **input** and **output** port is explicitly marked.

The advantage of NIR is that it is **exact and executable**. Simulators and
hardware backends (Intel Loihi, BrainChip Akida, SpiNNaker, etc.) can read a
NIR file and run the network directly, because every number they need is
right there.

The disadvantage is that NIR is not human-readable. A NIR file looks like a
collection of matrices and node identifiers, not English.

---

## How CNL becomes a NIR graph

When you write a CNL specification, the system converts it to NIR in five
steps. Here is what happens at each step in plain terms.

### Step 1 — Reading your sentences (Parsing)

The system reads your CNL text one line at a time. Each line is matched
against 21 known sentence shapes. If a line matches, the system pulls out the
relevant numbers and names (for example: the neuron name, the threshold
value, the weight). If a line does not match any known shape, the system stops
and tells you exactly which line failed and what it expected instead.

The result is a list of structured facts — like a filled-in form for each
sentence.

### Step 2 — Checking what is exportable (Exportability gate)

Before doing any serious work, the system checks whether every fact you have
written can be represented in NIR at all. Some CNL concepts — like specifying
Akida hardware versions — are handled by a different part of the toolkit and
are not part of the NIR translation path. If you include such a sentence, the
system stops here and tells you clearly which sentences are blocked.

This is a deliberate safety check. The system never silently produces a NIR
file that ignores or misrepresents part of your specification.

### Step 3 — Building the internal blueprint (IR Lowering)

The system now assembles all your facts into an internal blueprint called a
`NetworkIR` (Network Intermediate Representation). Think of this as a
well-organised table that records:

- every neuron population, with all its properties (size, threshold, decay
  rate, etc.)
- every connection between populations, with its weight and any special
  properties (inhibitory, delayed, plastic)
- every timing declaration (how fast the network runs)
- any advisory information that is useful to know but cannot be directly
  expressed as hardware operations (for example, the *intent* behind a
  Dopamine modulation rule)

This internal blueprint is the bridge between your English sentences and the
final NIR file. It is not yet executable — it still contains human-friendly
names and semantic labels — but it is fully structured.

### Step 4 — Building the NIR graph (Materialization)

The system now converts the internal blueprint into an actual NIR graph. This
is where every population becomes a real neuron node with exact tensor shapes,
every connection becomes a real weight matrix, and every delay becomes a
delay node in the graph.

Not every CNL concept maps to an executable NIR operation. The system is
honest about this:

- **Faithfully lowered**: Threshold, membrane decay, synaptic weights,
  inhibitory connections, and axonal delays are turned into exact, executable
  NIR nodes. A simulator running this graph will behave exactly as your CNL
  sentences specified.

- **Stored as metadata**: Refractory periods, STDP learning rules, timing
  declarations, receptor dynamics, and similar concepts are stored as advisory
  notes attached to the relevant nodes. A simulator can read these notes and
  act on them if it supports them, but they do not change the core graph
  topology.

- **Approximated**: Homeostatic plasticity (keeping a steady firing rate) is
  approximated by adjusting the voltage threshold of the neuron. Short-term
  depression is approximated by scaling down the connection weight. Lateral
  inhibition is approximated by adding an inhibitory weight mask between
  neighbouring neurons. These approximations are clearly flagged in the output.

The result is a `nir.NIRGraph` — a valid, standard NIR object that can be
saved to a `.nir` file and given to any NIR-compatible simulator or hardware
tool.

### Step 5 — Saving to disk (optional)

If you asked the system to save the result, it writes the NIR graph to a
`.nir` file using the standard NIR format. This file is portable — you can
give it to a colleague, load it into another tool, or push it to hardware.

---

## What gets lost and why

CNL is *intentionally more expressive* than what NIR can directly execute.
This is by design. You can describe biological intent in CNL that no current
hardware chip can execute natively — and the system still accepts and preserves
that intent, just not as executable operations.

Here is an honest summary of what the current system can and cannot do:

| CNL concept | What happens in NIR | Is it simulated? |
|---|---|---|
| Neuron fires above threshold | Exact threshold in the graph | ✅ Yes |
| Membrane potential decays | Exact time constant in the graph | ✅ Yes |
| Synaptic weights | Exact weight matrix in the graph | ✅ Yes |
| Inhibitory connections | Negative weights in the graph | ✅ Yes |
| Axonal delay | Delay node in the graph | ✅ Yes |
| Refractory period | Advisory note on the neuron node | ⚠️ Simulator-dependent |
| STDP learning rule | Advisory note on the connection | ⚠️ Simulator-dependent |
| Homeostatic plasticity | Threshold adjusted as approximation | ⚠️ Approximate |
| Short-term depression | Weight scaled as approximation | ⚠️ Approximate (only with utilization rate) |
| Receptor dynamics (AMPA, NMDA…) | Advisory note on the connection | ⚠️ Simulator-dependent |
| Neuromodulation (Dopamine…) | Advisory note on the graph | ⚠️ Simulator-dependent |
| Adaptive spiking | Advisory note on the neuron node | ⚠️ Simulator-dependent |
| Background noise | Advisory note on the neuron node | ⚠️ Simulator-dependent |
| Spatial connectivity patterns | Exact weights (one-to-one, binary mask) or advisory | Mixed |

The key principle is: **the system never silently drops or misrepresents
anything you wrote.** If a concept is approximated, it says so. If a concept
is metadata-only, the note is still there for any downstream tool that
understands it.

---

## How a NIR graph becomes CNL (the reverse direction)

It is also possible to go the other way: take an existing NIR graph — perhaps
one exported from another tool like snnTorch or Rockpool — and produce a CNL
description from it. This is called the **NIR → CNL** direction.

This reverse path is useful when:

- A colleague shares a `.nir` file and you want to read and understand it as
  English sentences.
- You have trained a network in a deep learning framework, exported it to NIR,
  and now want to work with it in the CNL Studio.
- You are editing a network visually in the Studio canvas and want the text
  editor to stay in sync.

### What the reverse path does

Reading a NIR graph in reverse follows the same internal logic, but run
backwards:

1. **Every node is classified.** Input nodes become input populations, output
   nodes become output populations, and LIF neuron nodes become named neuron
   populations. The node's exact size, threshold, and decay rate are read
   from the graph.

2. **Every connection is summarised.** Weight matrices are inspected to
   determine whether the connection is excitatory or inhibitory, and how
   large the weight footprint is. Delay nodes become axonal delay sentences.

3. **Metadata is recovered.** If the NIR file was originally produced by
   NeuroCNL, it contains embedded notes (the advisory metadata from step 4
   above) that allow the reverse path to recover things like STDP learning
   rules and timing declarations as proper CNL sentences. If the file came
   from a different tool, the metadata may not be present, and those
   sentences will not be generated.

4. **CNL sentences are generated.** The system writes a valid CNL
   specification describing the network. For things it cannot exactly
   recover (for example, if the weight matrix is a large trained tensor and
   not a simple scalar), it writes a conservative summary sentence that
   describes the structure and topology honestly.

5. **Approximations are flagged.** Any sentence that is a summary or
   approximation rather than an exact recovery is marked clearly, both in the
   text and in diagnostic output, so you know exactly how faithful the
   translation was.

### What does not round-trip perfectly

The reverse direction is intentionally conservative. There are things it will
not pretend to recover:

- **Exact large weight matrices** are described by their shape and statistics,
  not reproduced inline as CNL sentences. CNL is a specification language, not
  a weight serialisation format.
- **Custom NIR node types** (for example, Conv2d, or hardware-specific nodes)
  that have no CNL equivalent produce a fallback description sentence and a
  warning, rather than a fake match.
- **Biological semantics** that were only approximated in the forward direction
  (homeostatic plasticity, short-term depression) will be noted as
  approximately recovered when read back.

The goal is an honest, readable summary — not a byte-perfect reproduction of
something that was never stored as exact English in the first place.

---

## The two-file model

When you compile a CNL specification, you can produce two artifacts:

| File | What it contains | Who reads it |
|---|---|---|
| `model.nir` | The exact graph: tensor shapes, weight matrices, node topology | Simulators, hardware, other NIR tools |
| `model.cnl` | The human-readable description: what the network does and why | Researchers, collaborators, the CNL Studio editor |

These two files are complementary. The `.nir` file is the authoritative
execution artifact. The `.cnl` file is the authoritative intent artifact.
Together they give you both machine precision and human legibility.

When you load a `.nir` file back into the Studio, the system regenerates the
`.cnl` view automatically using the reverse translation described above.

---

## A complete example

Suppose you want to describe a simple two-population sensory-to-motor circuit.
Here is what the full journey looks like.

### You write this CNL specification

```
# A simple sensory-to-motor reflex arc
The network MUST operate WITH timestep of 1 ms

The network MUST contain an excitatory sensory population of 4 neurons
The network MUST contain an excitatory motor population of 2 neurons

The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0

The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds
The motor neuron membrane potential MUST decay WITH time constant of 0.02 seconds

The connection from sensory to motor MUST have WITH synaptic weight of 0.8
The connection from sensory to motor MUST transmit WITH delay of 5ms

A synapse MUST strengthen IF pre-synaptic spike precedes post-synaptic spike by less than 20ms
```

### What the system produces

**NIR graph nodes:**

| Node name | Type | What it represents |
|---|---|---|
| `sensory` | `nir.Input` + `nir.LIF` | 4 sensory neurons, threshold 1.0, tau 20 ms |
| `weight_sensory_to_motor` | `nir.Linear` | 4 × 2 weight matrix, all entries 0.8 |
| `delay_sensory_to_motor` | `nir.Delay` | 5 ms axonal delay |
| `motor` | `nir.LIF` + `nir.Output` | 2 motor neurons, threshold 1.0, tau 20 ms |

**Fidelity report:**

- Threshold: ✅ exact
- Membrane decay: ✅ exact
- Synaptic weight: ✅ exact
- Axonal delay: ✅ exact
- STDP rule: ⚠️ stored as advisory metadata (not executable in this graph)

### If someone loads the `.nir` file and reads it back

The reverse translation produces:

```
The network MUST contain an excitatory sensory population of 4 neurons
The network MUST contain an excitatory motor population of 2 neurons
The sensory neuron MUST fire ONLY IF membrane potential exceeds 1.0
The motor neuron MUST fire ONLY IF membrane potential exceeds 1.0
The sensory neuron membrane potential MUST decay WITH time constant of 0.02 seconds
The motor neuron membrane potential MUST decay WITH time constant of 0.02 seconds
The connection from sensory to motor MUST have WITH synaptic weight of 0.8
The connection from sensory to motor MUST transmit WITH delay of 5ms
# STDP learning rule recovered from graph metadata:
A synapse MUST strengthen IF pre-synaptic spike precedes post-synaptic spike by less than 20ms
```

The timing declaration (`timestep of 1 ms`) is also recovered from graph
metadata if the `.nir` file was produced by NeuroCNL.

> **Which grammar is this?** The example above uses the legacy,
> biological-style grammar (`MUST`/`WITH` sentences, parsed by
> `cnl_parser.py`) — a separate pipeline from the `nir_cnl` dialect that
> CNL Studio's actual notebook-generation path (`compile_to_nir` →
> `backend/app/routers/notebook.py`) compiles. `compile_to_nir` rejects
> this grammar outright with an actionable `legacy_grammar` error.
> `nir_cnl`'s equivalent declarative style looks like this instead:
>
> ```
> Define a network named reflex_arc with timestep 0.001.
> Define an input port named input with shape (4,).
> Define a LIF neuron named sensory with time constant 0.02, resistance 1.0,
>   leak voltage 0.0, and firing threshold 1.0.
> Define an output port named output with shape (2,).
> input connects to sensory.
> sensory connects to output.
> ```
>
> The optional `with timestep <seconds>` clause on the network sentence
> is what lets a declared timestep reach `nir.LIF` node
> `metadata["dt"]` and, from there, every backend's `beta`/`threshold`
> conversion (`neurocnl/lif_semantics.py`) — the training notebook and
> all three simulators read the same value. Without it, the conversion
> falls back to `1e-4`, which for the `tau`/`threshold` values used
> above produces an effectively unreachable firing threshold (the neuron
> never spikes). Declare a timestep roughly a tenth of your neurons'
> time constant to keep training viable.

---

## Summary

- **CNL** is plain English with strict grammar rules that let you describe a
  spiking neural network in human-readable sentences.
- **NIR** is a standard open file format that stores the same network as an
  exact mathematical graph that hardware and simulators can execute directly.
- **CNL → NIR** compilation takes your English sentences, checks them,
  assembles them into an internal blueprint, and then generates an exact NIR
  graph. Some biological concepts are represented exactly; others are
  approximated or stored as advisory notes, always transparently.
- **NIR → CNL** reverse translation reads an existing NIR graph, classifies
  its nodes and connections, and generates readable CNL sentences. It is
  honest about what it can recover exactly versus what it can only summarise.
- The system never silently drops or misrepresents anything. If something
  cannot be represented faithfully, it says so explicitly.
