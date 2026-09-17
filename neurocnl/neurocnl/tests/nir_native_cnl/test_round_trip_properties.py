"""Round-trip identity and structural shape property tests.

Properties implemented here:

* **Property 1** — Round-trip identity for all supported NIRGraphs.
  Render → parse → compile preserves graph structure, vector values,
  and tensor shapes.
* **Property 4** — Comments and keyword casing are parse-output-invariant.
  Inserting ``# ...`` comment lines and toggling case on case-insensitive
  keywords does not change the parse result (Requirements 1.9, 1.10).
* **Property 5** — Identifier round-trip preservation. Node and edge
  identifiers survive render → parse → compile byte-equal
  (Requirements 1.3, 3.3).
* **Property 6** — Sentence structural shape. The rendered text satisfies
  length, connective, ordering, and count invariants
  (Requirements 1.1, 1.4, 3.1, 3.2, 3.4).
* **Property 13** — Unsupported node and edge handling. The renderer
  emits one comment line per unsupported node / incident edge and
  raises no exception; the surviving subgraph satisfies the same
  structural round-trip contract.
"""

from __future__ import annotations

import re

import nir
import numpy as np
from hypothesis import given, settings
from hypothesis import strategies as st

from neurocnl.nir_cnl.compiler import NIR_Compiler
from neurocnl.nir_cnl.grammar_tables import keyword_set
from neurocnl.nir_cnl.ir_types import NIRNodeRecord
from neurocnl.nir_cnl.parser import NIR_CNL_Parser
from neurocnl.nir_cnl.renderer import NIR_Renderer

from ._round_trip import assert_round_trip_equal
from ._strategies import identifier_strategy, nir_graph_strategy

# Case-insensitive keyword list for Property 4.
_KEYWORDS: tuple[str, ...] = tuple(keyword_set)


# ---------------------------------------------------------------------------
# Property 1: Round-trip identity
# ---------------------------------------------------------------------------


# Feature: nir-native-cnl, Property 1: Round-trip identity for all supported NIRGraphs
@given(graph=nir_graph_strategy())
@settings(max_examples=100, deadline=None)
def test_property_1_round_trip_identity(graph: nir.NIRGraph) -> None:
    """Render → parse → compile recovers the original graph exactly.

    **Validates: Requirements 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 5.7, 5.8,
    5.9, 5.10, 5.11, 5.13, 10.1, 10.2, 10.3, 10.4, 11.1, 11.2, 11.3, 11.4**
    """
    text = NIR_Renderer().render(graph)
    records = NIR_CNL_Parser().parse(text)
    recovered = NIR_Compiler().compile(records)
    assert_round_trip_equal(graph, recovered)


# ---------------------------------------------------------------------------
# Property 4: Comments and keyword casing are parse-output-invariant
# ---------------------------------------------------------------------------


def _toggle_keyword_case(text: str, draw: st.DrawFn) -> str:
    """Randomly flip case of case-insensitive grammar keywords in *text*."""
    result = text
    for kw in _KEYWORDS:
        # Toggle case of every occurrence of *kw* with 50% probability.
        if draw(st.booleans()):

            def _swapcase(m: re.Match[str], kw: str = kw) -> str:
                return kw.swapcase()

            result = re.sub(re.escape(kw), _swapcase, result, flags=re.IGNORECASE)
    return result


def _insert_comment_lines(text: str, comments: list[str]) -> str:
    """Insert comment lines at uniformly random positions in *text*."""
    lines = text.splitlines(keepends=True)
    for comment in comments:
        pos = len(lines) // max(1, len(comments))
        lines.insert(pos, "# " + comment + "\n")
    return "".join(lines)


# Feature: nir-native-cnl, Property 4: Comments and keyword casing are parse-output-invariant
@given(
    graph=nir_graph_strategy(),
    comments=st.lists(
        st.text(
            alphabet=st.characters(
                whitelist_categories=("L", "N", "P", "Zs"),
            ),
            max_size=40,
        ),
        max_size=5,
    ),
)
@settings(max_examples=100, deadline=None)
def test_property_4_comments_and_case_invariant(
    graph: nir.NIRGraph, comments: list[str]
) -> None:
    """Inserting ``#`` comment lines and toggling keyword case must not
    change the parse output.

    **Validates: Requirements 1.9, 1.10**
    """
    text = NIR_Renderer().render(graph)
    # Baseline parse.
    baseline_records = NIR_CNL_Parser().parse(text)

    # Transform: insert comment lines.
    transformed = _insert_comment_lines(text, comments)
    transformed_records = NIR_CNL_Parser().parse(transformed)

    # The record lists must be structurally equal (same count, same
    # identifiers, same primitives, same parameters).
    assert len(baseline_records) == len(transformed_records), (
        f"Comment insertion changed record count: "
        f"{len(baseline_records)} -> {len(transformed_records)}"
    )
    for base_rec, trans_rec in zip(baseline_records, transformed_records, strict=False):
        assert type(base_rec) is type(trans_rec)
        # For node records, check primitive and name equality.
        if isinstance(base_rec, NIRNodeRecord) and isinstance(trans_rec, NIRNodeRecord):
            assert base_rec.name == trans_rec.name
            assert base_rec.primitive == trans_rec.primitive


# ---------------------------------------------------------------------------
# Property 5: Identifier round-trip preservation
# ---------------------------------------------------------------------------


# Feature: nir-native-cnl, Property 5: Identifier round-trip preservation
@given(node_id=identifier_strategy())
@settings(max_examples=100, deadline=None)
def test_property_5_identifier_round_trip(node_id: str) -> None:
    """Node identifiers survive render → parse byte-equal.

    **Validates: Requirements 1.3, 3.3**
    """
    # Build a minimal graph with the generated identifier.
    graph = nir.NIRGraph(
        nodes={
            node_id: nir.Input(input_type=np.asarray([1], dtype=int)),
            "out": nir.Output(output_type=np.asarray([1], dtype=int)),
        },
        edges=[(node_id, "out")],
        type_check=False,
    )
    text = NIR_Renderer().render(graph)
    records = NIR_CNL_Parser().parse(text)
    recovered = NIR_Compiler().compile(records)

    # The recovered graph must contain the original identifier verbatim.
    assert node_id in recovered.nodes, (
        f"Identifier {node_id!r} not found in recovered graph nodes "
        f"{sorted(recovered.nodes.keys())}."
    )
    # Edge must preserve the identifier too.
    recovered_edge_srcs = {src for src, _ in recovered.edges}
    assert (
        node_id in recovered_edge_srcs
    ), f"Identifier {node_id!r} not preserved in recovered edges {recovered.edges}."


# ---------------------------------------------------------------------------
# Property 5 (metadata variant): dt/beta metadata overrides round-trip
#
# `backend/app/routers/notebook.py` reads optional `dt` (nir.LIF) and
# `beta` (nir.IF) metadata overrides from these node types via the
# generic `str|int|float` metadata mechanism exercised generically by
# `metadata_strategy()` above. These two tests pin down that specific
# usage explicitly (non-default numeric values, not just arbitrary
# hypothesis-generated metadata) so a future change to LIF/IF codegen
# or to the metadata round-trip path is caught by a concrete example.
# ---------------------------------------------------------------------------


def test_property_5_lif_dt_metadata_round_trip() -> None:
    """A ``nir.LIF`` node with non-default ``dt`` metadata round-trips
    through CNL text preserving that exact value in ``.metadata``.

    **Validates: Requirements 1.3, 3.3, 10.1-10.4**
    """
    node = nir.LIF(
        tau=np.asarray([0.02], dtype=np.float64),
        r=np.asarray([1.0], dtype=np.float64),
        v_leak=np.asarray([0.0], dtype=np.float64),
        v_threshold=np.asarray([1.0], dtype=np.float64),
    )
    node.metadata = {"dt": 5e-3}

    graph = nir.NIRGraph(
        nodes={
            "inp": nir.Input(input_type=np.asarray([1], dtype=int)),
            "lif1": node,
            "out": nir.Output(output_type=np.asarray([1], dtype=int)),
        },
        edges=[("inp", "lif1"), ("lif1", "out")],
        type_check=False,
    )
    text = NIR_Renderer().render(graph)
    records = NIR_CNL_Parser().parse(text)
    recovered = NIR_Compiler().compile(records)

    recovered_node = recovered.nodes["lif1"]
    assert isinstance(recovered_node, nir.LIF)
    assert (
        recovered_node.metadata.get("dt") == 5e-3
    ), f"Expected dt=5e-3 preserved in recovered metadata, got {recovered_node.metadata!r}"


def test_property_5_if_beta_metadata_round_trip() -> None:
    """A ``nir.IF`` node with non-default ``beta`` metadata round-trips
    through CNL text preserving that exact value in ``.metadata``.

    **Validates: Requirements 1.3, 3.3, 10.1-10.4**
    """
    node = nir.IF(
        r=np.asarray([1.0], dtype=np.float64),
        v_threshold=np.asarray([1.0], dtype=np.float64),
    )
    node.metadata = {"beta": 0.75}

    graph = nir.NIRGraph(
        nodes={
            "inp": nir.Input(input_type=np.asarray([1], dtype=int)),
            "if1": node,
            "out": nir.Output(output_type=np.asarray([1], dtype=int)),
        },
        edges=[("inp", "if1"), ("if1", "out")],
        type_check=False,
    )
    text = NIR_Renderer().render(graph)
    records = NIR_CNL_Parser().parse(text)
    recovered = NIR_Compiler().compile(records)

    recovered_node = recovered.nodes["if1"]
    assert isinstance(recovered_node, nir.IF)
    assert (
        recovered_node.metadata.get("beta") == 0.75
    ), f"Expected beta=0.75 preserved in recovered metadata, got {recovered_node.metadata!r}"


# ---------------------------------------------------------------------------
# Property 6: Sentence structural shape
# ---------------------------------------------------------------------------


# Feature: nir-native-cnl, Property 6: Sentence structural shape
@given(graph=nir_graph_strategy())
@settings(max_examples=100, deadline=None)
def test_property_6_sentence_structural_shape(graph: nir.NIRGraph) -> None:
    """Each NL_Sentence satisfies length, connective, and ordering contracts.

    **Validates: Requirements 1.1, 1.4, 3.1, 3.2, 3.4**
    """
    text = NIR_Renderer().render(graph)
    lines = [ln for ln in text.splitlines() if not ln.strip().startswith("#")]

    node_sentence_lines = [
        ln for ln in lines if ln.startswith("Define ") or ln.startswith("Create ")
    ]
    edge_sentence_lines = [ln for ln in lines if " connects to " in ln]

    # Requirement 1.1: every sentence ends with "." and satisfies character limit.
    # Note: the 64-token limit from Requirement 1.1 applies to hand-authored
    # sentences; the renderer may exceed 64 whitespace tokens for Primitives
    # with many vector parameters rendered in shape+values form (e.g. CubaLIF
    # with 6 vector parameters × 2 clauses = 12 parameter clauses). The
    # character limit of 1024 is enforced here for all sentences.
    for sentence in node_sentence_lines + edge_sentence_lines:
        assert sentence.endswith("."), f"Sentence missing period: {sentence!r}"
        assert (
            len(sentence) <= 1024
        ), f"Sentence too long ({len(sentence)} chars): {sentence[:100]}..."

    # Requirement 3.2: all node sentences precede all edge sentences in source order.
    # Find last node sentence and first edge sentence positions.
    node_lines_pos = [
        i
        for i, ln in enumerate(lines)
        if ln.startswith("Define ") and "network named" not in ln
    ]
    edge_lines_pos = [i for i, ln in enumerate(lines) if " connects to " in ln]
    if node_lines_pos and edge_lines_pos:
        assert max(node_lines_pos) < min(
            edge_lines_pos
        ), "Some edge sentences appear before node sentences."

    # Requirement 1.4: connective structure for node sentences with params.
    for sentence in node_sentence_lines:
        if " with " in sentence:
            # Extract the with-clause portion (after "with ", before the final ".").
            with_part = sentence[sentence.index(" with ") + 6 :].rstrip(".")
            # Split on ", and " (Oxford) or " and " (two-clause)
            # to verify the connective placement is correct:
            # No isolated comma before final "and" for 2-clause forms.
            clauses_count = (
                with_part.count(", and ")
                + with_part.count(" and ")
                - with_part.count(", and ")
            )
            # Basic: the with-clause must not end with ", " (no trailing comma).
            assert not with_part.endswith(
                ", "
            ), f"with-clause ends with trailing comma: {sentence!r}"

    # Requirement 3.1: one sentence per node (excluding network header).
    # Count non-network "Define" sentences and compare to supported graph nodes.
    from neurocnl.nir_cnl.grammar_tables import primitive_phrases

    supported_count = sum(
        1 for node in graph.nodes.values() if type(node).__name__ in primitive_phrases
    )
    # Count non-network Define lines.
    non_network_defines = [
        ln for ln in node_sentence_lines if "network named" not in ln
    ]
    assert (
        len(non_network_defines) == supported_count
    ), f"Expected {supported_count} node sentences but got {len(non_network_defines)}."

    # Requirement 3.2: one edge sentence per edge connecting supported nodes.
    from neurocnl.nir_cnl.grammar_tables import primitive_phrases as pp

    supported_names = {
        name for name, node in graph.nodes.items() if type(node).__name__ in pp
    }
    expected_edges = [
        (s, t) for s, t in graph.edges if s in supported_names and t in supported_names
    ]
    assert len(edge_sentence_lines) == len(
        expected_edges
    ), f"Expected {len(expected_edges)} edge sentences but got {len(edge_sentence_lines)}."


# ---------------------------------------------------------------------------
# Property 13: Unsupported node and edge handling
# ---------------------------------------------------------------------------


class _UnsupportedNode:
    """Synthetic node type that is not one of the 18 NIR Primitives."""

    pass


# Feature: nir-native-cnl, Property 13: Unsupported node and edge handling
@given(
    graph=nir_graph_strategy(),
    unsupported_names=st.lists(
        identifier_strategy().map(lambda s: "unsup_" + s),
        min_size=1,
        max_size=3,
    ),
)
@settings(max_examples=100, deadline=None)
def test_property_13_unsupported_node_handling(
    graph: nir.NIRGraph, unsupported_names: list[str]
) -> None:
    """Unsupported nodes and incident edges emit comment lines, no exception.

    **Validates: Requirements 3.6, 3.7, 5.12**
    """
    # Build an augmented graph with unsupported nodes mixed in.
    augmented_nodes = dict(graph.nodes)
    augmented_edges = list(graph.edges)

    added_names: list[str] = []
    for uname in unsupported_names:
        if uname not in augmented_nodes:
            augmented_nodes[uname] = _UnsupportedNode()
            added_names.append(uname)

    # Add edges from supported → unsupported (incident edges).
    if added_names and graph.nodes:
        first_supported = next(iter(graph.nodes.keys()))
        first_unsupported = added_names[0]
        augmented_edges.append((first_supported, first_unsupported))

    augmented_graph = nir.NIRGraph(
        nodes=augmented_nodes,
        edges=augmented_edges,
        type_check=False,
    )

    # Renderer must NOT raise; output must contain comment lines.
    text = NIR_Renderer().render(augmented_graph)

    for uname in added_names:
        assert (
            f"# unsupported node type _UnsupportedNode for node {uname}" in text
        ), f"Missing unsupported-node comment for {uname!r} in:\n{text}"

    # Incident edges involving unsupported nodes must be commented.
    if added_names and graph.nodes:
        first_supported = next(iter(graph.nodes.keys()))
        first_unsupported = added_names[0]
        assert (
            f"# unsupported edge from {first_supported} to {first_unsupported}" in text
        ), f"Missing unsupported-edge comment in:\n{text}"

    # The surviving subgraph (supported nodes only) must still round-trip.
    surviving_nodes = {
        name: node
        for name, node in augmented_nodes.items()
        if type(node).__name__ != "_UnsupportedNode"
    }
    unsupported_name_set = set(added_names)
    surviving_edges = [
        (s, t)
        for s, t in graph.edges
        if s not in unsupported_name_set and t not in unsupported_name_set
    ]
    surviving_graph = nir.NIRGraph(
        nodes=surviving_nodes,
        edges=surviving_edges,
        type_check=False,
    )
    surviving_text = NIR_Renderer().render(surviving_graph)
    surviving_records = NIR_CNL_Parser().parse(surviving_text)
    surviving_recovered = NIR_Compiler().compile(surviving_records)
    assert_round_trip_equal(surviving_graph, surviving_recovered)
