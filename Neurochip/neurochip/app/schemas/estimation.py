from typing import Any

from pydantic import BaseModel, ConfigDict

from neurochip.contracts.estimation_contracts import LatencyEstimate, PowerEstimate


class NetworkInput(BaseModel):
    """Validated network specification received from HTTP request bodies."""

    model_config = ConfigDict(strict=True)

    num_neurons: int
    num_synapses: int
    neuron_model: str
    populations: list[dict[str, Any]]
    connections: list[dict[str, Any]]
    weight_bit_width: int
    network_depth: int
    stimulus: dict[str, Any] | None = None


__all__ = ["PowerEstimate", "LatencyEstimate", "NetworkInput"]
