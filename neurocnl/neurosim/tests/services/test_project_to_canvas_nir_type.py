"""Unit tests for _project_to_canvas nir_type emission.

Validates: Requirements 2.1, 2.4

These tests confirm that _project_to_canvas correctly:
- Emits a ``nir_type`` key in every node dict.
- Sets ``nir_type`` to ``f"nir.{type(node).__name__}"`` for standard NIR node
  types present in a non-None ``nir_graph`` (that naive guess happens to
  already match the canonical value for these types).
- Sets ``nir_type`` to the canonical ``"cnl.<ClassName>"`` string (NOT the
  naive ``f"nir.{ClassName}"`` guess) for CNLStudio-internal node types
  (``Synaptic``/``RSynaptic``) that carry a ``CNL_NIR_TYPE`` in the ``cnl.``
  namespace — see ``neurocnl/runtime/cnl_nodes.py``. Regression coverage for
  the bug where the top-level ``nir_type`` field disagreed with the correct
  value already computed for ``parameters['nir_type']``/
  ``metadata['canvas_component_id']`` on the same node, silently breaking
  canvas port/edge rendering for these two node types.
- Sets ``nir_type`` to ``None`` for all nodes when ``nir_graph`` is ``None``.
"""

from __future__ import annotations

from types import SimpleNamespace

import nir as _nir
import numpy as np

from neurocnl.ir.types import NetworkIR, PopulationIR
from neurocnl.runtime.cnl_nodes import RSynaptic, Synaptic

# Import the private function directly as instructed by the task spec.
from neurosim.app.services.canonical_editor_projection import _project_to_canvas

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

_SHAPE = np.array([1])


def _make_nir_lif() -> _nir.LIF:
    return _nir.LIF(tau=_SHAPE, r=_SHAPE, v_leak=_SHAPE, v_threshold=_SHAPE)


def _make_nir_input() -> _nir.Input:
    return _nir.Input(input_type={"input": _SHAPE})


def _make_nir_output() -> _nir.Output:
    return _nir.Output(output_type={"output": _SHAPE})


def _make_nir_cuba_lif() -> _nir.CubaLIF:
    return _nir.CubaLIF(
        tau_syn=_SHAPE,
        tau_mem=_SHAPE,
        r=_SHAPE,
        v_leak=_SHAPE,
        v_threshold=_SHAPE,
    )


def _ir_for_names(names: list[str]) -> NetworkIR:
    """Build a minimal NetworkIR whose populations match ``names``."""
    return NetworkIR(
        populations={
            name: PopulationIR(name=name, size=1, population_type="excitatory") for name in names
        },
        connections=[],
    )


def _nir_graph_stub(node_map: dict[str, _nir.NIRNode]) -> SimpleNamespace:
    """Return a lightweight stub that exposes only the interface used by
    ``_project_to_canvas``: a ``nodes`` dict and an empty ``edges`` list.

    Using a stub avoids the NIRGraph topology-validation that rejects isolated
    Input/Output nodes (no outgoing / incoming edges) and auto-inserts extra
    nodes during ``infer_types()``.
    """
    return SimpleNamespace(nodes=node_map, edges=[])


# ---------------------------------------------------------------------------
# Tests — nir_graph is non-None
# ---------------------------------------------------------------------------


def test_nir_type_emitted_for_lif_node() -> None:
    """_project_to_canvas emits nir_type='nir.LIF' for an nir.LIF node."""
    lif_node = _make_nir_lif()
    ir = _ir_for_names(["pop_lif"])
    nir_graph = _nir_graph_stub({"pop_lif": lif_node})

    projection = _project_to_canvas(ir, [], nir_graph=nir_graph)

    assert len(projection.nodes) == 1
    node_dict = projection.nodes[0]
    assert "nir_type" in node_dict
    assert node_dict["nir_type"] == f"nir.{type(lif_node).__name__}"
    assert node_dict["nir_type"] == "nir.LIF"


def test_nir_type_emitted_for_input_node() -> None:
    """_project_to_canvas emits nir_type='nir.Input' for an nir.Input node."""
    input_node = _make_nir_input()
    ir = _ir_for_names(["inp"])
    nir_graph = _nir_graph_stub({"inp": input_node})

    projection = _project_to_canvas(ir, [], nir_graph=nir_graph)

    node_dict = projection.nodes[0]
    assert "nir_type" in node_dict
    assert node_dict["nir_type"] == f"nir.{type(input_node).__name__}"
    assert node_dict["nir_type"] == "nir.Input"


def test_nir_type_emitted_for_output_node() -> None:
    """_project_to_canvas emits nir_type='nir.Output' for an nir.Output node."""
    output_node = _make_nir_output()
    ir = _ir_for_names(["out"])
    nir_graph = _nir_graph_stub({"out": output_node})

    projection = _project_to_canvas(ir, [], nir_graph=nir_graph)

    node_dict = projection.nodes[0]
    assert "nir_type" in node_dict
    assert node_dict["nir_type"] == f"nir.{type(output_node).__name__}"
    assert node_dict["nir_type"] == "nir.Output"


def test_nir_type_emitted_for_cuba_lif_node() -> None:
    """_project_to_canvas emits nir_type='nir.CubaLIF' for an nir.CubaLIF node."""
    cuba_node = _make_nir_cuba_lif()
    ir = _ir_for_names(["cuba_pop"])
    nir_graph = _nir_graph_stub({"cuba_pop": cuba_node})

    projection = _project_to_canvas(ir, [], nir_graph=nir_graph)

    node_dict = projection.nodes[0]
    assert "nir_type" in node_dict
    assert node_dict["nir_type"] == f"nir.{type(cuba_node).__name__}"
    assert node_dict["nir_type"] == "nir.CubaLIF"


def test_nir_type_matches_class_name_for_all_known_types() -> None:
    """nir_type value equals f'nir.{type(node).__name__}' for each known NIR class."""
    nodes: dict[str, _nir.NIRNode] = {
        "lif": _make_nir_lif(),
        "inp": _make_nir_input(),
        "out": _make_nir_output(),
        "cuba": _make_nir_cuba_lif(),
    }
    ir = _ir_for_names(list(nodes.keys()))
    nir_graph = _nir_graph_stub(nodes)

    projection = _project_to_canvas(ir, [], nir_graph=nir_graph)

    assert len(projection.nodes) == 4
    result_by_id = {n["id"]: n for n in projection.nodes}

    for name, nir_node in nodes.items():
        expected_nir_type = f"nir.{type(nir_node).__name__}"
        assert result_by_id[name]["nir_type"] == expected_nir_type, (
            f"Node '{name}': expected nir_type={expected_nir_type!r}, "
            f"got {result_by_id[name]['nir_type']!r}"
        )


# ---------------------------------------------------------------------------
# Tests — cnl.-namespaced node types (regression: top-level nir_type must
# match the canonical "cnl.<ClassName>" value, not a naive "nir." guess)
# ---------------------------------------------------------------------------


def test_nir_type_is_cnl_namespaced_for_synaptic_node() -> None:
    """_project_to_canvas emits nir_type='cnl.Synaptic', not 'nir.Synaptic'."""
    synaptic_node = Synaptic(n_neurons=5, alpha=0.9, beta=0.8, threshold=1.0)
    ir = _ir_for_names(["pop_synaptic"])
    nir_graph = _nir_graph_stub({"pop_synaptic": synaptic_node})

    projection = _project_to_canvas(ir, [], nir_graph=nir_graph)

    node_dict = projection.nodes[0]
    assert node_dict["nir_type"] == "cnl.Synaptic", (
        f"Expected the canonical 'cnl.Synaptic' type string, got "
        f"{node_dict['nir_type']!r} — this is the exact field the canvas "
        "renderer's port-position lookup uses; a wrong value here silently "
        "drops the node's ports and any edges touching it from the canvas."
    )
    # The nested fields were already correct before this fix — confirm the
    # top-level field is now consistent with them, not just independently
    # correct.
    assert node_dict["parameters"]["nir_type"] == "cnl.Synaptic"
    assert node_dict["nir_type"] == node_dict["parameters"]["nir_type"]


def test_nir_type_is_cnl_namespaced_for_rsynaptic_node() -> None:
    """_project_to_canvas emits nir_type='cnl.RSynaptic', not 'nir.RSynaptic'."""
    rsynaptic_node = RSynaptic(n_neurons=7, alpha=0.9, beta=0.8, threshold=1.0)
    ir = _ir_for_names(["pop_rsynaptic"])
    nir_graph = _nir_graph_stub({"pop_rsynaptic": rsynaptic_node})

    projection = _project_to_canvas(ir, [], nir_graph=nir_graph)

    node_dict = projection.nodes[0]
    assert node_dict["nir_type"] == "cnl.RSynaptic", (
        f"Expected the canonical 'cnl.RSynaptic' type string, got {node_dict['nir_type']!r}."
    )
    assert node_dict["parameters"]["nir_type"] == "cnl.RSynaptic"
    assert node_dict["nir_type"] == node_dict["parameters"]["nir_type"]


# ---------------------------------------------------------------------------
# Tests — nir_graph is None
# ---------------------------------------------------------------------------


def test_nir_type_is_none_when_nir_graph_is_none() -> None:
    """_project_to_canvas emits nir_type=None for every node when nir_graph=None."""
    ir = _ir_for_names(["pop_a", "pop_b"])

    projection = _project_to_canvas(ir, [], nir_graph=None)

    assert len(projection.nodes) == 2
    for node_dict in projection.nodes:
        assert "nir_type" in node_dict, (
            f"Node {node_dict.get('id')!r} is missing the 'nir_type' key"
        )
        assert node_dict["nir_type"] is None, (
            f"Node {node_dict.get('id')!r}: expected nir_type=None, got {node_dict['nir_type']!r}"
        )


def test_nir_type_key_always_present_in_node_dict() -> None:
    """Every node dict returned by _project_to_canvas always contains the key 'nir_type'.

    This is a guard against accidental key omission whether or not nir_graph is
    provided.
    """
    lif_node = _make_nir_lif()
    ir = _ir_for_names(["n1"])

    # With nir_graph
    proj_with = _project_to_canvas(ir, [], nir_graph=_nir_graph_stub({"n1": lif_node}))
    assert "nir_type" in proj_with.nodes[0]

    # Without nir_graph
    proj_without = _project_to_canvas(ir, [], nir_graph=None)
    assert "nir_type" in proj_without.nodes[0]
    assert proj_without.nodes[0]["nir_type"] is None
