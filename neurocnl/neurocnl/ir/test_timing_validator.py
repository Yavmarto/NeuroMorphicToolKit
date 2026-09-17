"""Tests for timing declaration validation in the NIR materialization path."""

import pytest

from neurocnl.ir.timing_validator import (
    TimingValidationError,
    validate_timing_declarations,
)
from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR, TimingDeclarationIR


def test_validate_timing_declarations_accepts_consistent_quantized_delays() -> None:
    network = NetworkIR(
        populations={
            "input": PopulationIR(name="input", size=2, role="input"),
            "output": PopulationIR(name="output", size=2, role="output"),
        },
        connections=[ConnectionIR(source="input", target="output", delay=0.004, weight=0.5)],
        timing_declarations=[
            TimingDeclarationIR(kind="timestep", value=0.001, unit="seconds"),
            TimingDeclarationIR(kind="delay_quantization", value=0.002, unit="seconds"),
            TimingDeclarationIR(kind="simulation_time", value=0.1, unit="seconds"),
        ],
    )

    validate_timing_declarations(network)


def test_validate_timing_declarations_rejects_duplicate_kinds() -> None:
    network = NetworkIR(
        timing_declarations=[
            TimingDeclarationIR(kind="timestep", value=0.001, unit="seconds"),
            TimingDeclarationIR(kind="timestep", value=0.002, unit="seconds"),
        ]
    )

    with pytest.raises(TimingValidationError, match="may only be declared once"):
        validate_timing_declarations(network)


def test_validate_timing_declarations_rejects_non_multiple_quantization() -> None:
    network = NetworkIR(
        timing_declarations=[
            TimingDeclarationIR(kind="timestep", value=0.003, unit="seconds"),
            TimingDeclarationIR(kind="delay_quantization", value=0.004, unit="seconds"),
        ]
    )

    with pytest.raises(TimingValidationError, match="integer multiple"):
        validate_timing_declarations(network)


def test_validate_timing_declarations_rejects_delay_misaligned_with_quantization() -> None:
    network = NetworkIR(
        populations={
            "input": PopulationIR(name="input", size=1, role="input"),
            "output": PopulationIR(name="output", size=1, role="output"),
        },
        connections=[ConnectionIR(source="input", target="output", delay=0.003, weight=1.0)],
        timing_declarations=[
            TimingDeclarationIR(kind="timestep", value=0.001, unit="seconds"),
            TimingDeclarationIR(kind="delay_quantization", value=0.002, unit="seconds"),
        ],
    )

    with pytest.raises(TimingValidationError, match="align with the declared delay quantization"):
        validate_timing_declarations(network)
