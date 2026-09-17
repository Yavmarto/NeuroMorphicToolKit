"""Shared spike-train stimulus helpers for the CNL → NIR → Simulator pipeline.

Two public functions are provided:

:func:`parse_stimulus`
    Validate an explicit :class:`StimulusSpec` from the API request against
    the compiled NIR graph and return a :class:`ValidatedStimulus` ready for
    simulator dispatch.

:func:`generate_default_stimulus`
    Generate a small, deterministic Poisson-like spike train for the first
    ``nir.Input`` node in the graph.  The output is identical for the same
    (``seed``, ``timesteps``, ``input_size``) triple, making local runs fully
    reproducible.

Both functions raise :class:`StimulusError` with a structured
``diagnostics`` list when they detect an invalid population name or
out-of-range neuron index, so callers can surface actionable messages
without catching generic exceptions.
"""

from __future__ import annotations

import random
from dataclasses import dataclass, field

import nir

# ---------------------------------------------------------------------------
# Public data types
# ---------------------------------------------------------------------------


@dataclass(slots=True)
class ValidatedStimulus:
    """Spike-train stimulus that has been validated against a compiled NIR graph.

    Attributes
    ----------
    population : str
        Name of the ``nir.Input`` node that receives the stimulus.
    neuron_count : int
        Number of neurons in the input population.
    spikes : dict[int, list[int]]
        Neuron index → list of integer timesteps at which it fires.
    """

    population: str
    neuron_count: int
    spikes: dict[int, list[int]] = field(default_factory=dict)


class StimulusError(ValueError):
    """Raised when stimulus validation fails.

    Attributes
    ----------
    diagnostics : list[str]
        Human-readable messages, one per detected problem.
    """

    def __init__(self, diagnostics: list[str]) -> None:
        self.diagnostics = diagnostics
        super().__init__("; ".join(diagnostics))


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _find_input_nodes(graph: nir.NIRGraph) -> dict[str, nir.NIRNode]:
    """Return all ``nir.Input`` nodes from the graph, keyed by node name."""
    return {
        name: node for name, node in graph.nodes.items() if isinstance(node, nir.Input)
    }


def _neuron_count(node: nir.NIRNode) -> int:
    """Infer the neuron count for an Input node from its ``input_type`` shape.

    In the NIR library, ``nir.Input.input_type`` is always a dict mapping
    port name → shape array (e.g. ``{'input': array([2])}``).  This helper
    reads the first shape array and returns its leading dimension.
    """
    try:
        input_type = node.input_type
        if isinstance(input_type, dict) and input_type:
            shape = next(iter(input_type.values()))
            if hasattr(shape, "__len__") and len(shape) > 0:
                return int(shape[0])
        elif hasattr(input_type, "__len__") and len(input_type) > 0:
            # Fallback: bare array shape (future-proofing)
            return int(input_type[0])
    except (AttributeError, TypeError, IndexError, StopIteration):
        pass
    return 1  # conservative fallback


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def parse_stimulus(
    stimulus_spec: dict[str, object],
    graph: nir.NIRGraph,
) -> ValidatedStimulus:
    """Validate and parse an explicit spike-train stimulus spec.

    Parameters
    ----------
    stimulus_spec : dict
        A dict matching the ``StimulusSpec`` shape:
        ``{"type": "spike_train", "population": str, "spikes": {str: [int]}}``.
    graph : nir.NIRGraph
        The compiled NIR graph returned by :func:`neurocnl.compile_to_nir`.

    Returns
    -------
    ValidatedStimulus
        Validated stimulus ready for simulator dispatch.

    Raises
    ------
    StimulusError
        If the population name is not an ``nir.Input`` node in the graph, or
        if any neuron index is out of range.
    """
    diagnostics: list[str] = []

    population = stimulus_spec.get("population", "")
    if not isinstance(population, str) or not population:
        diagnostics.append("stimulus.population must be a non-empty string.")

    raw_spikes = stimulus_spec.get("spikes", {})
    if not isinstance(raw_spikes, dict):
        diagnostics.append(
            "stimulus.spikes must be a dict mapping neuron index to timestep list."
        )
        raw_spikes = {}

    if diagnostics:
        raise StimulusError(diagnostics)

    # Validate population exists and is an Input node
    input_nodes = _find_input_nodes(graph)
    if population not in input_nodes:
        available = sorted(input_nodes) or ["<none>"]
        diagnostics.append(
            f"Stimulus population {population!r} is not an nir.Input node in the compiled graph. "
            f"Available input populations: {', '.join(available)}."
        )
        raise StimulusError(diagnostics)

    n_neurons = _neuron_count(input_nodes[population])

    # Validate neuron indices and timestep values
    parsed_spikes: dict[int, list[int]] = {}
    for idx_str, ts_list in raw_spikes.items():
        try:
            idx = int(idx_str)
        except (ValueError, TypeError):
            diagnostics.append(
                f"Neuron index {idx_str!r} in stimulus.spikes must be an integer string."
            )
            continue

        if idx < 0 or idx >= n_neurons:
            diagnostics.append(
                f"Neuron index {idx} is out of range for population {population!r} "
                f"(size {n_neurons}).  Valid range: 0–{n_neurons - 1}."
            )
            continue

        if not isinstance(ts_list, list) or not all(
            isinstance(t, int) for t in ts_list
        ):
            diagnostics.append(
                f"Spike times for neuron {idx} must be a list of integers."
            )
            continue

        parsed_spikes[idx] = sorted(ts_list)

    if diagnostics:
        raise StimulusError(diagnostics)

    return ValidatedStimulus(
        population=population,
        neuron_count=n_neurons,
        spikes=parsed_spikes,
    )


def generate_default_stimulus(
    graph: nir.NIRGraph,
    timesteps: int,
    seed: int,
    firing_rate: float = 0.3,
) -> ValidatedStimulus:
    """Generate a deterministic default spike train for the first Input node.

    The spike train is a low-rate Poisson-like process generated from the
    provided seed so that every run with the same (seed, timesteps, graph)
    triple produces identical output.

    Parameters
    ----------
    graph : nir.NIRGraph
        The compiled NIR graph returned by :func:`neurocnl.compile_to_nir`.
    timesteps : int
        Total number of simulation timesteps.
    seed : int
        Random seed.  The same seed always produces the same spike train.
    firing_rate : float
        Poisson firing probability per neuron per timestep.  Higher values
        produce denser spike trains and more visible output activity.
        Defaults to 0.3 (30% chance per timestep).

    Returns
    -------
    ValidatedStimulus
        A stimulus for the first ``nir.Input`` node in the graph.

    Raises
    ------
    StimulusError
        If the graph contains no ``nir.Input`` nodes.
    """
    input_nodes = _find_input_nodes(graph)
    if not input_nodes:
        raise StimulusError(["The compiled NIR graph contains no nir.Input nodes."])

    # Use the first input node (deterministic: sorted by name)
    population = sorted(input_nodes)[0]
    n_neurons = _neuron_count(input_nodes[population])

    rng = random.Random(seed)
    spikes: dict[int, list[int]] = {}
    for neuron_idx in range(n_neurons):
        neuron_spikes = [t for t in range(timesteps) if rng.random() < firing_rate]
        if neuron_spikes:
            spikes[neuron_idx] = neuron_spikes

    return ValidatedStimulus(
        population=population,
        neuron_count=n_neurons,
        spikes=spikes,
    )
