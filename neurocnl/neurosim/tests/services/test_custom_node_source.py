"""Static source generation and validation coverage for custom nodes."""

from __future__ import annotations

import json
from pathlib import Path

from neurosim.app.services.custom_node_source import (
    analyze_custom_node_source,
    generate_custom_node_source,
    inject_stable_node_id,
    source_revision,
)
from neurosim.contracts.design_contracts import ComponentBlock, ParameterDef, PortDef


def _lif_component() -> ComponentBlock:
    return ComponentBlock(
        id="lif_population",
        name="LIF Population",
        category="Neurons",
        description="A LIF population.",
        icon="memory",
        parameters=[
            ParameterDef(
                name="tau_rc",
                label="Tau",
                description="Membrane time constant",
                type="float",
                default=0.02,
                min=0.001,
                unit="s",
            )
        ],
        ports=[
            PortDef(id="in", direction="input", label="Input"),
            PortDef(id="out", direction="output", label="Output"),
        ],
        cnl_template="",
    )


def test_generated_builtin_source_round_trips_through_static_contract() -> None:
    source = generate_custom_node_source(
        component=_lif_component(),
        component_id="lif_population",
        nir_type="nir.LIF",
        display_name="My LIF",
        category="neuron",
        parameters={"tau_rc": 0.03},
        parameter_definitions=[
            ParameterDef(
                name="tau_rc",
                label="Selected Tau",
                description="Selected NIR parameter",
                type="float",
                default=0.02,
            )
        ],
        ports=[
            PortDef(id="nir_in", direction="input", label="NIR input"),
            PortDef(id="nir_out", direction="output", label="NIR output"),
        ],
    )

    analysis = analyze_custom_node_source(
        source,
        known_component_ids={"lif_population"},
    )

    assert analysis.valid
    assert analysis.name == "My LIF"
    assert analysis.base_component_id is None
    assert analysis.base_nir_type == "nir.LIF"
    assert analysis.parameters[0].default == 0.03
    assert analysis.parameters[0].label == "Selected Tau"
    assert {port.id for port in analysis.ports} == {"nir_in", "nir_out"}


def test_every_nonempty_builtin_manifest_generates_valid_custom_source() -> None:
    component_root = Path(__file__).parents[2] / "components"
    manifests = []
    for path in component_root.rglob("*.json"):
        raw = path.read_text(encoding="utf-8")
        if raw.strip():
            manifests.append(ComponentBlock(**json.loads(raw)))
    known_ids = {component.id for component in manifests}

    for component in manifests:
        source = generate_custom_node_source(
            component=component,
            component_id=component.id,
            nir_type=None,
            display_name=component.name,
            category=component.category,
            parameters={},
            parameter_definitions=[],
            ports=[],
        )
        analysis = analyze_custom_node_source(
            source,
            known_component_ids=known_ids,
        )
        assert analysis.valid, (component.id, analysis.diagnostics)


def test_generated_pipeline_source_preserves_role_and_canvas_context() -> None:
    source = generate_custom_node_source(
        component=None,
        component_id="adamOptimiser",
        nir_type=None,
        pipeline_type="adamOptimiser",
        canvas_context="training",
        display_name="Adam Optimiser",
        category="optimiser",
        parameters={"lr": 0.002},
        parameter_definitions=[
            ParameterDef(
                name="lr",
                label="Learning Rate",
                description="",
                type="float",
                default=0.001,
            )
        ],
        ports=[PortDef(id="model", direction="input", label="Model")],
    )

    analysis = analyze_custom_node_source(source)

    assert analysis.valid
    assert analysis.base_pipeline_type == "adamOptimiser"
    assert analysis.canvases == ["training"]
    assert analysis.frameworks == ["snntorch_sim"]
    assert analysis.parameters[0].default == 0.002


def test_unknown_pipeline_base_is_rejected() -> None:
    source = """
from nmtk_sdk import CustomNode

class UnknownPipelineNode(CustomNode):
    name = "Unknown"
    category = "training"
    canvases = ["training"]
    frameworks = ["snntorch_sim"]
    base_pipeline_type = "notARealNode"
"""

    analysis = analyze_custom_node_source(source)

    assert not analysis.valid
    assert any(
        diagnostic.code == "invalid-base-pipeline-type"
        for diagnostic in analysis.diagnostics
    )


def test_syntax_diagnostic_preserves_line_and_column() -> None:
    analysis = analyze_custom_node_source("class Bad(CustomNode)\n    pass\n")

    assert not analysis.valid
    assert analysis.diagnostics[0].code == "python-syntax"
    assert analysis.diagnostics[0].line == 1
    assert analysis.diagnostics[0].column > 1


def test_dangerous_import_is_a_blocking_diagnostic() -> None:
    source = """
import subprocess
from nmtk_sdk import CustomNode

class Unsafe(CustomNode):
    name = "Unsafe"
    category = "neurons"
    canvases = ["model"]
    frameworks = ["nengo"]
    base_component_id = "lif_population"
"""
    analysis = analyze_custom_node_source(
        source,
        known_component_ids={"lif_population"},
    )

    assert not analysis.valid
    assert any(item.code == "unsafe-import" for item in analysis.diagnostics)


def test_injected_node_id_is_stable_across_display_metadata_edits() -> None:
    source = """
from nmtk_sdk import CustomNode

class Stable(CustomNode):
    name = "First Name"
    category = "neurons"
    canvases = ["model"]
    frameworks = ["nengo"]
    base_component_id = "lif_population"
"""
    first = inject_stable_node_id(source, "custom_stable_a1b2c3d4")
    renamed = first.replace('name = "First Name"', 'name = "Renamed"')
    second = inject_stable_node_id(renamed, "custom_stable_a1b2c3d4")

    analysis = analyze_custom_node_source(
        second,
        known_component_ids={"lif_population"},
    )
    assert analysis.valid
    assert analysis.name == "Renamed"
    assert analysis.node_id == "custom_stable_a1b2c3d4"
    assert source_revision(first) != source_revision(second)
