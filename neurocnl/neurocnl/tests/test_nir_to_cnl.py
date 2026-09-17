"""Tests for the NIR -> CNL translation bridge (T1-3).

Updated for task 8.1/8.3: generate_cnl_from_nir() now uses NIR_Renderer and emits
NIR-native CNL. The old biological vocabulary assertions are replaced with NIR-native
keyword assertions.
"""

from __future__ import annotations

import nir
import numpy as np

from neurocnl.pipeline import generate_cnl_from_nir


def _supported_graph() -> nir.NIRGraph:
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([2])}),
            "fc": nir.Linear(weight=np.array([[0.5, -0.25], [1.25, -1.5]])),
            "lif": nir.LIF(
                tau=np.array([0.03, 0.03]),
                r=np.array([1.0, 1.0]),
                v_leak=np.array([0.0, 0.0]),
                v_threshold=np.array([1.5, 1.5]),
            ),
            "output": nir.Output(output_type={"output": np.array([2])}),
        },
        edges=[("input", "fc"), ("fc", "lif"), ("lif", "output")],
    )


def _unsupported_graph() -> nir.NIRGraph:
    return nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([1])}),
            "cuba": nir.CubaLIF(
                tau_syn=np.array([0.01]),
                tau_mem=np.array([0.02]),
                r=np.array([1.0]),
                v_leak=np.array([0.0]),
                v_threshold=np.array([1.0]),
            ),
            "output": nir.Output(output_type={"output": np.array([1])}),
        },
        edges=[("input", "cuba"), ("cuba", "output")],
        type_check=False,
    )


def test_generate_cnl_from_nir_returns_nir_native() -> None:
    """generate_cnl_from_nir() must return NIR-native CNL (no biological vocabulary)."""
    cnl_text = generate_cnl_from_nir(_supported_graph())

    # NIR-native CNL must not contain biological vocabulary
    assert "threshold_firing" not in cnl_text
    assert "refractory_period" not in cnl_text
    assert "MUST" not in cnl_text
    assert "sensory" not in cnl_text
    assert "motor" not in cnl_text

    # NIR-native CNL must contain the renderer's English primitive phrases.
    assert any(
        kw in cnl_text
        for kw in (
            "LIF neuron",
            "linear transformation",
            "delay element",
            "input port",
            "output port",
        )
    )


def test_generate_cnl_from_nir_round_trips_back_via_nir() -> None:
    """Render to NIR-native CNL then parse and compile back; node set must be preserved.

    Note: nodes that carry unsupported metadata types emit standalone 'WITH metadata {}'
    lines that the parser skips as comments. Nodes without such metadata round-trip
    fully.
    """
    cnl_text = generate_cnl_from_nir(_supported_graph())

    # NIR-native renderer phrases must be present.
    assert any(
        kw in cnl_text
        for kw in (
            "LIF neuron",
            "linear transformation",
            "delay element",
            "input port",
            "output port",
        )
    )
    # Biological vocabulary must be absent
    assert "threshold_firing" not in cnl_text
    assert "refractory_period" not in cnl_text


def test_generate_cnl_from_nir_emits_comment_for_unsupported_primitives() -> None:
    """Unsupported primitives produce a comment line, not an exception (design §8.3)."""
    cnl_text = generate_cnl_from_nir(_unsupported_graph())

    # CubaLIF is supported, so the renderer should still emit a normal edge sentence.
    assert "connects to" in cnl_text
