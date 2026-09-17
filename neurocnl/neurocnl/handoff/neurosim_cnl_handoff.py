"""Build NeuroSim-compatible canonical import payloads."""

from __future__ import annotations

from neurocnl.cnl.types import ParsedSentence
from neurocnl.pipeline import default_params_from_specs, parse_spec_text
from neurocnl.utils import extract_numeric


class NeurosimHandoffRejectedError(ValueError):
    """Raised when a NeuroCNL spec cannot be handed off to NeuroSim."""

    def __init__(self, message: str, *, status_code: int = 422) -> None:
        super().__init__(message)
        self.status_code = status_code


def _build_neurosim_graph_contract(
    *,
    cnl_spec: str,
    sensory_n_neurons: int,
    motor_n_neurons: int,
    sensory_tau_rc: float,
    motor_tau_rc: float,
    sensory_tau_ref: float,
    motor_tau_ref: float,
    sensory_threshold: float,
    motor_threshold: float,
    weight: float,
    delay: float,
) -> dict[str, object]:
    return {
        "payload_type": "neurocnl_import_contract",
        "payload_version": "2026-04-29",
        "source_module": "neurocnl",
        "semantics_mode": "canonical_import",
        "cnl_spec": cnl_spec,
        "graph": {
            "nodes": [
                {
                    "id": "sensory",
                    "component_id": "lif_population",
                    "parameters": {
                        "name": "sensory",
                        "n_neurons": sensory_n_neurons,
                        "tau_rc": sensory_tau_rc,
                        "tau_ref": sensory_tau_ref,
                        "threshold": sensory_threshold,
                    },
                    "position": [100.0, 200.0],
                    "width": 150.0,
                    "height": 132.0,
                    "is_visible": True,
                },
                {
                    "id": "motor",
                    "component_id": "lif_population",
                    "parameters": {
                        "name": "motor",
                        "n_neurons": motor_n_neurons,
                        "tau_rc": motor_tau_rc,
                        "tau_ref": motor_tau_ref,
                        "threshold": motor_threshold,
                    },
                    "position": [400.0, 200.0],
                    "width": 150.0,
                    "height": 132.0,
                    "is_visible": True,
                },
            ],
            "edges": [
                {
                    "id": "edge_0",
                    "source_node_id": "sensory",
                    "source_port": "out",
                    "target_node_id": "motor",
                    "target_port": "in",
                    "parameters": {
                        "synapse_type": "static_synapse",
                        "weight": weight,
                        "delay": delay,
                    },
                },
            ],
            "metadata": {"zoom": 1.0, "pan": [0.0, 0.0]},
        },
        "warnings": [],
    }


_NIR_NEURON_PRIMITIVES = frozenset({"LIF", "CubaLIF", "LI", "CubaLI", "IF", "I"})
_NIR_ALL_CONCEPTS = frozenset(
    {
        "Input",
        "Output",
        "LIF",
        "CubaLIF",
        "LI",
        "CubaLI",
        "IF",
        "I",
        "Linear",
        "Affine",
        "Scale",
        "Conv1d",
        "Conv2d",
        "AvgPool2d",
        "SumPool2d",
        "Flatten",
        "Delay",
        "Threshold",
        "Connect",
    }
)


def _build_neurosim_handoff_from_nir(spec_text: str) -> dict[str, object]:
    """Build a NeuroSim handoff payload from a NIR-native spec."""
    from neurocnl.compile import CompileError, compile_to_nir
    from neurocnl.nir_cnl.ir_types import NIREdgeRecord, NIRNodeRecord
    from neurocnl.nir_cnl.parser import NIR_CNL_Parser

    try:
        compile_to_nir(spec_text)
    except CompileError as exc:
        raise NeurosimHandoffRejectedError(
            f"failed to parse NIR-native spec: {exc}", status_code=400
        ) from exc

    # Extract structural records for the graph contract.
    records = NIR_CNL_Parser().parse(spec_text)
    node_records = [r for r in records if isinstance(r, NIRNodeRecord)]
    edge_records = [r for r in records if isinstance(r, NIREdgeRecord)]

    neuron_nodes = [r for r in node_records if r.primitive in _NIR_NEURON_PRIMITIVES]
    neuron_names: set[str] = {r.name for r in neuron_nodes}

    # Build NeuroSim node entries (one per neuron primitive).
    graph_nodes = [
        {
            "id": r.name,
            "component_id": "lif_population",
            "parameters": {
                "name": r.name,
                "primitive": r.primitive,
                **{
                    k: (v if not hasattr(v, "shape") else list(v.shape))
                    for k, v in r.params.items()
                },
            },
            "position": [100.0 + i * 300.0, 200.0],
            "width": 150.0,
            "height": 132.0,
            "is_visible": True,
        }
        for i, r in enumerate(neuron_nodes)
    ]

    # Build NeuroSim edge entries (edges between neurons, skipping weight nodes).
    graph_edges = []
    for i, e in enumerate(edge_records):
        if e.src in neuron_names and e.target in neuron_names:
            graph_edges.append(
                {
                    "id": f"edge_{i}",
                    "source_node_id": e.src,
                    "source_port": "out",
                    "target_node_id": e.target,
                    "target_port": "in",
                    "parameters": {
                        "synapse_type": "static_synapse",
                        "weight": 1.0,
                        "delay": 0.001,
                    },
                }
            )

    semantic_lines = [
        line.strip()
        for line in spec_text.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    cnl_spec = "\n".join(semantic_lines)

    return {
        "payload_type": "neurocnl_import_contract",
        "payload_version": "2026-04-29",
        "source_module": "neurocnl",
        "semantics_mode": "canonical_import",
        "cnl_spec": cnl_spec,
        "graph": {
            "nodes": graph_nodes,
            "edges": graph_edges,
            "metadata": {"zoom": 1.0, "pan": [0.0, 0.0]},
        },
        "warnings": [],
    }


def build_neurosim_handoff_spec(spec_text: str) -> dict[str, object]:
    """Normalize NeuroCNL text into a canonical NeuroSim import contract.

    The handoff exposes the graph semantics explicitly so NeuroSim no longer has
    to treat local CNL parsing as a peer semantic authority.
    """
    parse_results = parse_spec_text(spec_text)
    parse_errors = [
        result["error"] or "unknown parse error"
        for result in parse_results
        if not result["valid"]
    ]
    if parse_errors:
        raise NeurosimHandoffRejectedError(
            "Some CNL sentences failed to parse: " + "; ".join(parse_errors),
            status_code=400,
        )

    parsed_specs: list[ParsedSentence] = [
        result["parsed"]
        for result in parse_results
        if result["valid"] and result["parsed"] is not None
    ]

    # NIR-native specs: route to the NIR-aware handoff builder.
    if parsed_specs and any(p["concept"] in _NIR_ALL_CONCEPTS for p in parsed_specs):
        return _build_neurosim_handoff_from_nir(spec_text)

    if not parsed_specs:
        raise NeurosimHandoffRejectedError("No valid CNL sentences found.")

    sensory_threshold = 1.0
    motor_threshold = 1.0
    sensory_tau_rc = 0.02
    motor_tau_rc = 0.02
    sensory_tau_ref = 0.002
    motor_tau_ref = 0.002
    sensory_n_neurons = 50
    motor_n_neurons = 50
    weight = 1.0
    delay = 0.001
    for spec in parsed_specs:
        condition = spec.get("condition")
        value = extract_numeric(condition)
        subject = str(spec.get("subject", "")).lower()
        concept = spec.get("concept")
        if concept == "threshold_firing":
            if value is None:
                continue
            if "sensory neuron" in subject:
                sensory_threshold = float(value)
            elif "motor neuron" in subject:
                motor_threshold = float(value)
        elif concept == "membrane_potential_decay":
            if value is None:
                continue
            if "sensory neuron" in subject:
                sensory_tau_rc = float(value)
            elif "motor neuron" in subject:
                motor_tau_rc = float(value)
        elif concept == "refractory_period":
            if value is None:
                continue
            if "sensory neuron" in subject:
                sensory_tau_ref = float(value)
            elif "motor neuron" in subject:
                motor_tau_ref = float(value)
        elif concept == "population_coding":
            if value is None:
                continue
            if "sensory population" in subject:
                sensory_n_neurons = int(value)
            elif "motor population" in subject or "motor ensemble" in subject:
                motor_n_neurons = int(value)
        elif concept == "synaptic_weight" and value is not None:
            weight = float(value)
        elif concept == "axonal_delay" and value is not None:
            delay = float(value)

    default_params_from_specs(parsed_specs)

    semantic_lines = [
        line.strip()
        for line in spec_text.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]

    cnl_spec = "\n".join(semantic_lines)
    return _build_neurosim_graph_contract(
        cnl_spec=cnl_spec,
        sensory_n_neurons=sensory_n_neurons,
        motor_n_neurons=motor_n_neurons,
        sensory_tau_rc=sensory_tau_rc,
        motor_tau_rc=motor_tau_rc,
        sensory_tau_ref=sensory_tau_ref,
        motor_tau_ref=motor_tau_ref,
        sensory_threshold=sensory_threshold,
        motor_threshold=motor_threshold,
        weight=weight,
        delay=delay,
    )
