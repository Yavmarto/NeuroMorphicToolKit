"""Machine-checked validation for timing declarations used by NIR materialization."""

from __future__ import annotations

from collections.abc import Iterable

import numpy as np

from neurocnl.ir.types import NetworkIR, TimingDeclarationIR

_SUPPORTED_TIMING_KINDS = frozenset(
    {
        "simulation_time",
        "timestep",
        "delay_quantization",
        "biological_speed_multiplier",
    }
)
_TIMING_TOLERANCE = 1e-9


class TimingValidationError(ValueError):
    """Raised when timing declarations cannot be represented consistently."""


def validate_timing_declarations(network: NetworkIR) -> None:
    """Validate timing declarations against the current executable NIR bridge."""
    declarations_by_kind: dict[str, TimingDeclarationIR] = {}

    for declaration in network.timing_declarations:
        if declaration.kind not in _SUPPORTED_TIMING_KINDS:
            raise TimingValidationError(
                f"Unsupported timing declaration kind {declaration.kind!r}."
            )
        if declaration.value is None or declaration.value <= 0:
            raise TimingValidationError(
                f"Timing declaration {declaration.kind!r} must have a positive value."
            )
        if declaration.kind in declarations_by_kind:
            raise TimingValidationError(
                f"Timing declaration {declaration.kind!r} may only be declared once."
            )
        declarations_by_kind[declaration.kind] = declaration

    timestep = _declaration_value(declarations_by_kind, "timestep")
    delay_quantization = _declaration_value(declarations_by_kind, "delay_quantization")
    simulation_time = _declaration_value(declarations_by_kind, "simulation_time")

    if (
        timestep is not None
        and delay_quantization is not None
        and (
            delay_quantization < timestep or not _is_integer_multiple(delay_quantization, timestep)
        )
    ):
        raise TimingValidationError(
            "Timing declaration 'delay_quantization' must be greater than or equal to the "
            "declared timestep and an integer multiple of it."
        )

    if simulation_time is not None and timestep is not None and simulation_time < timestep:
        raise TimingValidationError(
            "Timing declaration 'simulation_time' must be greater than or equal to the "
            "declared timestep."
        )

    if delay_quantization is None:
        return

    for delay in _effective_delays(network):
        if not _is_integer_multiple(delay, delay_quantization):
            raise TimingValidationError(
                "Connection delays must align with the declared delay quantization step."
            )


def _declaration_value(
    declarations_by_kind: dict[str, TimingDeclarationIR],
    kind: str,
) -> float | None:
    declaration = declarations_by_kind.get(kind)
    if declaration is None or declaration.value is None:
        return None
    return float(declaration.value)


def _effective_delays(network: NetworkIR) -> Iterable[float]:
    default_delay = network.metadata.get("default_axonal_delay")
    for connection in network.connections:
        if connection.delay is not None:
            yield float(connection.delay)
        elif default_delay is not None:
            yield float(default_delay)


def _is_integer_multiple(value: float, base: float) -> bool:
    ratio = value / base
    return bool(np.isclose(ratio, round(ratio), atol=_TIMING_TOLERANCE, rtol=0.0))
