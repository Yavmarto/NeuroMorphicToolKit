import os
import py_compile
import sys
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from neurocnl.cnl.types import ParsedSentence
from neurocnl.generation.assertion_generator import (
    AssertionGeneratorError,
    _generate_llm_assertions,
    _generate_template_assertions,
    generate_assertions,
)


@pytest.fixture
def sample_specs() -> list[ParsedSentence]:
    return [
        {
            "concept": "threshold_firing",
            "raw": "The neuron fires when input exceeds 1.0",
            "negated": False,
            "condition": "exceeds 1.0",
            "subject": "neuron",
            "verb": "fires",
            "action": "fire",
        },
        {
            "concept": "threshold_firing",
            "raw": "The neuron does not fire below 0.5",
            "negated": True,
            "condition": "below 0.5",
            "subject": "neuron",
            "verb": "fire",
            "action": "fire",
        },
        {
            "concept": "refractory_period",
            "raw": "The refractory period is 0.005s",
            "negated": False,
            "condition": "0.005s",
            "subject": "refractory period",
            "verb": "is",
            "action": "be",
        },
        {
            "concept": "membrane_potential_decay",
            "raw": "The membrane potential decays with tau 0.02s",
            "negated": False,
            "condition": "0.02s",
            "subject": "membrane potential",
            "verb": "decays",
            "action": "decay",
        },
        {
            "concept": "synaptic_weight",
            "raw": "The synaptic weight is 1.5",
            "negated": False,
            "condition": "1.5",
            "subject": "synaptic weight",
            "verb": "is",
            "action": "be",
        },
        {
            "concept": "axonal_delay",
            "raw": "The axonal delay is 0.01s",
            "negated": False,
            "condition": "0.01s",
            "subject": "axonal delay",
            "verb": "is",
            "action": "be",
        },
        {
            "concept": "stdp_learning",
            "raw": "STDP learning with rate 1e-4",
            "negated": False,
            "condition": "rate 1e-4",
            "subject": "STDP learning",
            "verb": "is",
            "action": "be",
        },
        {
            "concept": "stdp_learning",
            "raw": "BCM learning with rate 1e-5",
            "negated": False,
            "condition": "BCM rate 1e-5",
            "subject": "BCM learning",
            "verb": "is",
            "action": "be",
        },
        {
            "concept": "stdp_learning",
            "raw": "Oja learning with rate 1e-6",
            "negated": False,
            "condition": "Oja rate 1e-6",
            "subject": "Oja learning",
            "verb": "is",
            "action": "be",
        },
        {
            "concept": "inhibitory_connection",
            "raw": "The inhibitory connection has weight -2.0",
            "negated": False,
            "condition": "-2.0",
            "subject": "inhibitory connection",
            "verb": "has",
            "action": "have",
        },
        {
            "concept": "population_coding",
            "raw": "Population coding with 100 neurons",
            "negated": False,
            "condition": "100 neurons",
            "subject": "population coding",
            "verb": "is",
            "action": "be",
        },
        {
            "concept": "network_topology",
            "raw": "A population of 30 neurons",
            "negated": False,
            "condition": "population of 30 neurons",
            "subject": "network topology",
            "verb": "is",
            "action": "be",
        },
        {
            "concept": "lateral_inhibition",
            "raw": "Lateral inhibition with radius 2",
            "negated": False,
            "condition": "radius 2",
            "subject": "lateral inhibition",
            "verb": "is",
            "action": "be",
        },
        {
            "concept": "homeostatic_plasticity",
            "raw": "Homeostatic plasticity with target 20Hz",
            "negated": False,
            "condition": "target 20Hz",
            "subject": "homeostatic plasticity",
            "verb": "is",
            "action": "be",
        },
        {
            "concept": "neuromodulation",
            "raw": "Neuromodulation with factor 1.2",
            "negated": False,
            "condition": "factor 1.2",
            "subject": "neuromodulation",
            "verb": "is",
            "action": "be",
        },
        {
            "concept": "population_coding_range",
            "raw": "Population coding range is 180",
            "negated": False,
            "condition": "180",
            "subject": "population coding range",
            "verb": "is",
            "action": "be",
        },
    ]


def test_generate_template_assertions_all_concepts(
    sample_specs: list[ParsedSentence],
) -> None:
    code = _generate_template_assertions(sample_specs)
    assert '"""Layer 3 auto-generated assertions from CNL spec.' in code
    assert "import nengo" in code
    assert "import numpy as np" in code

    assert "def test_threshold_firing_0():" in code
    assert "assert np.any(spikes > 0)" in code
    assert "def test_threshold_firing_1():" in code
    assert "assert not np.any(spikes > 0)" in code
    assert "def test_refractory_period_2():" in code
    assert "tau_ref = 0.005" in code
    assert "def test_membrane_decay_3():" in code
    assert "tau_rc = 0.02" in code
    assert "def test_synaptic_weight_4():" in code
    assert "weight = 1.5" in code
    assert "def test_axonal_delay_5():" in code
    assert "delay = 0.01" in code
    assert "def test_stdp_learning_6():" in code
    assert "learning_rule_type=nengo.PES(learning_rate=0.0001)" in code
    # Print code for debugging if it fails again
    # print(code)
    assert "def test_stdp_learning_7():" in code
    assert "learning_rule_type=nengo.BCM(learning_rate=1e-05)" in code
    assert "def test_stdp_learning_8():" in code
    assert "learning_rule_type=nengo.Oja(learning_rate=1e-06)" in code
    assert "def test_inhibitory_connection_9():" in code
    assert "inh_weight = -2.0" in code
    assert "def test_population_coding_10():" in code
    assert "n_neurons = 100" in code
    assert "def test_network_topology_11():" in code
    assert "n_neurons = 30" in code
    assert "def test_lateral_inhibition_12():" in code
    assert "radius = 2.0" in code
    assert "def test_homeostatic_plasticity_13():" in code
    assert "target_rate = 20.0" in code
    assert "def test_neuromodulation_14():" in code
    assert "factor = 1.2" in code
    assert "def test_population_coding_range_15():" in code
    assert "range_val = 180.0" in code


def test_generate_assertions_happy_path(
    sample_specs: list[ParsedSentence], tmp_path: Path
) -> None:
    output_file = tmp_path / "test_assertions.py"
    res_path = generate_assertions(sample_specs, output_path=str(output_file))
    assert res_path == str(output_file)
    assert output_file.exists()
    content = output_file.read_text()
    assert "def test_threshold_firing_0():" in content


def test_generate_assertions_syntax_error(
    sample_specs: list[ParsedSentence], tmp_path: Path
) -> None:
    output_file = tmp_path / "bad_syntax.py"
    with patch("py_compile.compile") as mock_compile:
        mock_compile.side_effect = py_compile.PyCompileError(
            exc_type=SyntaxError,
            exc_value=SyntaxError("Invalid syntax"),
            file="bad_syntax.py",
        )
        with pytest.raises(
            AssertionGeneratorError, match="Generated assertions failed syntax check"
        ):
            generate_assertions(sample_specs, output_path=str(output_file))


def test_generate_assertions_llm_fallback(
    sample_specs: list[ParsedSentence], tmp_path: Path
) -> None:
    output_file = tmp_path / "test_fallback.py"
    with patch.dict(os.environ, {}, clear=True):
        # Even if use_llm=True, it should fallback if key is missing
        res_path = generate_assertions(
            sample_specs, output_path=str(output_file), use_llm=True
        )
        assert res_path == str(output_file)
        content = output_file.read_text()
        assert "Layer 3 auto-generated assertions from CNL spec." in content


sys.modules["anthropic"] = MagicMock()


@patch("anthropic.Anthropic")
def test_generate_llm_assertions_success(
    mock_anthropic_class: MagicMock, sample_specs: list[ParsedSentence]
) -> None:
    mock_client = MagicMock()
    mock_anthropic_class.return_value = mock_client
    mock_message = MagicMock()
    mock_message.content = [MagicMock(text="import nengo\ndef test_llm(): pass")]
    mock_client.messages.create.return_value = mock_message

    with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test-key"}):
        code = _generate_llm_assertions(sample_specs)
        assert "test_llm" in code
        mock_client.messages.create.assert_called_once()


def test_generate_llm_assertions_no_key(sample_specs: list[ParsedSentence]) -> None:
    import sys
    from unittest.mock import MagicMock

    sys.modules["anthropic"] = MagicMock()
    with (
        patch.dict(os.environ, {}, clear=True),
        pytest.raises(
            AssertionGeneratorError,
            match="ANTHROPIC_API_KEY environment variable not set",
        ),
    ):
        _generate_llm_assertions(sample_specs)


def test_generate_llm_assertions_no_package(sample_specs: list[ParsedSentence]) -> None:
    with (
        patch.dict(sys.modules, {"anthropic": None}),
        pytest.raises(AssertionGeneratorError, match="anthropic package not installed"),
    ):
        _generate_llm_assertions(sample_specs)


def test_generate_assertions_with_llm_enabled(
    sample_specs: list[ParsedSentence], tmp_path: Path
) -> None:
    output_file = tmp_path / "test_llm_enabled.py"
    mock_llm_code = (
        "import nengo\nimport numpy as np\ndef test_llm_generated(): assert True"
    )

    with patch(
        "neurocnl.generation.assertion_generator._generate_llm_assertions"
    ) as mock_gen:
        mock_gen.return_value = mock_llm_code
        with patch.dict(os.environ, {"ANTHROPIC_API_KEY": "test-key"}):
            res_path = generate_assertions(
                sample_specs, output_path=str(output_file), use_llm=True
            )
            assert res_path == str(output_file)
            assert output_file.read_text() == mock_llm_code
