"""SpiNNaker2 backend for Neurosim."""

import logging
import uuid
from typing import Any

# Attempt to import py-spinnaker2 with graceful degradation
try:
    import spinnaker2
    from spinnaker2 import hardware, network

    SPINNAKER2_AVAILABLE = True
except ImportError:
    SPINNAKER2_AVAILABLE = False

from neurosim.contracts.design_contracts import CanvasGraph

logger = logging.getLogger(__name__)


class SpiNNaker2SimBackend:
    """Backend for running spiking neural network simulations on SpiNNaker2.

    This class handles the conversion from Neurosim's CanvasGraph to a
    py-spinnaker2 network, configures the execution environment (hardware
    or fallback), and extracts spike/voltage recordings back to Neurosim formats.
    """

    def __init__(self, *, mock_mode: bool = False) -> None:
        """Initialize the backend."""
        self.network: Any = None
        self.probes: dict[str, Any] = {}
        self.populations: dict[str, Any] = {}
        self.run_id: str | None = None
        self.duration_ms: float = 0
        self.simulator: Any = None
        self._mock_mode = mock_mode

    def load(self, graph: CanvasGraph) -> None:
        """Load a Neurosim CanvasGraph into a SpiNNaker2 network.

        Args:
            graph: The CanvasGraph representing the network.
        """
        if not SPINNAKER2_AVAILABLE:
            logger.warning("py-spinnaker2 not available. Hardware features will be mocked.")

        self.run_id = str(uuid.uuid4())
        self.populations = {}
        self.probes = {}

        if SPINNAKER2_AVAILABLE:
            self.network = network.Network()

        # Parse populations
        for node in graph.nodes:
            n_neurons = max(1, int(node.parameters.get("n_neurons", 100)))
            self.populations[node.id] = {"n_neurons": n_neurons}

            if SPINNAKER2_AVAILABLE:
                # In a real integration, we'd map node.component_id to specific cell types
                # e.g. spinnaker2.cell_models.LIF
                pop = spinnaker2.Population(size=n_neurons, name=node.id)
                self.network.add(pop)
                self.populations[node.id]["pop"] = pop

                # Setup probes for recording if requested or by default
                pop.record(["spikes", "v"])

        # Parse projections
        for edge in graph.edges:
            source_id = edge.source_node_id
            target_id = edge.target_node_id
            weight = edge.parameters.get("weight", 1.0)
            delay = edge.parameters.get("delay", 1.0)

            if (
                SPINNAKER2_AVAILABLE
                and source_id in self.populations
                and target_id in self.populations
            ):
                source_pop = self.populations[source_id]["pop"]
                target_pop = self.populations[target_id]["pop"]

                # In a real integration, we'd map edge.component_id to specific synapse types
                proj = spinnaker2.Projection(
                    source=source_pop,
                    target=target_pop,
                    connector=spinnaker2.connectors.AllToAll(),
                    synapse_type=spinnaker2.synapse_types.StaticSynapse(weight=weight, delay=delay),
                )
                self.network.add(proj)

    def run(self, duration_ms: float) -> str:
        """Run the simulation for the given duration.

        Args:
            duration_ms: The duration to simulate in milliseconds.

        Returns:
            The run_id for retrieving results later.
        """
        self.duration_ms = duration_ms
        if not SPINNAKER2_AVAILABLE:
            if not self._mock_mode:
                raise RuntimeError(
                    "SpiNNaker2 SDK (py-spinnaker2) is not installed. Cannot run hardware "
                    "simulation. Install py-spinnaker2 or set mock_mode=True for local testing."
                )
            logger.warning("Running in explicit mock mode; SpiNNaker2 results are synthetic.")
        else:
            logger.info("Executing on SpiNNaker2 backend for %.2f ms", duration_ms)
            if self.network:
                self.simulator = hardware.Simulator()
                self.simulator.run(self.network, duration_ms)

        if self.run_id is None:
            self.run_id = str(uuid.uuid4())
        return self.run_id

    def get_results(self) -> dict[str, Any]:
        """Retrieve the simulation results mapped to Neurosim's internal format.

        Returns:
            A dictionary containing spike times and voltage traces per node.
        """
        results: dict[str, Any] = {}
        for node_id, pop_info in self.populations.items():
            n_neurons = pop_info["n_neurons"]

            if SPINNAKER2_AVAILABLE and "pop" in pop_info and self.simulator:
                pop = pop_info["pop"]
                try:
                    spikes = pop.get_data("spikes")
                    voltage = pop.get_data("v")
                    # Real data mapping would depend on the format returned by spinnaker2
                    results[node_id] = {
                        "spikes": (
                            spikes if spikes is not None else [[] for _ in range(n_neurons)]
                        ),
                        "voltage": (
                            voltage
                            if voltage is not None
                            else [[0.0] * 10 for _ in range(min(5, n_neurons))]
                        ),
                    }
                except Exception as e:
                    logger.warning("Failed to retrieve data for %s: %s", node_id, e)
                    results[node_id] = {
                        "spikes": [[] for _ in range(n_neurons)],
                        "voltage": [[0.0] * 10 for _ in range(min(5, n_neurons))],
                    }
            else:
                # Mock results for demonstration or fallback
                results[node_id] = {
                    "spikes": [[] for _ in range(n_neurons)],
                    "voltage": [[0.0] * 10 for _ in range(min(5, n_neurons))],
                }
        return results

    def reset(self) -> None:
        """Reset the backend state for a new simulation."""
        self.network = None
        self.probes = {}
        self.populations = {}
        self.run_id = None
        self.duration_ms = 0
        self.simulator = None
