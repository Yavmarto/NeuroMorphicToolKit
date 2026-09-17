from unittest import mock

import pytest

from neurocnl.generation.akida_generator import generate_script
from neurocnl.ir.types import (
    AkidaHardwareIR,
    ConnectionIR,
    NetworkIR,
    PopulationIR,
    SourceProvenance,
)


@pytest.fixture
def valid_ir_model() -> NetworkIR:
    """Create a minimal valid IR model."""
    return NetworkIR(
        populations={
            "sensory": PopulationIR(
                name="sensory",
                size=50,
                provenance=[SourceProvenance(concept="threshold_firing")],
            ),
            "motor": PopulationIR(
                name="motor",
                size=50,
                provenance=[SourceProvenance(concept="threshold_firing")],
            ),
        },
        connections=[
            ConnectionIR(
                source="sensory",
                target="motor",
                weight=1.0,
                provenance=[SourceProvenance(concept="synaptic_weight")],
            )
        ],
    )


@pytest.fixture
def unsupported_ir_model() -> NetworkIR:
    """Create an IR model with an unsupported concept for akida."""
    return NetworkIR(
        populations={
            "sensory": PopulationIR(
                name="sensory",
                size=50,
                provenance=[SourceProvenance(concept="receptor_dynamics")],
            ),
        },
        connections=[],
    )


@pytest.fixture
def akida2_branching_ir_model() -> NetworkIR:
    """Create an Akida2 IR that the planner allows but the shared mapper rejects."""
    return NetworkIR(
        populations={
            "sensory": PopulationIR(name="sensory", size=50, population_type="lif"),
            "interneuron": PopulationIR(
                name="interneuron", size=25, population_type="lif"
            ),
            "motor": PopulationIR(name="motor", size=50, population_type="lif"),
        },
        connections=[
            ConnectionIR(source="sensory", target="interneuron", weight=1.0),
            ConnectionIR(source="sensory", target="motor", weight=1.0),
        ],
        akida_hardware=AkidaHardwareIR(version="Akida2"),
    )


def test_akida_generator_script_emits_valid_code(valid_ir_model: NetworkIR) -> None:
    """Test standard Akida script generation."""
    code = generate_script(valid_ir_model)
    assert "import akida" in code
    assert "akida.Sequential()" in code
    assert "model.add(Input(input_shape=(50,)))" in code
    assert "model.add(FullyConnected(units=50, name='motor'))" in code


def test_akida_generator_macos_warning(valid_ir_model: NetworkIR) -> None:
    """Test macOS execution warning."""
    with (
        mock.patch("sys.platform", "darwin"),
        pytest.warns(RuntimeWarning, match="currently do not support macOS"),
    ):
        generate_script(valid_ir_model)


def test_akida_generator_unsupported_halts(unsupported_ir_model: NetworkIR) -> None:
    """Test unsupported topology halts generation."""
    with pytest.raises(
        RuntimeError,
        match="Network topology contains features unsupported by the Akida native backend",
    ):
        generate_script(unsupported_ir_model)


def test_akida_generator_branching_akida2_halts_before_partial_script(
    akida2_branching_ir_model: NetworkIR,
) -> None:
    """Approximate Akida2 topologies must fail closed instead of skipping edges."""
    with pytest.raises(RuntimeError, match="branching or ambiguous fan-out"):
        generate_script(akida2_branching_ir_model)
