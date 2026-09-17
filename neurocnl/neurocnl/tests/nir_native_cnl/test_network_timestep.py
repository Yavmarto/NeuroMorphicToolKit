"""Tests for the network sentence's optional ``with timestep <seconds>`` clause.

Covers the grammar addition (Requirement 1.7's optional network-timestep
clause): happy-path parsing with and without the clause, invalid-value
diagnostics, compiler propagation into ``nir.LIF`` node metadata and the
compiled graph's own metadata, explicit per-node overrides winning over
the declared default, the undeclared case staying byte-for-byte
unchanged (critical backward-compat guarantee), and a render -> reparse
-> recompile round trip.

_Validates: nir_cnl network-timestep grammar extension_
"""

from __future__ import annotations

import pytest

from neurocnl.compile import compile_to_nir
from neurocnl.nir_cnl.errors import ParseError
from neurocnl.nir_cnl.ir_types import NetworkContainer
from neurocnl.nir_cnl.parser import NIR_CNL_Parser
from neurocnl.nir_cnl.renderer import NIR_Renderer

_SPEC_TEMPLATE = "\n".join(
    [
        "Define a network named demo{network_clause}.",
        "Define an input port named in1 with shape (1,).",
        "Define a LIF neuron named n1 with time constant 0.02, resistance 1.0,"
        " leak voltage 0.0, and firing threshold 1.0{node_clause}.",
        "Define an output port named out1 with shape (1,).",
        "in1 connects to n1.",
        "n1 connects to out1.",
    ]
)


def _spec(network_clause: str = "", node_clause: str = "") -> str:
    return _SPEC_TEMPLATE.format(network_clause=network_clause, node_clause=node_clause)


def _parse_network(text: str) -> NetworkContainer:
    records = NIR_CNL_Parser().parse(text)
    containers = [r for r in records if isinstance(r, NetworkContainer)]
    assert len(containers) == 1
    return containers[0]


def _codes(exc_info: pytest.ExceptionInfo[ParseError]) -> set[str]:
    return {d.code for d in exc_info.value.errors}


# ---------------------------------------------------------------------------
# Parser
# ---------------------------------------------------------------------------


def test_network_sentence_without_timestep_leaves_field_none() -> None:
    container = _parse_network(_spec())
    assert container == NetworkContainer(name="demo", line=1, timestep_seconds=None)


def test_network_sentence_with_timestep_parses_value() -> None:
    container = _parse_network(_spec(network_clause=" with timestep 0.001"))
    assert container == NetworkContainer(name="demo", line=1, timestep_seconds=0.001)


def test_network_sentence_rejects_non_numeric_timestep() -> None:
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse(_spec(network_clause=" with timestep foo"))
    assert "invalid_value" in _codes(exc_info)


def test_network_sentence_rejects_zero_timestep() -> None:
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse(_spec(network_clause=" with timestep 0"))
    assert "invalid_value" in _codes(exc_info)


def test_network_sentence_rejects_negative_timestep() -> None:
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse(_spec(network_clause=" with timestep -0.001"))
    assert "invalid_value" in _codes(exc_info)


def test_network_sentence_missing_named_keyword_still_syntax_error() -> None:
    """Regression: the new optional clause must not weaken the existing
    strict identifier-parsing path for malformed sentences."""
    with pytest.raises(ParseError) as exc_info:
        NIR_CNL_Parser().parse("Define a network demo.")
    assert "syntax_error" in _codes(exc_info)


# ---------------------------------------------------------------------------
# Compiler propagation
# ---------------------------------------------------------------------------


def test_compiler_injects_declared_timestep_into_graph_and_lif_metadata() -> None:
    graph = compile_to_nir(_spec(network_clause=" with timestep 0.001"))
    assert graph.metadata.get("dt") == 0.001
    assert graph.nodes["n1"].metadata.get("dt") == 0.001


def test_compiler_no_declaration_injects_nothing() -> None:
    """Critical backward-compat guarantee: an undeclared network timestep
    must leave graph/node metadata exactly as before this change — no
    'dt' key anywhere — so notebook.py's existing 1e-4 default fallback
    is completely unaffected."""
    graph = compile_to_nir(_spec())
    assert "dt" not in graph.metadata
    assert "dt" not in graph.nodes["n1"].metadata


def test_compiler_explicit_node_override_wins_over_declared_default() -> None:
    graph = compile_to_nir(
        _spec(
            network_clause=" with timestep 0.001",
            node_clause=", annotated with metadata dt equal to 0.0005",
        )
    )
    assert graph.metadata.get("dt") == 0.001
    assert graph.nodes["n1"].metadata.get("dt") == 0.0005


# ---------------------------------------------------------------------------
# Renderer round trip
# ---------------------------------------------------------------------------


def test_render_emits_network_timestep_and_suppresses_inherited_node_clause() -> None:
    graph = compile_to_nir(_spec(network_clause=" with timestep 0.001"))
    text = NIR_Renderer().render(graph)
    assert "Define a network named demo with timestep 0.001." in text
    assert "annotated with metadata dt equal to" not in text


def test_render_still_emits_explicit_node_override_that_differs() -> None:
    graph = compile_to_nir(
        _spec(
            network_clause=" with timestep 0.001",
            node_clause=", annotated with metadata dt equal to 0.0005",
        )
    )
    text = NIR_Renderer().render(graph)
    assert "Define a network named demo with timestep 0.001." in text
    assert "annotated with metadata dt equal to 0.0005" in text


def test_render_reparse_recompile_round_trip_preserves_timestep() -> None:
    graph = compile_to_nir(_spec(network_clause=" with timestep 0.001"))
    text = NIR_Renderer().render(graph)
    recompiled = compile_to_nir(text)
    assert recompiled.metadata.get("dt") == 0.001
    assert recompiled.nodes["n1"].metadata.get("dt") == 0.001
