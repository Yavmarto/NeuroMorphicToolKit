"""PBT — `_project_to_canvas` nir_type round-trip.

**Validates: Requirements 2.1, 2.4**

Property 2: Bug Condition — nir_type Emitted by Python Projection

For any NIR graph passed to `_project_to_canvas` where `nir_graph` is non-null and
a node name exists in both `ir.populations` and `nir_graph.nodes`, the fixed
`_project_to_canvas` SHALL include a `nir_type` key in that node's dict whose value
is `f"nir.{type(nir_graph.nodes[name]).__name__}"`.
"""

from __future__ import annotations

import nir
import numpy as np
from hypothesis import given, settings
from hypothesis import strategies as st

from neurocnl.ir.types import NetworkIR, PopulationIR
from neurosim.app.services.canonical_editor_projection import _project_to_canvas

# ---------------------------------------------------------------------------
# NIR node factories — minimal valid instances for each known primitive
# ---------------------------------------------------------------------------

_ARR = np.array([1.0])  # shared scalar-shaped array for all numeric params


def _make_lif() -> nir.LIF:
    return nir.LIF(tau=_ARR, r=_ARR, v_leak=_ARR * 0, v_threshold=_ARR)


def _make_input() -> nir.Input:
    return nir.Input(input_type={"input": _ARR})


def _make_output() -> nir.Output:
    return nir.Output(output_type={"output": _ARR})


def _make_cuba_lif() -> nir.CubaLIF:
    return nir.CubaLIF(
        tau_syn=_ARR,
        tau_mem=_ARR,
        r=_ARR,
        v_leak=_ARR * 0,
        v_threshold=_ARR,
    )


def _make_if() -> nir.IF:
    return nir.IF(r=_ARR, v_threshold=_ARR)


def _make_li() -> nir.LI:
    return nir.LI(tau=_ARR, r=_ARR, v_leak=_ARR * 0)


from typing import Any

# Map from NIR class name to zero-arg factory
_NIR_FACTORIES: dict[str, Any] = {
    "LIF": _make_lif,
    "Input": _make_input,
    "Output": _make_output,
    "CubaLIF": _make_cuba_lif,
    "IF": _make_if,
    "LI": _make_li,
}

# ---------------------------------------------------------------------------
# Hypothesis strategy
# ---------------------------------------------------------------------------


@st.composite
def nir_node_list_strategy(draw: st.DrawFn) -> list[tuple[str, Any]]:
    """Draw a non-empty list of (unique population name, nir_node) pairs."""
    class_names = draw(
        st.lists(
            st.sampled_from(list(_NIR_FACTORIES.keys())),
            min_size=1,
            max_size=8,
        )
    )
    # Assign unique names to each node slot (e.g. LIF_0, Input_1)
    named_nodes = [
        (f"{cls_name.lower()}_{i}", _NIR_FACTORIES[cls_name]())
        for i, cls_name in enumerate(class_names)
    ]
    return named_nodes


# ---------------------------------------------------------------------------
# Property test
# ---------------------------------------------------------------------------


@settings(max_examples=100, deadline=None)
@given(nir_node_list_strategy())
def test_pbt_nir_type_round_trip(named_nodes: Any) -> None:
    """**Validates: Requirements 2.1, 2.4**

    For any non-empty list of NIR node instances, `_project_to_canvas` emits
    a `nir_type` key for every node whose value matches
    `f"nir.{type(nir_graph.nodes[name]).__name__}"`.
    """
    # Build a minimal NetworkIR with one PopulationIR per node
    populations = {name: PopulationIR(name=name, size=1) for name, _node in named_nodes}
    ir = NetworkIR(populations=populations, connections=[])

    # Build a NIRGraph with the drawn node instances.
    # type_check=False because _project_to_canvas only reads nir_graph.nodes —
    # it does not require a topologically valid graph; the NIRGraph type-inference
    # step would otherwise fail for isolated or Output-only node lists.
    nir_graph = nir.NIRGraph(
        nodes={name: node for name, node in named_nodes},
        edges=[],
        type_check=False,
    )

    result = _project_to_canvas(ir, [], nir_graph=nir_graph)

    # Index result nodes by id for easy lookup
    result_by_id = {node_dict["id"]: node_dict for node_dict in result.nodes}

    for pop_name, nir_node in named_nodes:
        assert (
            pop_name in result_by_id
        ), f"Population '{pop_name}' missing from projection output"
        node_dict = result_by_id[pop_name]

        assert (
            "nir_type" in node_dict
        ), f"Node '{pop_name}' dict is missing 'nir_type' key"

        expected_nir_type = f"nir.{type(nir_node).__name__}"
        actual_nir_type = node_dict["nir_type"]

        assert (
            actual_nir_type == expected_nir_type
        ), f"Node '{pop_name}': expected nir_type={expected_nir_type!r}, got {actual_nir_type!r}"
