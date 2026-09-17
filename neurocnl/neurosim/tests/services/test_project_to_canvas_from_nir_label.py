"""Regression test for node label resolution in _project_to_canvas_from_nir.

serialize_nir_to_canvas_graph() (backend/app/services/nir_graph_serializer.py)
already resolves a friendly node label via
``metadata.get("ir_name") or metadata.get("label") or <raw NIR graph key>``.
_project_to_canvas_from_nir captured that serialized node's ``parameters``
and ``metadata`` but discarded its ``label``, hardcoding the raw NIR graph
key instead — so any canvas fed from this path (which is effectively every
canvas projection, since _project_to_canvas delegates here whenever a
nir_graph is available) showed the raw internal node id instead of the
resolved name whenever one was available via metadata.
"""

from __future__ import annotations

from types import SimpleNamespace

import nir as _nir
import numpy as np

from neurocnl.ir.types import NetworkIR, PopulationIR
from neurosim.app.services.canonical_editor_projection import _project_to_canvas

_SHAPE = np.array([1.0])


def _nir_graph_stub(node_map: dict[str, _nir.NIRNode]) -> SimpleNamespace:
    """See test_project_to_canvas_nir_type.py for why a stub is used here."""
    return SimpleNamespace(nodes=node_map, edges=[])


def _ir_for_names(names: list[str]) -> NetworkIR:
    return NetworkIR(
        populations={
            name: PopulationIR(name=name, size=1, population_type="excitatory") for name in names
        },
        connections=[],
    )


def test_label_resolves_via_metadata_ir_name_not_raw_graph_key() -> None:
    """A node whose metadata carries ir_name must show that, not the raw id."""
    lif_node = _nir.LIF(
        tau=_SHAPE,
        r=_SHAPE,
        v_leak=_SHAPE,
        v_threshold=_SHAPE,
        metadata={"ir_name": "hidden_layer_1"},
    )
    # "n1" is the raw NIR graph dict key — the bug showed this instead of
    # the resolved "hidden_layer_1" name.
    ir = _ir_for_names(["n1"])
    nir_graph = _nir_graph_stub({"n1": lif_node})

    projection = _project_to_canvas(ir, [], nir_graph=nir_graph)

    node_dict = projection.nodes[0]
    assert node_dict["label"] == "hidden_layer_1", (
        f"Expected the metadata-resolved name 'hidden_layer_1', got "
        f"{node_dict['label']!r} — the raw NIR graph key 'n1' means the "
        "label resolution computed by serialize_nir_to_canvas_graph() was "
        "discarded."
    )


def test_label_falls_back_to_raw_graph_key_without_metadata() -> None:
    """No ir_name/label metadata: falling back to the raw key is still correct."""
    lif_node = _nir.LIF(tau=_SHAPE, r=_SHAPE, v_leak=_SHAPE, v_threshold=_SHAPE)
    ir = _ir_for_names(["n1"])
    nir_graph = _nir_graph_stub({"n1": lif_node})

    projection = _project_to_canvas(ir, [], nir_graph=nir_graph)

    assert projection.nodes[0]["label"] == "n1"


def test_label_resolves_for_node_not_in_ir_populations() -> None:
    """Same fix applies to the "node not in ir.populations" branch."""
    lif_node = _nir.LIF(
        tau=_SHAPE,
        r=_SHAPE,
        v_leak=_SHAPE,
        v_threshold=_SHAPE,
        metadata={"ir_name": "orphan_neuron"},
    )
    # Empty populations dict forces the "pop is None" branch.
    ir = NetworkIR(populations={}, connections=[])
    nir_graph = _nir_graph_stub({"n2": lif_node})

    projection = _project_to_canvas(ir, [], nir_graph=nir_graph)

    assert projection.nodes[0]["label"] == "orphan_neuron"
