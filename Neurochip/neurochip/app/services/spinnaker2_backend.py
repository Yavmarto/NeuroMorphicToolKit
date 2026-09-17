import asyncio
import json
import logging
import os
from collections.abc import AsyncGenerator
from typing import Any

from ..schemas.estimation import NetworkInput

logger = logging.getLogger(__name__)

try:
    import spinnaker2.brian2_sim as b2_sim  # type: ignore[import-not-found]
    import spinnaker2.hardware as hw  # type: ignore[import-not-found]
    import spinnaker2.snn as snn  # type: ignore[import-not-found]

    SPINNAKER2_AVAILABLE = True
except ImportError:
    SPINNAKER2_AVAILABLE = False


class SpiNNaker2Backend:
    """
    Service for interacting with SpiNNaker2 hardware via py-spinnaker2.
    """

    def __init__(self, config_path: str | None = None):
        """
        Initialize the backend, optionally overriding the global hardware configuration path.
        """
        if config_path:
            os.environ["SPINNAKER_CONFIG_PATH"] = config_path

        self.config_path = os.environ.get("SPINNAKER_CONFIG_PATH")
        self.board_mappings = {}
        if self.config_path and os.path.exists(self.config_path):
            try:
                with open(self.config_path) as f:
                    self.board_mappings = json.load(f)
            except Exception as e:
                logger.warning(
                    "Could not load SPINNAKER_CONFIG_PATH %s: %s",
                    self.config_path,
                    e,
                )

    def _resolve_host(self, board_id: str | None) -> str | None:
        if not board_id:
            return None
        host = self.board_mappings.get(board_id, board_id)
        return host if isinstance(host, str) else None

    def compile_network(self, network_input: NetworkInput) -> Any:
        """
        Compile a Neurochip NetworkInput into a py-spinnaker2 snn.Network.

        Args:
            network_input: The input network definition.

        Returns:
            An instance of spinnaker2.snn.Network representing the compiled network.
        """
        if not SPINNAKER2_AVAILABLE:
            logger.warning("py-spinnaker2 not installed. Returning mock compiled network.")
            return {"compiled": True, "network": network_input.num_neurons, "mock": True}

        logger.info(
            "Compiling network with %s neurons for SpiNNaker2",
            network_input.num_neurons,
        )
        net = snn.Network("neurochip_network")

        populations = {}
        for i, pop_def in enumerate(network_input.populations):
            pop_id = pop_def.get("id", str(i))
            size = pop_def.get("size", 100)

            # Configure multi-core mapping explicitly scaling populations respecting boundary partitions
            max_neurons_per_core = pop_def.get("max_neurons_per_core", 256)

            pop = snn.Population(
                size,
                snn.LIF,
                name=f"pop_{pop_id}",
                max_neurons_per_core=max_neurons_per_core,
                record=["spikes"],
            )
            net.add(pop)
            populations[pop_id] = pop

        for proj_def in network_input.connections:
            pre_id = str(proj_def.get("pre"))
            post_id = str(proj_def.get("post"))
            if pre_id in populations and post_id in populations:
                proj = snn.Projection(
                    populations[pre_id],
                    populations[post_id],
                    snn.AllToAllConnector(),
                    synapse_type=snn.StaticSynapse(weight=1.0, delay=1.0),
                )
                net.add(proj)

        return net

    def run_network(
        self, compiled_network: Any, timesteps: int, board_id: str | None = None
    ) -> dict[str, Any]:
        """
        Execute the compiled network on the SpiNNaker2 board.

        Args:
            compiled_network: The network compiled by `compile_network`.
            timesteps: The number of simulation timesteps to run.
            board_id: Optional ID or hostname to select specific hardware from the config.

        Returns:
            A dictionary containing the simulation results (spikes, voltages).
        """
        if not SPINNAKER2_AVAILABLE or isinstance(compiled_network, dict):
            logger.info(
                "Running mock network on SpiNNaker2 for %s timesteps on board %s",
                timesteps,
                board_id,
            )
            return {
                "status": "success",
                "spikes": {"0": [10, 20]},
                "voltages": {},
            }

        logger.info(
            "Running network on SpiNNaker2 hardware for %s timesteps on board %s",
            timesteps,
            board_id,
        )
        try:
            host_ip = self._resolve_host(board_id)
            chip = hw.SpiNNaker2Chip(host=host_ip) if host_ip else hw.SpiNNaker2Chip()
            chip.run(compiled_network, timesteps)

            spikes = {}
            for pop in compiled_network.populations:
                spikes[pop.name] = pop.get_spikes()

            return {
                "status": "success",
                "spikes": spikes,
                "voltages": {},
            }
        except Exception as e:
            logger.error(
                "Hardware execution failed: %s. Falling back to brian2_sim emulation.",
                e,
            )
            try:
                b2_sim.run(compiled_network, timesteps)
                spikes = {}
                for pop in compiled_network.populations:
                    spikes[pop.name] = pop.get_spikes()
                return {"status": "success", "spikes": spikes, "voltages": {}, "emulation": True}
            except Exception as sim_e:
                logger.error("Fallback emulation also failed: %s", sim_e)
                raise RuntimeError(f"Both hardware and emulation failed: {e} | {sim_e}")

    async def stream_spikes(
        self, compiled_network: Any, timesteps: int, board_id: str | None = None
    ) -> AsyncGenerator[dict[str, Any], None]:
        """
        Integrate stream processing capabilities mapping spikes through Host-driven Spike Replicator methods.
        """
        if not SPINNAKER2_AVAILABLE or isinstance(compiled_network, dict):
            # Mock streaming
            for t in range(timesteps):
                await asyncio.sleep(0.01)
                yield {"time": t, "events": [{"pop_id": "0", "neuron_id": 5, "type": "spike"}]}
            return

        logger.info(
            "Streaming network events from SpiNNaker2 hardware for %s timesteps",
            timesteps,
        )

        try:
            host_ip = self._resolve_host(board_id)
            chip = hw.SpiNNaker2Chip(host=host_ip) if host_ip else hw.SpiNNaker2Chip()
            # Start the run asynchronously or in streaming mode if supported
            # Here we simulate fetching from Host-driven Spike Replicator via a generator
            chip.start_run(compiled_network, timesteps)

            while chip.is_running():
                events = chip.get_recent_spikes()
                if events:
                    yield {"events": events}
                await asyncio.sleep(0.05)

            # Yield final batch
            final_events = chip.get_recent_spikes()
            if final_events:
                yield {"events": final_events}

        except Exception as e:
            logger.error("Streaming hardware execution failed: %s", e)
            yield {"error": str(e)}
