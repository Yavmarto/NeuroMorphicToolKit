"""PYNQ Simulator — software reference for the overlay-v2 engine.

Implements the same interface as the real PYNQ backend (overlay load,
configure, DMA run) but executes in-process. It is a faithful reimplementation
of ``hardware/pynq_z2/hls/snn_overlay_engine.cpp``: persistent membrane state,
shift-based leak, refractory suppression, reset-to-zero, and the same
frame-per-timestep stream protocol.

That fidelity is the point. It is what the on-board self-test compares against,
and what makes an on-board vs simulator accuracy delta meaningful. If the two
diverge, one of them is wrong — which is exactly the situation overlay-v1
shipped in, where the simulator ran a plausible-looking model and the hardware
could not read its weights at all.

State machine:  UNLOADED → LOADED → CONFIGURED → (RUNNING → CONFIGURED)
"""

from __future__ import annotations

import logging
import time
from enum import Enum, auto
from typing import Any

from ...contracts.pynq_runtime_artifact_contract import (
    DEFAULT_REGISTER_MAP,
    MAX_SYNAPSES,
)
from .pynq_errors import (
    ConfigurationError,
    DmaTransferError,
    MmioWriteError,
    OverlayLoadError,
)

logger = logging.getLogger(__name__)


class PynqState(Enum):
    """Lifecycle states for the PYNQ backend."""

    UNLOADED = auto()
    LOADED = auto()
    CONFIGURED = auto()
    RUNNING = auto()


class PynqSimulator:
    """In-process PYNQ simulator for CI and offline development.

    Mimics overlay loading, MMIO register writes, and DMA spike transfer
    using a simple leaky integrate-and-fire (LIF) neuron model.
    """

    def __init__(self) -> None:
        self.state: PynqState = PynqState.UNLOADED
        self.bitstream_path: str | None = None
        self.register_map: dict[str, Any] = {}
        self.mmio_registers: dict[int, int] = {}
        self.weights: list[float] = []
        self.layers: list[dict[str, Any]] = []
        self.config: dict[str, Any] = {}
        self.neuron_count: int = 0
        self.threshold: float = 1.0

    def load_overlay(self, bitstream_path: str) -> None:
        """Simulate loading a bitstream overlay.

        Validates that the path has a ``.bit`` extension.

        Args:
            bitstream_path: Path to the ``.bit`` file.

        Raises:
            OverlayLoadError: If the path does not end with ``.bit``.
        """
        if not bitstream_path.endswith(".bit"):
            raise OverlayLoadError(
                f"Bitstream path must end with '.bit', got: {bitstream_path}",
                error_code="OVERLAY_INVALID_FORMAT",
            )
        self.bitstream_path = bitstream_path
        self.register_map = dict(DEFAULT_REGISTER_MAP)
        self.state = PynqState.LOADED
        logger.info("Simulator: overlay loaded from %s", bitstream_path)

    def configure(
        self,
        weights: list[float],
        config: dict[str, Any],
        register_map: dict[str, Any] | None = None,
        layers: list[dict[str, Any]] | None = None,
    ) -> None:
        """Program the simulated engine.

        Args:
            weights: Flat int8 weight buffer, one contiguous block per layer.
            config: Additional parameters (e.g. a fallback ``threshold``).
            register_map: Optional override for the default register map.
            layers: Per-layer descriptors — ``input_size``, ``output_size``,
                ``weight_offset``, ``threshold``, ``leak_shift``,
                ``refractory``. Without them the simulator has no network
                shape and can only report an empty run.

        Raises:
            ConfigurationError: If called before overlay is loaded.
            MmioWriteError: If the weight buffer exceeds the on-chip cache.
        """
        if self.state == PynqState.UNLOADED:
            raise ConfigurationError(
                "Cannot configure before overlay is loaded",
                error_code="CONFIGURE_BEFORE_LOAD",
            )

        if register_map is not None:
            self.register_map = register_map

        if len(weights) > MAX_SYNAPSES:
            raise MmioWriteError(
                f"Weight/synapse count ({len(weights)}) exceeds MAX_SYNAPSES ({MAX_SYNAPSES})",
                error_code="MMIO_WEIGHT_OVERFLOW",
            )

        self.weights = list(weights)
        self.layers = [dict(layer) for layer in (layers or [])]
        self.config = dict(config)
        self.threshold = float(config.get("threshold", 1.0))
        self.neuron_count = sum(int(layer.get("output_size", 0)) for layer in self.layers)
        self.state = PynqState.CONFIGURED
        logger.info(
            "Simulator: configured %d weights across %d layer(s)",
            len(weights),
            len(self.layers),
        )

    @property
    def input_size(self) -> int:
        return int(self.layers[0].get("input_size", 0)) if self.layers else 0

    @property
    def output_size(self) -> int:
        return int(self.layers[-1].get("output_size", 0)) if self.layers else 0

    def run(
        self,
        input_spikes: list[int],
        timesteps: int = 1,
    ) -> dict[str, Any]:
        """Execute the configured network, mirroring the HLS engine exactly.

        Args:
            input_spikes: ``input_size * timesteps`` words, one per input
                neuron per timestep. Non-zero means that neuron spiked.
            timesteps: Number of timesteps.

        Returns:
            Dict with ``output_spikes`` (``output_size * timesteps`` words,
            1 for a spike), ``timesteps``, ``output_neurons``, and
            ``execution_time_us``.

        Raises:
            ConfigurationError: If called before configure.
            DmaTransferError: On an empty or wrongly-sized input buffer.
        """
        if self.state not in (PynqState.CONFIGURED, PynqState.RUNNING):
            raise ConfigurationError(
                "Cannot run before configure is called",
                error_code="RUN_BEFORE_CONFIGURE",
            )

        if len(input_spikes) == 0:
            raise DmaTransferError(
                "Input spike buffer is empty — DMA underrun",
                error_code="DMA_EMPTY_BUFFER",
            )

        if not self.layers:
            raise ConfigurationError(
                "Cannot run without layer descriptors — the engine has no network shape to execute",
                error_code="MISSING_LAYER_DESCRIPTORS",
            )

        input_size = self.input_size
        output_size = self.output_size
        expected = input_size * timesteps
        if len(input_spikes) != expected:
            raise DmaTransferError(
                f"Expected {expected} input words ({input_size} neurons x "
                f"{timesteps} timesteps), got {len(input_spikes)}",
                error_code="DMA_INPUT_SIZE_MISMATCH",
            )

        self.state = PynqState.RUNNING
        start = time.monotonic()

        # Persistent per-layer state. Overlay-v1 reset the membrane potential
        # for every neuron on every timestep, which made it a thresholded
        # matrix-multiply rather than a spiking neuron.
        membrane = [[0] * int(layer.get("output_size", 0)) for layer in self.layers]
        refractory = [[0] * int(layer.get("output_size", 0)) for layer in self.layers]

        output_spikes: list[int] = []
        for timestep in range(timesteps):
            frame = input_spikes[timestep * input_size : (timestep + 1) * input_size]
            current = [1 if value else 0 for value in frame]

            for index, layer in enumerate(self.layers):
                fan_in = int(layer.get("input_size", 0))
                fan_out = int(layer.get("output_size", 0))
                weight_base = int(layer.get("weight_offset", 0))
                threshold = int(layer.get("threshold", 0))
                leak_shift = int(layer.get("leak_shift", 0))
                refractory_reload = int(layer.get("refractory", 0))

                next_spikes = [0] * fan_out
                for neuron in range(fan_out):
                    row = weight_base + neuron * fan_in
                    accumulator = 0
                    for synapse in range(fan_in):
                        if synapse < len(current) and current[synapse]:
                            position = row + synapse
                            if position < len(self.weights):
                                accumulator += int(self.weights[position])

                    potential = membrane[index][neuron]
                    if leak_shift > 0:
                        potential -= potential >> leak_shift
                    potential += accumulator

                    if refractory[index][neuron] > 0:
                        refractory[index][neuron] -= 1
                        potential = 0
                    elif potential >= threshold:
                        next_spikes[neuron] = 1
                        potential = 0
                        refractory[index][neuron] = refractory_reload

                    membrane[index][neuron] = potential

                current = next_spikes

            output_spikes.extend(current[:output_size])

        elapsed_us = (time.monotonic() - start) * 1_000_000
        self.state = PynqState.CONFIGURED  # back to CONFIGURED after run

        logger.info(
            "Simulator: ran %d timesteps, %d spikes in %.1f µs",
            timesteps,
            sum(output_spikes),
            elapsed_us,
        )
        return {
            "output_spikes": output_spikes,
            "timesteps": timesteps,
            "output_neurons": output_size,
            "execution_time_us": elapsed_us,
        }

    def reset(self) -> None:
        """Reset to LOADED state, clearing weights and config.

        Raises:
            ConfigurationError: If overlay was never loaded.
        """
        if self.state == PynqState.UNLOADED:
            raise ConfigurationError(
                "Cannot reset — overlay was never loaded",
                error_code="RESET_BEFORE_LOAD",
            )
        self.weights = []
        self.layers = []
        self.config = {}
        self.mmio_registers = {}
        self.neuron_count = 0
        self.threshold = 1.0
        self.state = PynqState.LOADED
        logger.info("Simulator: reset to LOADED state")

    @property
    def current_state(self) -> str:
        """Return the current state as a lowercase string."""
        return self.state.name.lower()
