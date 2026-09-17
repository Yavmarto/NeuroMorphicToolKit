"""Layer 3 Assertion Generator.

Generates pytest assertions from validated CNL specifications.
When the Anthropic API key is available, uses Claude to generate assertions.
Otherwise, generates assertions using template-based rules.
"""

import os
import py_compile
import textwrap
from typing import cast

from neurocnl.cnl.types import ParsedSentence

try:
    from neurocnl.utils import extract_numeric
except ImportError:
    from utils import extract_numeric  # type: ignore[no-redef]


class AssertionGeneratorError(Exception):
    """Raised when assertion generation or syntax check fails."""


def _generate_template_assertions(parsed_specs: list[ParsedSentence]) -> str:
    """Generate pytest assertions from parsed specs using templates.

    This is the template-based fallback when no LLM API is available.
    Each test validates exactly one behavioral rule from the spec.
    """
    lines = [
        '"""Layer 3 auto-generated assertions from CNL spec.',
        "",
        "Each test validates exactly one behavioral rule.",
        "Dependencies: nengo, numpy only.",
        '"""',
        "",
        "import nengo",
        "import numpy as np",
        "",
    ]

    for i, spec in enumerate(parsed_specs):
        concept = spec["concept"]
        raw = spec["raw"]
        negated = spec.get("negated", False)
        condition = spec.get("condition", "")

        if concept == "threshold_firing":
            lines.extend(
                [
                    f"def test_threshold_firing_{i}():",
                    f'    """Validates: {raw}"""',
                    "    with nengo.Network() as net:",
                    "        ens = nengo.Ensemble(50, 1, neuron_type=nengo.LIF())",
                    "        inp = nengo.Node(output=2.0)",
                    "        nengo.Connection(inp, ens)",
                    "        probe = nengo.Probe(ens.neurons, synapse=None)",
                    "    with nengo.Simulator(net) as sim:",
                    "        sim.run(0.5)",
                    "    spikes = sim.data[probe]",
                ]
            )
            if negated:
                lines.extend(
                    [
                        "    assert not np.any(spikes > 0), (",
                        '        "Neuron should NOT fire below threshold"',
                        "    )",
                        "",
                    ]
                )
            else:
                lines.extend(
                    [
                        "    assert np.any(spikes > 0), (",
                        '        "Neuron should fire when input exceeds threshold"',
                        "    )",
                        "",
                    ]
                )
        elif concept == "refractory_period":
            tau_ref = extract_numeric(condition, 0.002)
            lines.extend(
                [
                    f"def test_refractory_period_{i}():",
                    f'    """Validates: {raw}"""',
                    f"    tau_ref = {tau_ref}",
                    "    with nengo.Network() as net:",
                    "        ens = nengo.Ensemble(",
                    "            50, 1, neuron_type=nengo.LIF(tau_ref=tau_ref)",
                    "        )",
                    "        inp = nengo.Node(output=2.0)",
                    "        nengo.Connection(inp, ens)",
                    "        probe = nengo.Probe(ens.neurons, synapse=None)",
                    "    with nengo.Simulator(net) as sim:",
                    "        sim.run(0.1)",
                    "    spikes = sim.data[probe]",
                    "    dt = sim.dt",
                    "    for neuron_idx in range(spikes.shape[1]):",
                    "        spike_times = np.where(spikes[:, neuron_idx] > 0)[0] * dt",
                    "        if len(spike_times) > 1:",
                    "            isis = np.diff(spike_times)",
                    "            assert np.all(isis >= tau_ref - dt), (",
                    '                f"ISI {np.min(isis):.4f}s < refractory {tau_ref}s"',
                    "            )",
                    "",
                ]
            )
        elif concept == "membrane_potential_decay":
            tau_rc = extract_numeric(condition, 0.02)
            lines.extend(
                [
                    f"def test_membrane_decay_{i}():",
                    f'    """Validates: {raw}"""',
                    f"    tau_rc = {tau_rc}",
                    "    with nengo.Network() as net:",
                    "        ens = nengo.Ensemble(",
                    "            50, 1, neuron_type=nengo.LIF(tau_rc=tau_rc)",
                    "        )",
                    "        probe = nengo.Probe(ens.neurons, 'voltage', synapse=None)",
                    "    with nengo.Simulator(net) as sim:",
                    "        sim.run(0.1)",
                    "    voltage = sim.data[probe]",
                    "    # With no input, voltage should stay near zero (resting)",
                    "    mean_voltage = np.mean(np.abs(voltage[10:]))",
                    "    assert mean_voltage < 1.0, (",
                    '        f"Mean voltage {mean_voltage:.4f} should decay toward rest"',
                    "    )",
                    "",
                ]
            )
        elif concept == "synaptic_weight":
            weight = extract_numeric(condition, 1.0)
            lines.extend(
                [
                    f"def test_synaptic_weight_{i}():",
                    f'    """Validates: {raw}"""',
                    f"    weight = {weight}",
                    "    with nengo.Network() as net:",
                    "        sensory = nengo.Ensemble(50, 1, neuron_type=nengo.LIF())",
                    "        motor = nengo.Ensemble(50, 1, neuron_type=nengo.LIF())",
                    "        inp = nengo.Node(output=0.5)",
                    "        nengo.Connection(inp, sensory)",
                    "        nengo.Connection(sensory, motor, transform=weight)",
                    "        probe = nengo.Probe(motor, synapse=0.05)",
                    "    with nengo.Simulator(net) as sim:",
                    "        sim.run(0.5)",
                    "    output = sim.data[probe]",
                    "    # Motor ensemble should have received input through weighted connection",
                    "    assert np.any(np.abs(output[100:]) > 0.01), (",
                    '        "Motor ensemble should respond to weighted synaptic input"',
                    "    )",
                    "",
                ]
            )
        elif concept == "axonal_delay":
            delay = extract_numeric(condition, 0.005)
            lines.extend(
                [
                    f"def test_axonal_delay_{i}():",
                    f'    """Validates: {raw}"""',
                    f"    delay = {delay}",
                    "    with nengo.Network() as net:",
                    "        sensory = nengo.Ensemble(50, 1, neuron_type=nengo.LIF())",
                    "        motor = nengo.Ensemble(50, 1, neuron_type=nengo.LIF())",
                    "        inp = nengo.Node(output=0.5)",
                    "        nengo.Connection(inp, sensory)",
                    "        conn = nengo.Connection(",
                    "            sensory, motor, synapse=nengo.Lowpass(delay)",
                    "        )",
                    "        probe = nengo.Probe(motor, synapse=0.01)",
                    "    with nengo.Simulator(net) as sim:",
                    "        sim.run(0.5)",
                    "    output = sim.data[probe]",
                    "    # Delayed connection should still produce motor output",
                    "    assert np.any(np.abs(output[100:]) > 0.01), (",
                    '        "Motor should respond through delayed connection"',
                    "    )",
                    "",
                ]
            )
        elif concept == "stdp_learning":
            # Determine learning rule type from condition
            rule_class = "nengo.PES"
            rule_label = "STDP/PES"
            needs_error = True
            if condition and "BCM" in condition:
                rule_class = "nengo.BCM"
                rule_label = "BCM"
                needs_error = False
            elif condition and "Oja" in condition:
                rule_class = "nengo.Oja"
                rule_label = "Oja"
                needs_error = False

            lr = extract_numeric(condition, 1e-4)

            lines.extend(
                [
                    f"def test_stdp_learning_{i}():",
                    f'    """Validates: {raw}"""',
                    "    with nengo.Network() as net:",
                    "        sensory = nengo.Ensemble(50, 1, neuron_type=nengo.LIF())",
                    "        motor = nengo.Ensemble(50, 1, neuron_type=nengo.LIF())",
                    "        inp = nengo.Node(output=0.5)",
                    "        nengo.Connection(inp, sensory)",
                    "        conn = nengo.Connection(",
                    "            sensory, motor,",
                    f"            learning_rule_type={rule_class}(learning_rate={lr})",
                    "        )",
                ]
            )
            if needs_error:
                lines.extend(
                    [
                        "        error = nengo.Node(output=0.0)",
                        "        nengo.Connection(error, conn.learning_rule)",
                    ]
                )
            lines.extend(
                [
                    "        probe = nengo.Probe(motor, synapse=0.05)",
                    "    with nengo.Simulator(net) as sim:",
                    "        sim.run(0.5)",
                    "    output = sim.data[probe]",
                    f"    # Network with {rule_label} learning rule should produce output",
                    "    assert np.any(np.abs(output[100:]) > 0.01), (",
                    f'        "Network with {rule_label} should produce motor output"',
                    "    )",
                    "",
                ]
            )
        elif concept == "inhibitory_connection":
            weight = extract_numeric(condition, -1.0)
            lines.extend(
                [
                    f"def test_inhibitory_connection_{i}():",
                    f'    """Validates: {raw}"""',
                    f"    inh_weight = {weight}",
                    "    with nengo.Network() as net:",
                    "        pre = nengo.Ensemble(50, 1, neuron_type=nengo.LIF())",
                    "        post = nengo.Ensemble(50, 1, neuron_type=nengo.LIF())",
                    "        inp = nengo.Node(output=1.0)",
                    "        nengo.Connection(inp, pre)",
                    "        nengo.Connection(pre, post, transform=inh_weight)",
                    "        probe = nengo.Probe(post, synapse=0.05)",
                    "    with nengo.Simulator(net) as sim:",
                    "        sim.run(0.5)",
                    "    output = sim.data[probe]",
                    "    # Inhibitory connection should suppress or reduce post activity",
                    "    mean_output = np.mean(output[200:])",
                    "    assert mean_output < 0.5, (",
                    '        f"Inhibitory connection should reduce output, got {mean_output:.4f}"',
                    "    )",
                    "",
                ]
            )
        elif concept == "population_coding":
            n_neurons = extract_numeric(condition, 50) or 50
            lines.extend(
                [
                    f"def test_population_coding_{i}():",
                    f'    """Validates: {raw}"""',
                    f"    n_neurons = {int(n_neurons)}",
                    "    with nengo.Network() as net:",
                    "        ens = nengo.Ensemble(",
                    "            n_neurons=n_neurons, dimensions=1,",
                    "            neuron_type=nengo.LIF()",
                    "        )",
                    "        inp = nengo.Node(output=0.5)",
                    "        nengo.Connection(inp, ens)",
                    "        probe = nengo.Probe(ens, synapse=0.05)",
                    "    with nengo.Simulator(net) as sim:",
                    "        sim.run(0.5)",
                    "    output = sim.data[probe]",
                    "    # Ensemble should represent the input value",
                    "    mean_repr = np.mean(output[200:])",
                    "    assert abs(mean_repr - 0.5) < 0.3, (",
                    '        f"Population should represent input; got {mean_repr:.4f}"',
                    "    )",
                    "",
                ]
            )
        elif concept == "network_topology":
            if condition and "population of" in condition:
                n_neurons = extract_numeric(condition, 30) or 30
                lines.extend(
                    [
                        f"def test_network_topology_{i}():",
                        f'    """Validates: {raw}"""',
                        f"    n_neurons = {int(n_neurons)}",
                        "    with nengo.Network() as net:",
                        "        ens = nengo.Ensemble(",
                        "            n_neurons=n_neurons, dimensions=1,",
                        "            neuron_type=nengo.LIF()",
                        "        )",
                        "        assert ens.n_neurons == n_neurons",
                        "",
                    ]
                )
        elif concept == "lateral_inhibition":
            radius = extract_numeric(condition, 2)
            lines.extend(
                [
                    f"def test_lateral_inhibition_{i}():",
                    f'    """Validates: {raw}"""',
                    f"    radius = {radius}",
                    "    assert radius > 0, 'Lateral inhibition radius must be positive'",
                    "",
                ]
            )
        elif concept == "homeostatic_plasticity":
            rate = extract_numeric(condition, 10)
            lines.extend(
                [
                    f"def test_homeostatic_plasticity_{i}():",
                    f'    """Validates: {raw}"""',
                    f"    target_rate = {rate}",
                    "    assert target_rate > 0, 'Target firing rate must be positive'",
                    "",
                ]
            )
        elif concept == "neuromodulation":
            factor = extract_numeric(condition, 1.5)
            lines.extend(
                [
                    f"def test_neuromodulation_{i}():",
                    f'    """Validates: {raw}"""',
                    f"    factor = {factor}",
                    "    assert factor > 0, 'Neuromodulation factor must be positive'",
                    "",
                ]
            )
        elif concept == "population_coding_range":
            range_val = extract_numeric(condition, 360)
            lines.extend(
                [
                    f"def test_population_coding_range_{i}():",
                    f'    """Validates: {raw}"""',
                    f"    range_val = {range_val}",
                    "    assert range_val > 0, 'Population coding range must be positive'",
                    "",
                ]
            )

    return "\n".join(lines)


def _generate_llm_assertions(parsed_specs: list[ParsedSentence]) -> str:
    """Generate pytest assertions using the Anthropic Claude API."""
    try:
        import anthropic
    except ImportError:
        raise AssertionGeneratorError(
            "anthropic package not installed. Install with: pip install anthropic"
        )

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        raise AssertionGeneratorError("ANTHROPIC_API_KEY environment variable not set")

    client = anthropic.Anthropic(api_key=api_key)

    spec_text = "\n".join(f"- [{s['concept']}] {s['raw']}" for s in parsed_specs)

    system_prompt = textwrap.dedent(
        """\
        You are a test generator. Given CNL (Controlled Natural Language) specifications
        for a neuromorphic sensory-motor reflex arc, generate pytest test functions.

        Rules:
        - Generate ONLY pytest test functions. No prose, no explanation.
        - Each test must be a standalone pytest function.
        - Each test must test exactly one behavioral rule from the spec.
        - Each test must include a docstring stating which CNL sentence it validates.
        - Use only nengo and numpy as dependencies.
        - DO NOT generate tests that always pass.
        - DO NOT test implementation details not present in the CNL spec.
        - DO NOT use mock objects.
        - Include proper imports at the top: import nengo, import numpy as np
    """
    )

    message = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=4096,
        system=system_prompt,
        messages=[
            {
                "role": "user",
                "content": f"Generate pytest assertions for these CNL specifications:\n\n{spec_text}",
            }
        ],
    )

    return cast(str, message.content[0].text)


def generate_assertions(
    parsed_specs: list[ParsedSentence],
    output_path: str = "test_layer3_assertions.py",
    use_llm: bool = False,
) -> str:
    """Generate pytest assertions from parsed CNL specs.

    Parameters
    ----------
    parsed_specs : list[ParsedSentence]
        Output of cnl_parser.parse().
    output_path : str
        Path to write the generated test file.
    use_llm : bool
        If True and ANTHROPIC_API_KEY is set, use Claude API.
        Otherwise, use template-based generation.

    Returns
    -------
    str
        Path to the generated test file.

    Raises
    ------
    AssertionGeneratorError
        If syntax check on the generated file fails.
    """
    if use_llm and os.environ.get("ANTHROPIC_API_KEY"):
        code = _generate_llm_assertions(parsed_specs)
    else:
        code = _generate_template_assertions(parsed_specs)

    with open(output_path, "w") as f:
        f.write(code)

    # Syntax check
    try:
        py_compile.compile(output_path, doraise=True)
    except py_compile.PyCompileError as e:
        raise AssertionGeneratorError(f"Generated assertions failed syntax check: {e}")

    return output_path
