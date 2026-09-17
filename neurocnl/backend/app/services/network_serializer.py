"""Serialise a ``nengo.Network`` into a JSON-safe graph structure."""

from __future__ import annotations

from typing import Any

import nengo
import numpy as np


def _infer_subtype(label: str) -> str:
    """Infer a node subtype from its label for richer frontend rendering."""
    label_lower = label.lower()
    if "error" in label_lower:
        return "input_error"
    if "stimulus" in label_lower or "input" in label_lower:
        return "input_stimulus"
    if "sensory" in label_lower:
        return "sensory"
    if "motor" in label_lower:
        return "motor"
    if "intern" in label_lower:
        return "interneuron"
    return "generic"


def _size_class(n_neurons: int) -> str:
    if n_neurons < 50:
        return "small"
    if n_neurons <= 100:
        return "medium"
    return "large"


def _distribution_bounds(distribution: object) -> tuple[float, float] | None:
    """Return ``(low, high)`` for simple distribution objects when available."""
    low = getattr(distribution, "low", None)
    high = getattr(distribution, "high", None)
    if low is None or high is None:
        return None
    try:
        return (float(low), float(high))
    except (TypeError, ValueError):
        return None


def _serialize_transform(transform: object) -> float | list[list[float]] | None:
    """Convert a Nengo transform init payload into a JSON-safe form."""
    init = getattr(transform, "init", None)
    if init is None:
        return None
    try:
        return float(init)
    except (TypeError, ValueError):
        array = np.asarray(init, dtype=float)
        if array.ndim == 0:
            return float(array)
        return list(array.tolist())


def _endpoint_selector(obj: object) -> str:
    """Describe whether a connection endpoint targets an ensemble, neurons, or a rule."""
    if hasattr(obj, "connection"):
        return "learning_rule"
    if hasattr(obj, "ensemble"):
        return "neurons"
    return "ensemble"


def serialize_network(network: nengo.Network) -> dict[str, Any]:
    """Convert *network* into ``{nodes: [...], edges: [...]}``."""
    nodes: list[dict[str, Any]] = []
    edges: list[dict[str, Any]] = []
    export_population_metadata = getattr(network, "export_population_metadata", {})
    export_connection_metadata = getattr(network, "export_connection_metadata", {})

    x_step = 200
    x = 0

    # Input nodes
    for node in network.nodes:
        label = node.label or "input"
        subtype = _infer_subtype(label)
        nodes.append(
            {
                "id": label,
                "type": "input_node",
                "subtype": subtype,
                "label": label,
                "params": {},
                "position": {"x": x, "y": 200},
            }
        )
        x += x_step

    # Ensembles
    for ens in network.ensembles:
        label = ens.label or "ensemble"
        subtype = _infer_subtype(label)
        n_neurons = ens.n_neurons
        params: dict[str, Any] = {
            "n_neurons": n_neurons,
            "dimensions": ens.dimensions,
            "neuron_type": type(ens.neuron_type).__name__,
            "size_class": _size_class(n_neurons),
        }
        if hasattr(ens.neuron_type, "tau_rc"):
            params["tau_rc"] = float(ens.neuron_type.tau_rc)
        if hasattr(ens.neuron_type, "tau_ref"):
            params["tau_ref"] = float(ens.neuron_type.tau_ref)
        if hasattr(ens.neuron_type, "tau_n"):
            params["tau_n"] = float(ens.neuron_type.tau_n)
        if ens.radius != 1.0:
            params["radius"] = float(ens.radius)
        intercept_bounds = _distribution_bounds(ens.intercepts)
        if intercept_bounds is not None:
            params["intercepts_low"], params["intercepts_high"] = intercept_bounds
        max_rate_bounds = _distribution_bounds(ens.max_rates)
        if max_rate_bounds is not None:
            params["max_rates_low"], params["max_rates_high"] = max_rate_bounds
        export_metadata = export_population_metadata.get(label)
        if isinstance(export_metadata, dict):
            threshold = export_metadata.get("threshold")
            if threshold is not None:
                params["threshold"] = float(threshold)

        nodes.append(
            {
                "id": label,
                "type": "ensemble",
                "subtype": subtype,
                "label": label,
                "params": params,
                "position": {"x": x, "y": 200},
            }
        )
        x += x_step

    # Connections → edges
    for conn in network.connections:
        pre_label = _obj_label(conn.pre)
        post_label = _obj_label(conn.post)

        transform_payload = _serialize_transform(getattr(conn, "transform", None))
        weight = transform_payload if isinstance(transform_payload, float) else None

        is_inhibitory = weight is not None and weight < 0
        has_learning_rule = conn.learning_rule_type is not None
        learning_rule_name = (
            type(conn.learning_rule_type).__name__ if has_learning_rule else None
        )

        synapse_tau = None
        if hasattr(conn, "synapse") and conn.synapse is not None:
            synapse_tau = getattr(conn.synapse, "tau", None)
            if synapse_tau is not None:
                synapse_tau = float(synapse_tau)

        has_delay = synapse_tau is not None and synapse_tau >= 0.001

        learning_rate = None
        if has_learning_rule and hasattr(conn.learning_rule_type, "learning_rate"):
            try:
                learning_rate = float(conn.learning_rule_type.learning_rate)
            except (TypeError, ValueError):
                pass

        edge: dict[str, Any] = {
            "id": f"{pre_label}_to_{post_label}",
            "source": pre_label,
            "target": post_label,
            "is_inhibitory": is_inhibitory,
            "has_learning_rule": has_learning_rule,
            "learning_rule": learning_rule_name,
            "learning_rate": learning_rate,
            "has_delay": has_delay,
            "params": {},
        }
        if transform_payload is not None:
            edge["params"]["transform"] = transform_payload
        if synapse_tau is not None:
            edge["params"]["synapse"] = synapse_tau
        export_metadata = export_connection_metadata.get((pre_label, post_label), {})
        edge["params"]["source_selector"] = export_metadata.get(
            "source_selector", _endpoint_selector(conn.pre)
        )
        edge["params"]["target_selector"] = export_metadata.get(
            "target_selector", _endpoint_selector(conn.post)
        )
        if has_learning_rule:
            edge["params"]["learning_rule"] = learning_rule_name
        if isinstance(export_metadata, dict) and "targeted" in export_metadata:
            edge["params"]["learning_rule_targeted"] = bool(
                export_metadata.get("targeted")
            )

        edges.append(edge)

    return {"nodes": nodes, "edges": edges}


def _obj_label(obj: object) -> str:
    """Return a label for a Nengo object (Ensemble, Node, Neurons, …)."""
    if hasattr(obj, "connection"):
        conn = obj.connection
        pre_label = _obj_label(conn.pre)
        post_label = _obj_label(conn.post)
        return f"{pre_label}_to_{post_label}_learning_rule"
    if hasattr(obj, "label") and obj.label:
        return str(obj.label)
    if hasattr(obj, "ensemble"):
        ens = obj.ensemble
        return getattr(ens, "label", None) or str(id(ens))
    return str(id(obj))
