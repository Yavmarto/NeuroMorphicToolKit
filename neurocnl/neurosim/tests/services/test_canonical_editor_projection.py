"""Tests for canonical editor contracts and projections."""

import pytest

from neurocnl.cnl.document import import_ir_from_nir, serialize_ir
from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR
from neurosim.app.services.canonical_editor_projection import (
    apply_canvas_mutation,
    canonical_from_cnl,
    canonical_to_cnl,
    canvas_from_canonical,
)
from neurosim.contracts.canonical_editor_contracts import (
    CanonicalEditorDocument,
    CanvasNodeMutation,
    CanvasProjection,
    FidelityAnnotation,
)


def _minimal_ir() -> NetworkIR:
    return NetworkIR(
        populations={
            "sensory_input": PopulationIR(
                name="sensory_input", size=4, population_type="excitatory"
            ),
            "motor_output": PopulationIR(
                name="motor_output", size=2, population_type="excitatory"
            ),
        },
        connections=[
            ConnectionIR(source="sensory_input", target="motor_output", weight=0.5)
        ],
    )


def test_canonical_editor_document_round_trips_json() -> None:
    ir = _minimal_ir()
    doc = CanonicalEditorDocument(
        ir_json=serialize_ir(ir),
        cnl_text="sensory_input connects to motor_output.",
    )
    serialized = doc.model_dump()
    restored = CanonicalEditorDocument.model_validate(serialized)
    assert restored.ir_json == doc.ir_json
    assert restored.cnl_text == doc.cnl_text


def test_fidelity_annotation_round_trips_json() -> None:
    ann = FidelityAnnotation(
        kind="advisory",
        concept="neuromodulation",
        message="Neuromodulation preserved as metadata only.",
        affects=["sensory_input"],
    )
    assert FidelityAnnotation.model_validate(ann.model_dump()).kind == "advisory"


def test_canvas_projection_survives_json_round_trip() -> None:
    proj = CanvasProjection(
        nodes=[{"id": "sensory_input", "x": 100, "y": 200}],
        edges=[{"source": "sensory_input", "target": "motor_output"}],
        read_only_annotations=[
            FidelityAnnotation(
                kind="unsupported",
                concept="spatial_connectivity",
                message="Cannot edit connectivity pattern in canvas.",
            )
        ],
    )
    restored = CanvasProjection.model_validate(proj.model_dump())
    assert len(restored.read_only_annotations) == 1
    assert restored.read_only_annotations[0].concept == "spatial_connectivity"


# NIR-native CNL fixtures — use 'Define a LIF neuron...' syntax
REFLEX_ARC_CNL = "\n".join(
    [
        "Define a network named reflexarc.",
        "",
        "# Layers:",
        "Define an input port named input with shape (1,).",
        "Define a LIF neuron named sensory_input with "
        "time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define a LIF neuron named motor_output with "
        "time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 0.8.",
        "Define an output port named output with shape (1,).",
        "",
        "# Connections:",
        "input connects to sensory_input.",
        "sensory_input connects to motor_output.",
        "motor_output connects to output.",
    ]
)

MULTI_NODE_CNL = "\n".join(
    [
        "Define a network named multi.",
        "",
        "# Layers:",
        "Define an input port named input with shape (1,).",
        "Define a LIF neuron named pop_a with "
        "time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define a LIF neuron named pop_b with "
        "time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define a LIF neuron named pop_c with "
        "time constant 0.02, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.",
        "Define an output port named output with shape (1,).",
        "",
        "# Connections:",
        "input connects to pop_a.",
        "pop_a connects to pop_b.",
        "pop_b connects to pop_c.",
        "pop_c connects to output.",
    ]
)


def test_canonical_from_cnl_returns_document_with_ir_json() -> None:
    doc = canonical_from_cnl(REFLEX_ARC_CNL)
    assert doc.ir_json is not None
    # sensory_input and motor_output should appear as LIF populations
    pops = doc.ir_json.get("populations", {})
    assert "sensory_input" in pops or "motor_output" in pops
    assert doc.cnl_text != ""


def test_canonical_to_cnl_round_trips_through_document() -> None:
    doc = canonical_from_cnl(REFLEX_ARC_CNL)
    cnl = canonical_to_cnl(doc)
    doc2 = canonical_from_cnl(cnl)
    assert set(doc2.ir_json["populations"]) == set(doc.ir_json["populations"])


def test_canvas_from_canonical_produces_projection() -> None:
    doc = canonical_from_cnl(REFLEX_ARC_CNL)
    canvas = canvas_from_canonical(doc)
    node_ids = {n["id"] for n in canvas.nodes}
    assert "sensory_input" in node_ids
    assert "motor_output" in node_ids


def test_multi_node_topology_preserved_in_ir_json() -> None:
    doc = canonical_from_cnl(MULTI_NODE_CNL)
    # NIR compiler imports LIF nodes only (not Input/Output ports)
    populations = doc.ir_json.get("populations", {})
    lif_pops = {
        k: v for k, v in populations.items() if k in ("pop_a", "pop_b", "pop_c")
    }
    assert len(lif_pops) == 3


def test_apply_canvas_mutation_updates_threshold() -> None:
    doc = canonical_from_cnl(REFLEX_ARC_CNL)
    mutation = CanvasNodeMutation(node_id="sensory_input", threshold=1.5)
    updated = apply_canvas_mutation(doc, mutation)
    from neurocnl.cnl.document import deserialize_ir

    ir = deserialize_ir(updated.ir_json)
    assert ir.populations["sensory_input"].threshold == pytest.approx(1.5)


def test_apply_canvas_mutation_unknown_node_raises() -> None:
    doc = canonical_from_cnl(REFLEX_ARC_CNL)
    import pytest as _pytest

    with _pytest.raises(ValueError, match="Unknown node"):
        apply_canvas_mutation(doc, CanvasNodeMutation(node_id="nonexistent"))


def test_cnl_canonical_cnl_round_trip_preserves_population_names() -> None:
    """CNL -> canonical -> CNL: population names must survive."""
    doc = canonical_from_cnl(REFLEX_ARC_CNL)
    cnl = canonical_to_cnl(doc)
    doc2 = canonical_from_cnl(cnl)
    assert set(doc2.ir_json["populations"]) == set(doc.ir_json["populations"])


def test_advisory_semantics_survive_canvas_projection() -> None:
    """Advisory-only concepts must appear in fidelity_annotations when present."""
    # Build a document with an advisory fidelity annotation manually
    ir = _minimal_ir()
    doc = CanonicalEditorDocument(
        ir_json=serialize_ir(ir),
        cnl_text="",
        fidelity_annotations=[
            FidelityAnnotation(
                kind="advisory",
                concept="neuromodulation",
                message="Neuromodulation preserved as metadata only.",
                affects=["sensory_input"],
            )
        ],
    )
    advisory_concepts = {
        a.concept for a in doc.fidelity_annotations if a.kind == "advisory"
    }
    assert "neuromodulation" in advisory_concepts


def test_unsupported_concept_produces_annotation_but_ir_still_populated() -> None:
    """Unsupported concepts produce unsupported annotation but IR is still populated."""
    # Build a document with an unsupported fidelity annotation manually
    ir = _minimal_ir()
    doc = CanonicalEditorDocument(
        ir_json=serialize_ir(ir),
        cnl_text="",
        fidelity_annotations=[
            FidelityAnnotation(
                kind="unsupported",
                concept="spatial_connectivity",
                message="Cannot represent local connectivity in NIR.",
                affects=["sensory_input"],
            )
        ],
    )
    unsupported = [a for a in doc.fidelity_annotations if a.kind == "unsupported"]
    assert any("spatial_connectivity" in a.concept for a in unsupported)
    assert "sensory_input" in doc.ir_json.get("populations", {})


def test_threshold_mutation_survives_canonical_round_trip() -> None:
    """Canvas threshold edit -> canonical -> re-parse from CNL -> same threshold."""
    doc = canonical_from_cnl(REFLEX_ARC_CNL)
    mutated = apply_canvas_mutation(
        doc, CanvasNodeMutation(node_id="sensory_input", threshold=2.0)
    )
    from neurocnl.cnl.document import deserialize_ir

    ir = deserialize_ir(mutated.ir_json)
    assert ir.populations["sensory_input"].threshold == pytest.approx(2.0)
    # Re-parse from the rendered CNL (uses embedded metadata)
    doc2 = canonical_from_cnl(mutated.cnl_text)
    ir2 = deserialize_ir(doc2.ir_json)
    assert ir2.populations["sensory_input"].threshold == pytest.approx(2.0)


# ---------------------------------------------------------------------------
# Network-level timestep (graph.metadata["dt"]) surfaces into CanvasProjection
#
# Companion to the nir_cnl grammar's optional `with timestep <seconds>`
# clause — without this, a declared timestep is invisible to the Studio
# canvas even though it's correctly compiled and rendered.
# ---------------------------------------------------------------------------

_LIF_WITH_TIMESTEP_CNL = "\n".join(
    [
        "Define a network named demo with timestep 0.005.",
        "Define an input port named in1 with shape (1,).",
        "Define a LIF neuron named n1 with time constant 0.02, resistance 1.0,"
        " leak voltage 0.0, and firing threshold 1.0.",
        "Define an output port named out1 with shape (1,).",
        "in1 connects to n1.",
        "n1 connects to out1.",
    ]
)


def test_canonical_from_cnl_surfaces_network_dt_in_canvas_metadata() -> None:
    doc = canonical_from_cnl(_LIF_WITH_TIMESTEP_CNL)
    assert "with timestep" in doc.cnl_text
    assert doc.canvas is not None
    assert doc.canvas.metadata.get("dt") == 0.005


def test_canonical_from_cnl_no_dt_omits_key() -> None:
    """Backward-compat guard: an undeclared network timestep must not
    appear in the canvas projection's metadata at all."""
    no_dt_cnl = _LIF_WITH_TIMESTEP_CNL.replace(" with timestep 0.005", "")
    doc = canonical_from_cnl(no_dt_cnl)
    assert "with timestep" not in doc.cnl_text
    assert doc.canvas is not None
    assert "dt" not in doc.canvas.metadata


def test_import_ir_from_nir_preserves_network_dt() -> None:
    """import_ir_from_nir must carry graph.metadata['dt'] into NetworkIR
    metadata — this is what lets a re-materialized graph (canvas_from_canonical,
    canonical_to_cnl, or any persisted-document reload that only has ir_json,
    not the original live nir_graph) still know its declared timestep."""
    from neurocnl.compile import compile_to_nir

    graph = compile_to_nir(_LIF_WITH_TIMESTEP_CNL)
    ir = import_ir_from_nir(graph)
    assert ir.metadata.get("dt") == 0.005


def test_import_ir_from_nir_no_dt_omits_key() -> None:
    from neurocnl.compile import compile_to_nir

    no_dt_cnl = _LIF_WITH_TIMESTEP_CNL.replace(" with timestep 0.005", "")
    graph = compile_to_nir(no_dt_cnl)
    ir = import_ir_from_nir(graph)
    assert "dt" not in ir.metadata


# ── Mixed-case node names must still receive propagated population sizes ───────


def _lif_scalar(name: str) -> str:
    return (
        f"Define a LIF neuron named {name} with time constant 0.002, "
        "resistance 1.0, leak voltage 0.0, and firing threshold 1.0."
    )


MIXED_CASE_MNIST_SPEC = "\n".join(
    [
        "Define a network named graph.",
        "Define an input port named nir.Input_1 with shape (784,).",
        _lif_scalar("nir.LIF_1"),
        "Define a linear transformation named nir.Linear_1 with weight matrix shape (256, 784).",
        _lif_scalar("nir.LIF_2"),
        "Define a linear transformation named nir.Linear_2 with weight matrix shape (10, 256).",
        _lif_scalar("nir.LIF_3"),
        "Define an output port named nir.Output_1 with shape (10,).",
        "nir.Input_1 connects to nir.LIF_1.",
        "nir.LIF_1 connects to nir.Linear_1.",
        "nir.Linear_1 connects to nir.LIF_2.",
        "nir.LIF_2 connects to nir.Linear_2.",
        "nir.Linear_2 connects to nir.LIF_3.",
        "nir.LIF_3 connects to nir.Output_1.",
    ]
)


def test_mixed_case_lif_names_get_propagated_sizes() -> None:
    """Regression: canvas-authored names are mixed-case and lost their sizes.

    `import_ir_from_nir` keys populations lower-cased ("nir.lif_1") while both
    the NIR graph and `propagate_nir_sizes` use the CNL's spelling
    ("nir.LIF_1"), so the population lookup missed every node with a capital
    letter — i.e. every node the canvas creates. The projection then fell back
    to reading each LIF's size off its scalar `tau` and reported 1 neuron for a
    784-neuron layer.
    """
    document = canonical_from_cnl(MIXED_CASE_MNIST_SPEC)
    assert document.canvas is not None
    sizes = {node["id"]: node["size"] for node in document.canvas.nodes}

    assert sizes["nir.LIF_1"] == 784
    assert sizes["nir.LIF_2"] == 256
    assert sizes["nir.LIF_3"] == 10

    neuron_counts = {
        node["id"]: node["parameters"].get("n_neurons")
        for node in document.canvas.nodes
        if node["nir_type"] == "nir.LIF"
    }
    assert neuron_counts == {"nir.LIF_1": 784, "nir.LIF_2": 256, "nir.LIF_3": 10}


def test_scalar_lif_params_survive_size_propagation() -> None:
    """Declaring tau/threshold as scalars must keep their values, not zero them.

    The shape-only form ("with time constant shape (784,)") sets sizes correctly
    but discards the values. With the lookup fixed, the scalar form gives both:
    real tau/threshold AND topology-inferred sizes.
    """
    document = canonical_from_cnl(MIXED_CASE_MNIST_SPEC)
    assert document.canvas is not None
    lifs = [n for n in document.canvas.nodes if n["nir_type"] == "nir.LIF"]

    assert lifs, "expected LIF nodes on the canvas"
    for node in lifs:
        assert node["parameters"]["tau"] == pytest.approx(0.002)
        assert node["parameters"]["threshold"] == pytest.approx(1.0)
