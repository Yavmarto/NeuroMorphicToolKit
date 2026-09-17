"""Tests for Pydantic contracts and their validation logic."""

import pytest
from pydantic import ValidationError

from neurocnl.contracts import (
    LIFNeuronContract,
    PopulationContract,
    STDPContract,
    SynapticContract,
)


def test_lif_neuron_contract_valid() -> None:
    params = {
        "threshold": 1.0,
        "resting_potential": 0.0,
        "refractory_period": 0.002,
        "tau": 0.02,
        "reset_potential": 0.0,
    }
    contract = LIFNeuronContract(**params)
    assert contract.threshold == 1.0


def test_lif_neuron_contract_invalid_threshold() -> None:
    params = {
        "threshold": -0.5,
        "resting_potential": 0.0,
        "refractory_period": 0.002,
        "tau": 0.02,
        "reset_potential": 0.0,
    }
    with pytest.raises(ValidationError) as excinfo:
        LIFNeuronContract(**params)
    assert "threshold" in str(excinfo.value)


def test_lif_neuron_contract_invalid_tau() -> None:
    params = {
        "threshold": 1.0,
        "resting_potential": 0.0,
        "refractory_period": 0.002,
        "tau": -0.01,
        "reset_potential": 0.0,
    }
    with pytest.raises(ValidationError) as excinfo:
        LIFNeuronContract(**params)
    assert "tau" in str(excinfo.value)


def test_synaptic_contract_invalid_inhibitory() -> None:
    with pytest.raises(ValidationError) as excinfo:
        SynapticContract(inhibitory_weight=0.5)
    assert "inhibitory_weight" in str(excinfo.value)


def test_population_contract_invalid_count() -> None:
    with pytest.raises(ValidationError) as excinfo:
        PopulationContract(
            population_n_neurons=0, population_dimensions=1, population_radius=1.0
        )
    assert "population_n_neurons" in str(excinfo.value)


def test_population_contract_boundary_count() -> None:
    with pytest.raises(ValidationError) as excinfo:
        PopulationContract(
            population_n_neurons=10001, population_dimensions=1, population_radius=1.0
        )
    assert "population_n_neurons" in str(excinfo.value)


def test_lif_neuron_contract_boundary_refractory() -> None:
    params = {
        "threshold": 1.0,
        "resting_potential": 0.0,
        "refractory_period": 0.0,
        "tau": 0.02,
        "reset_potential": 0.0,
    }
    with pytest.raises(ValidationError) as excinfo:
        LIFNeuronContract(**params)
    assert "refractory_period" in str(excinfo.value)


def test_lif_neuron_contract_boundary_tau() -> None:
    params = {
        "threshold": 1.0,
        "resting_potential": 0.0,
        "refractory_period": 0.002,
        "tau": 0.0,
        "reset_potential": 0.0,
    }
    with pytest.raises(ValidationError) as excinfo:
        LIFNeuronContract(**params)
    assert "tau" in str(excinfo.value)


def test_stdp_contract_invalid_window() -> None:
    with pytest.raises(ValidationError) as excinfo:
        STDPContract(stdp_window=0.2)
    assert "stdp_window" in str(excinfo.value)


def test_parsed_sentence_contract_missing_field() -> None:
    from neurocnl.contracts import ParsedSentenceContract

    with pytest.raises(ValidationError):
        ParsedSentenceContract(  # type: ignore[call-arg]
            concept="threshold_firing",
            subject="neuron",
            # action is missing
            verb="MUST",
            negated=False,
            raw="A neuron MUST spike if exceeds 1.0",
        )


def test_cnl_parse_result_contract_invalid_type() -> None:
    from neurocnl.contracts import CNLParseResultContract

    with pytest.raises(ValidationError):
        CNLParseResultContract(
            line="one",
            raw="invalid line",
            valid=False,  # Should be int
        )


def test_layer1_result_contract_missing_field() -> None:
    from neurocnl.contracts import Layer1ResultContract

    with pytest.raises(ValidationError):
        Layer1ResultContract(  # type: ignore[call-arg]
            overall=True,
            passed=[],
            # failed is missing
        )


def test_layer2_result_contract_invalid_type() -> None:
    from neurocnl.contracts import Layer2ResultContract

    with pytest.raises(ValidationError):
        Layer2ResultContract(
            overall=True,
            checks_passed="none",  # Should be list
            checks_failed=[],
            neurons_found=[],
        )


def test_simulation_result_contract_invalid_nested_type() -> None:
    from neurocnl.contracts import SimulationResultContract

    with pytest.raises(ValidationError):
        SimulationResultContract(
            duration=1.0,
            dt=0.001,
            wall_time_seconds=0.1,
            motor_output=["not a list of floats"],
        )


def test_pipeline_result_to_contract() -> None:
    from neurocnl.contracts import PipelineResultContract
    from neurocnl.pipeline import PipelineResult

    res = PipelineResult(
        parsed=[
            {
                "concept": "threshold_firing",
                "subject": "neuron",
                "action": "spike",
                "verb": "MUST",
                "negated": False,
                "condition": "exceeds 1.0",
                "raw": "A neuron MUST spike if exceeds 1.0",
            }
        ],
        validation={
            "layer1": {
                "overall": True,
                "passed": [{"name": "test", "reason": "ok", "result": True}],
                "failed": [],
            },
            "layer2": {
                "overall": True,
                "checks_passed": [],
                "checks_failed": [],
                "neurons_found": [],
            },
            "overall": True,
        },
        overall_pass=True,
    )
    contract = res.to_contract()
    assert isinstance(contract, PipelineResultContract)
    assert contract.overall_pass is True
    assert len(contract.parsed) == 1
    assert contract.validation is not None
    assert contract.validation.overall is True
