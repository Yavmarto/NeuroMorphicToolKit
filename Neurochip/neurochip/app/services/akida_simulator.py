"""Akida Simulator — test double for CI environments without the Akida SDK.

Implements the same interface as the real Akida backend (model construction,
device mapping, inference) but executes entirely in-process using a minimal
integrate-and-fire spike model.  This means CI tests exercise a meaningful
execution path rather than just echoing input data.

State machine:  UNINITIALIZED → CONSTRUCTED → MAPPED → (RUNNING → MAPPED)
"""

from __future__ import annotations

import logging
import time
from enum import Enum, auto
from typing import Any

from .akida_errors import (
    AkidaConfigurationError,
    AkidaInferenceError,
)

logger = logging.getLogger(__name__)


class AkidaState(Enum):
    """Lifecycle states for the Akida backend."""

    UNINITIALIZED = auto()
    CONSTRUCTED = auto()
    MAPPED = auto()
    RUNNING = auto()


class AkidaSimulator:
    """In-process Akida simulator for CI and offline development.

    Mimics model construction, device mapping, and inference execution
    using a simple leaky integrate-and-fire (LIF) neuron model built
    from the mapped network's populations and connections.
    """

    def __init__(self) -> None:
        self.state: AkidaState = AkidaState.UNINITIALIZED
        self._populations: list[dict[str, Any]] = []
        self._connections: list[dict[str, Any]] = []
        self._network_summary: dict[str, Any] = {}
        self._akida_version: str = "akida1"
        self._threshold: float = 1.0

    def construct_model(self, mapped_network: dict[str, Any]) -> None:
        """Build a simulated model from an AkidaMappedNetwork-shaped dict.

        Args:
            mapped_network: Dict with ``populations``, ``connections``,
                ``akida_version``, and ``network_summary`` keys.

        Raises:
            AkidaConfigurationError: If populations list is empty.
        """
        populations = mapped_network.get("populations", [])
        connections = mapped_network.get("connections", [])

        if not populations:
            raise AkidaConfigurationError(
                "Cannot construct model: populations list is empty",
                error_code="CONSTRUCT_EMPTY_POPULATIONS",
            )

        self._populations = list(populations)
        self._connections = list(connections)
        self._network_summary = dict(mapped_network.get("network_summary", {}))
        self._akida_version = mapped_network.get("akida_version", "akida1")
        self.state = AkidaState.CONSTRUCTED
        logger.info(
            "Simulator: model constructed with %d populations, %d connections",
            len(self._populations),
            len(self._connections),
        )

    def map_to_device(self) -> None:
        """Simulate mapping the model to an Akida device.

        Raises:
            AkidaConfigurationError: If called before construct_model.
        """
        if self.state == AkidaState.UNINITIALIZED:
            raise AkidaConfigurationError(
                "Cannot map to device before model is constructed",
                error_code="MAP_BEFORE_CONSTRUCT",
            )
        self.state = AkidaState.MAPPED
        logger.info("Simulator: model mapped to simulated AKD1000 device")

    def run_inference(self, inputs: list[float]) -> dict[str, Any]:
        """Simulate inference using a minimal LIF model.

        Each population is treated as a layer.  Input values are fed to
        the first population's neurons, then propagated through connections
        using the connection weight as a uniform synaptic weight.

        Args:
            inputs: Input values (one per neuron in the first population).

        Returns:
            Dict with ``outputs``, ``timesteps``, and ``execution_time_us``.

        Raises:
            AkidaConfigurationError: If not in MAPPED state.
            AkidaInferenceError: If inputs list is empty.
        """
        if self.state not in (AkidaState.MAPPED, AkidaState.RUNNING):
            raise AkidaConfigurationError(
                "Cannot run inference before model is mapped",
                error_code="INFERENCE_BEFORE_MAP",
            )

        if not inputs:
            raise AkidaInferenceError(
                "Input buffer is empty",
                error_code="INFERENCE_EMPTY_INPUT",
            )

        self.state = AkidaState.RUNNING
        start = time.monotonic()

        # Build layer sizes from populations
        layer_sizes = [pop.get("size", 1) for pop in self._populations]
        connection_weights = [conn.get("weight", 1.0) or 1.0 for conn in self._connections]

        # Initialize first layer from inputs
        current_activations = inputs[: layer_sizes[0]]
        # Pad if inputs shorter than first population
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
            layer_threshold = (
                self._populations[layer_idx]
                .get("attributes", {})
                .get("lif_threshold", self._threshold)
            )

            # Simple weighted sum with LIF threshold
            for j in range(next_size):
                for i in range(len(current_activations)):
                    next_activations[j] += current_activations[i] * conn_weight

                # LIF fire-or-zero
                if next_activations[j] >= layer_threshold:
                    next_activations[j] = 1.0
                else:
                    next_activations[j] = 0.0

            current_activations = next_activations

        elapsed_us = (time.monotonic() - start) * 1_000_000
        self.state = AkidaState.MAPPED  # back to MAPPED after run

        logger.info(
            "Simulator: inference complete, %d outputs in %.1f us",
            len(current_activations),
            elapsed_us,
        )
        return {
            "outputs": current_activations,
            "timesteps": 1,
            "execution_time_us": elapsed_us,
        }

    def get_model_summary(self) -> dict[str, Any]:
        """Return the network summary stored during construction."""
        return dict(self._network_summary)

    def reset(self) -> None:
        """Reset to CONSTRUCTED state, clearing device mapping.

        Raises:
            AkidaConfigurationError: If model was never constructed.
        """
        if self.state == AkidaState.UNINITIALIZED:
            raise AkidaConfigurationError(
                "Cannot reset — model was never constructed",
                error_code="RESET_BEFORE_CONSTRUCT",
            )
        self.state = AkidaState.CONSTRUCTED
        logger.info("Simulator: reset to CONSTRUCTED state")

    @property
    def current_state(self) -> str:
        """Return the current state as a lowercase string."""
        return self.state.name.lower()
