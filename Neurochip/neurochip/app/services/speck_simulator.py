"""Speck Simulator — test double for CI environments without the Speck SDK.

State machine:  UNINITIALIZED → CONSTRUCTED → MAPPED → (RUNNING → MAPPED)
"""

from __future__ import annotations

import logging
import time
from enum import Enum, auto
from typing import Any

from .speck_errors import (
    SpeckConfigurationError,
    SpeckInferenceError,
)

logger = logging.getLogger(__name__)


class SpeckState(Enum):
    """Lifecycle states for the Speck backend."""

    UNINITIALIZED = auto()
    CONSTRUCTED = auto()
    MAPPED = auto()
    RUNNING = auto()


class SpeckSimulator:
    """In-process Speck simulator for CI and offline development.

    Mimics model construction, device mapping, and inference execution
    using a simple leaky integrate-and-fire (LIF) neuron model.
    """

    def __init__(self) -> None:
        self.state: SpeckState = SpeckState.UNINITIALIZED
        self._populations: list[dict[str, Any]] = []
        self._connections: list[dict[str, Any]] = []
        self._network_summary: dict[str, Any] = {}
        self._threshold: float = 1.0

    def construct_model(self, mapped_network: dict[str, Any]) -> None:
        """Build a simulated model from a mapped network payload."""
        populations = mapped_network.get("populations", [])
        connections = mapped_network.get("connections", [])

        if not populations:
            raise SpeckConfigurationError(
                "Cannot construct model: populations list is empty",
                error_code="CONSTRUCT_EMPTY_POPULATIONS",
            )

        self._populations = list(populations)
        self._connections = list(connections)
        self._network_summary = dict(mapped_network.get("network_summary", {}))
        self.state = SpeckState.CONSTRUCTED
        logger.info(
            "Speck Simulator: model constructed with %d populations, %d connections",
            len(self._populations),
            len(self._connections),
        )

    def map_to_device(self) -> None:
        """Simulate mapping the model to a Speck device."""
        if self.state == SpeckState.UNINITIALIZED:
            raise SpeckConfigurationError(
                "Cannot map to device before model is constructed",
                error_code="MAP_BEFORE_CONSTRUCT",
            )
        self.state = SpeckState.MAPPED
        logger.info("Speck Simulator: model mapped to simulated Speck 2 device")

    def run_inference(self, inputs: list[float]) -> dict[str, Any]:
        """Simulate inference using a minimal LIF model."""
        if self.state not in (SpeckState.MAPPED, SpeckState.RUNNING):
            raise SpeckConfigurationError(
                "Cannot run inference before model is mapped",
                error_code="INFERENCE_BEFORE_MAP",
            )

        if not inputs:
            raise SpeckInferenceError(
                "Input buffer is empty",
                error_code="INFERENCE_EMPTY_INPUT",
            )

        self.state = SpeckState.RUNNING
        start = time.monotonic()

        # Build layer sizes from populations
        layer_sizes = [pop.get("size", 1) for pop in self._populations]
        connection_weights = [conn.get("weight", 1.0) or 1.0 for conn in self._connections]

        # Initialize first layer from inputs
        current_activations = inputs[: layer_sizes[0]]
        while len(current_activations) < layer_sizes[0]:
            current_activations.append(0.0)

        # Propagate through layers
        for layer_idx in range(1, len(layer_sizes)):
            conn_weight = (
                connection_weights[layer_idx - 1]
                if layer_idx - 1 < len(connection_weights)
                else 1.0
            )
            next_size = layer_sizes[layer_idx]
            next_activations = [0.0] * next_size

            for j in range(next_size):
                for i in range(len(current_activations)):
                    next_activations[j] += current_activations[i] * conn_weight

                if next_activations[j] >= self._threshold:
                    next_activations[j] = 1.0
                else:
                    next_activations[j] = 0.0

            current_activations = next_activations

        elapsed_us = (time.monotonic() - start) * 1_000_000
        self.state = SpeckState.MAPPED

        return {
            "outputs": current_activations,
            "timesteps": 1,
            "execution_time_us": elapsed_us,
            "telemetry": {"power_estimate_mw": 0.5},
        }

    def reset(self) -> None:
        """Reset to CONSTRUCTED state."""
        if self.state == SpeckState.UNINITIALIZED:
            raise SpeckConfigurationError(
                "Cannot reset — model was never constructed",
                error_code="RESET_BEFORE_CONSTRUCT",
            )
        self.state = SpeckState.CONSTRUCTED

    @property
    def current_state(self) -> str:
        """Return the current state as a lowercase string."""
        return self.state.name.lower()
