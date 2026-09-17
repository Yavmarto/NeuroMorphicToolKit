"""Lower parsed CNL sentences into a typed intermediate representation."""

from __future__ import annotations

import re

from neurocnl.cnl.types import ParsedSentence
from neurocnl.ir.condition_parsing import (
    condition_value,
    connection_endpoints,
    lower_matrix_native_weight,
    normalized_population_subject,
    parse_connectivity_mask,
    parse_population_shape,
    parse_receptor_dynamics,
    parse_short_term_plasticity,
    parse_weight_bounds,
    population_name,
    population_role,
    provenance_for,
    split_projection_targets,
    stdp_direction,
    stdp_kind,
)
from neurocnl.ir.ir_merge import LoweringError, merge_connection, merge_population
from neurocnl.ir.types import (
    AkidaBlockType,
    AkidaConnectionPropertyIR,
    AkidaHardwareIR,
    LearningRuleIR,
    NetworkIR,
    TimingDeclarationIR,
)
from neurocnl.utils import extract_numeric

__all__ = ["LoweringError", "SUPPORTED_CONCEPTS", "lower_to_ir"]

SUPPORTED_CONCEPTS = {
    "threshold_firing",
    "refractory_period",
    "membrane_potential_decay",
    "synaptic_weight",
    "axonal_delay",
    "stdp_learning",
    "inhibitory_connection",
    "population_coding",
    "population_coding_range",
    "network_topology",
    "timing_declaration",
    "adaptive_spiking",
    "receptor_dynamics",
    "background_noise",
    "spatial_connectivity",
    "lateral_inhibition",
    "homeostatic_plasticity",
    "neuromodulation",
    "short_term_plasticity",
    "akida_hardware",
    "akida_spatiotemporal",
}


def lower_to_ir(parsed_specs: list[ParsedSentence]) -> NetworkIR:
    """Lower parsed CNL sentences into a normalized intermediate representation."""
    network = NetworkIR()

    for spec in parsed_specs:
        concept = spec["concept"]
        if concept not in SUPPORTED_CONCEPTS:
            raise LoweringError(
                f"Lowering for concept {concept!r} is not implemented in this phase."
            )

        provenance = provenance_for(spec)

        if concept == "threshold_firing":
            merge_population(
                network,
                name=population_name(spec["subject"]),
                provenance=provenance,
                threshold=extract_numeric(spec.get("condition")),
                attributes={
                    "threshold_condition": spec.get("condition"),
                    "threshold_action": spec.get("action"),
                },
            )
        elif concept == "refractory_period":
            merge_population(
                network,
                name=population_name(spec["subject"]),
                provenance=provenance,
                refractory_period=extract_numeric(spec.get("condition")),
                attributes={
                    "refractory_condition": spec.get("condition"),
                    "refractory_action": spec.get("action"),
                },
            )
        elif concept == "membrane_potential_decay":
            merge_population(
                network,
                name=population_name(spec["subject"]),
                provenance=provenance,
                membrane_time_constant=extract_numeric(spec.get("condition")),
                attributes={"decay_condition": spec.get("condition")},
            )
        elif concept == "synaptic_weight":
            source, target = connection_endpoints(spec["subject"])
            merge_population(network, name=source, provenance=provenance)
            merge_population(network, name=target, provenance=provenance)
            if spec.get("matrix_kind") is not None:
                weight_matrix, matrix_attributes = lower_matrix_native_weight(
                    network,
                    spec=spec,
                    source=source,
                    target=target,
                    provenance=provenance,
                )
                merge_connection(
                    network,
                    source=source,
                    target=target,
                    provenance=provenance,
                    weight=weight_matrix,
                    polarity="inhibitory" if spec.get("negated") else "excitatory",
                    attributes=matrix_attributes,
                )
                continue
            merge_connection(
                network,
                source=source,
                target=target,
                provenance=provenance,
                weight=extract_numeric(spec.get("condition")),
                polarity="inhibitory" if spec.get("negated") else "excitatory",
            )
        elif concept == "axonal_delay":
            subject = spec["subject"]
            delay = extract_numeric(spec.get("condition"))
            if subject in {"synapse", "connection"}:
                current = network.metadata.get("default_axonal_delay")
                if current is not None and current != delay:
                    raise LoweringError(
                        f"Conflicting global axonal delay values: {current!r} vs {delay!r}."
                    )
                network.metadata["default_axonal_delay"] = delay
                network.metadata.setdefault("provenance", []).append(provenance)
            else:
                source, target = connection_endpoints(subject)
                merge_population(network, name=source, provenance=provenance)
                merge_population(network, name=target, provenance=provenance)
                merge_connection(
                    network,
                    source=source,
                    target=target,
                    provenance=provenance,
                    delay=delay,
                )
        elif concept == "stdp_learning":
            subject = spec.get("subject", "")
            source = None
            target = None
            if subject not in {"synapse", "connection"} and " to " in subject:
                source, target = connection_endpoints(subject)
                merge_population(network, name=source, provenance=provenance)
                merge_population(network, name=target, provenance=provenance)

            condition = spec.get("condition") or ""
            weight_min, weight_max = parse_weight_bounds(spec)
            network.learning_rules.append(
                LearningRuleIR(
                    kind=stdp_kind(condition),
                    source=source,
                    target=target,
                    rate=(
                        condition_value(condition, "learning rate of ")
                        if "learning rate of " in condition.lower()
                        else None
                    ),
                    window=(
                        condition_value(condition, "window of ")
                        if "window of " in condition.lower()
                        else None
                    ),
                    weight_min=weight_min,
                    weight_max=weight_max,
                    provenance=[provenance],
                    attributes={
                        "action": spec.get("action"),
                        "negated": bool(spec.get("negated")),
                        "condition": condition,
                        "update_direction": stdp_direction(spec.get("action")),
                    },
                )
            )
        elif concept == "inhibitory_connection":
            source, target = connection_endpoints(spec["subject"])
            merge_population(network, name=source, provenance=provenance)
            merge_population(network, name=target, provenance=provenance)
            weight = extract_numeric(spec.get("condition"))
            if weight is not None and weight > 0:
                weight = -weight
            if weight is None:
                weight = -1.0
            merge_connection(
                network,
                source=source,
                target=target,
                provenance=provenance,
                weight=weight,
                polarity="inhibitory",
            )
        elif concept == "population_coding":
            name = normalized_population_subject(spec["subject"])
            condition = spec.get("condition") or ""
            size = extract_numeric(condition)
            dim_match = re.search(r"(\d+)\s+dimensions", condition)
            dimensions = int(dim_match.group(1)) if dim_match else None
            shape_literal = spec.get("shape")
            shape = (
                tuple(shape_literal)
                if shape_literal is not None
                else parse_population_shape(condition)
            )

            attributes: dict[str, object] = {"population_coding_condition": condition}
            if condition.startswith("range "):
                attributes["encoding_range"] = condition.removeprefix("range ")
            if shape is not None:
                attributes["shape_intent"] = shape

            merge_population(
                network,
                name=name,
                provenance=provenance,
                size=int(size) if size is not None and "neurons" in condition else None,
                dimensions=dimensions,
                shape=shape,
                role=population_role(spec["subject"]) or "population",
                attributes=attributes,
            )
        elif concept == "population_coding_range":
            merge_population(
                network,
                name=population_name(spec["subject"]),
                provenance=provenance,
                attributes={
                    "population_coding_range_degrees": extract_numeric(
                        spec.get("condition")
                    ),
                    "population_coding_range_condition": spec.get("condition"),
                    "population_coding_range_action": spec.get("action"),
                },
            )
        elif concept == "network_topology":
            condition = spec.get("condition") or ""
            subject_name = normalized_population_subject(spec["subject"])
            if "population of" in condition:
                size = extract_numeric(condition)
                population_type = (
                    "inhibitory" if "inhibitory" in condition else "excitatory"
                )
                shape_literal = spec.get("shape")
                shape = (
                    tuple(shape_literal)
                    if shape_literal is not None
                    else parse_population_shape(condition)
                )
                attributes = {}
                if shape is not None:
                    attributes["shape_intent"] = shape
                merge_population(
                    network,
                    name=subject_name,
                    provenance=provenance,
                    size=int(size) if size is not None else None,
                    shape=shape,
                    role=population_role(spec["subject"]) or "population",
                    population_type=population_type,
                    attributes=attributes or None,
                )
            else:
                merge_population(network, name=subject_name, provenance=provenance)
                for target in split_projection_targets(condition):
                    merge_population(network, name=target, provenance=provenance)
                    merge_connection(
                        network,
                        source=subject_name,
                        target=target,
                        provenance=provenance,
                        attributes={"projection_only": True},
                    )
        elif concept == "adaptive_spiking":
            merge_population(
                network,
                name=population_name(spec["subject"]),
                provenance=provenance,
                attributes={
                    "adaptive_spiking_enabled": not bool(spec.get("negated")),
                    "adaptation_time_constant": extract_numeric(spec.get("condition")),
                    "adaptive_spiking_condition": spec.get("condition"),
                    "adaptive_spiking_action": spec.get("action"),
                },
            )
        elif concept == "receptor_dynamics":
            receptor_dynamics = parse_receptor_dynamics(spec.get("condition") or "")
            subject = population_name(spec.get("subject") or "")
            attributes = {
                **receptor_dynamics,
                "receptor_dynamics_condition": spec.get("condition"),
                "receptor_dynamics_action": spec.get("action"),
            }
            if subject in {"synapse", "connection"}:
                current = network.metadata.get("global_receptor_dynamics")
                if current is not None and any(
                    current.get(key) != value
                    for key, value in attributes.items()
                    if key in {"receptor_type", "time_constant"}
                ):
                    raise LoweringError(
                        "Conflicting global receptor dynamics declarations found."
                    )
                network.metadata["global_receptor_dynamics"] = {
                    **attributes,
                    "scope": subject,
                }
                network.metadata.setdefault("provenance", []).append(provenance)
            else:
                source, target = connection_endpoints(spec["subject"])
                merge_population(network, name=source, provenance=provenance)
                merge_population(network, name=target, provenance=provenance)
                merge_connection(
                    network,
                    source=source,
                    target=target,
                    provenance=provenance,
                    attributes=attributes,
                )
        elif concept == "background_noise":
            condition = spec.get("condition") or ""
            parameterization = (
                "variance" if condition.startswith("variance of ") else "amplitude"
            )
            merge_population(
                network,
                name=population_name(spec["subject"]),
                provenance=provenance,
                attributes={
                    "background_noise_value": extract_numeric(condition),
                    "background_noise_parameterization": parameterization,
                    "background_noise_condition": condition,
                    "background_noise_action": spec.get("action"),
                },
            )
        elif concept == "spatial_connectivity":
            condition = spec.get("condition") or ""
            subject_name = population_name(spec["subject"])
            action = spec.get("action") or ""
            connectivity_pattern = spec.get("connectivity_pattern")
            merge_population(network, name=subject_name, provenance=provenance)
            if connectivity_pattern == "one_to_one":
                target_name = population_name(action.removeprefix("connect to "))
                merge_population(network, name=target_name, provenance=provenance)
                merge_connection(
                    network,
                    source=subject_name,
                    target=target_name,
                    provenance=provenance,
                    connectivity_pattern="one_to_one",
                    attributes={
                        "spatial_connectivity_condition": condition,
                        "spatial_connectivity_action": action,
                    },
                )
            elif connectivity_pattern == "binary_mask":
                target_name = population_name(action.removeprefix("connect to "))
                merge_population(network, name=target_name, provenance=provenance)
                merge_connection(
                    network,
                    source=subject_name,
                    target=target_name,
                    provenance=provenance,
                    connectivity_pattern="binary_mask",
                    connectivity_mask=(
                        tuple(
                            tuple(int(value) for value in row)
                            for row in spec["connectivity_mask"]
                        )
                        if spec.get("connectivity_mask") is not None
                        else parse_connectivity_mask(
                            condition.removeprefix("binary mask ").strip()
                        )
                    ),
                    attributes={
                        "spatial_connectivity_condition": condition,
                        "spatial_connectivity_action": action,
                    },
                )
            elif connectivity_pattern == "distance_dependent_probability":
                target_name = population_name(action.removeprefix("connect to "))
                merge_population(network, name=target_name, provenance=provenance)
                merge_connection(
                    network,
                    source=subject_name,
                    target=target_name,
                    provenance=provenance,
                    connectivity_pattern="distance_dependent_probability",
                    attributes={
                        "spatial_connectivity_condition": condition,
                        "spatial_connectivity_action": action,
                    },
                )
            elif connectivity_pattern == "random_sparsity":
                target_name = population_name(action.removeprefix("connect to "))
                merge_population(network, name=target_name, provenance=provenance)
                merge_connection(
                    network,
                    source=subject_name,
                    target=target_name,
                    provenance=provenance,
                    connectivity_pattern="random_sparsity",
                    connection_density=spec.get("connection_density"),
                    attributes={
                        "spatial_connectivity_condition": condition,
                        "spatial_connectivity_action": action,
                    },
                )
            elif connectivity_pattern == "local_radius" or condition.startswith(
                "radius of "
            ):
                merge_connection(
                    network,
                    source=subject_name,
                    target=subject_name,
                    provenance=provenance,
                    connectivity_pattern="local_radius",
                    locality_radius=spec.get("locality_radius")
                    or extract_numeric(condition),
                    attributes={
                        "spatial_connectivity_condition": condition,
                        "spatial_connectivity_action": spec.get("action"),
                    },
                )
            else:
                raise LoweringError(
                    f"Unsupported spatial connectivity condition {condition!r}."
                )
        elif concept == "lateral_inhibition":
            name = population_name(spec["subject"])
            radius = extract_numeric(spec.get("condition"))
            merge_population(network, name=name, provenance=provenance)
            merge_connection(
                network,
                source=name,
                target=name,
                provenance=provenance,
                polarity="inhibitory",
                connectivity_pattern="local_radius",
                locality_radius=radius,
                attributes={
                    "lateral_inhibition_radius": radius,
                    "lateral_inhibition_condition": spec.get("condition"),
                    "lateral_inhibition_action": spec.get("action"),
                },
            )
        elif concept == "homeostatic_plasticity":
            merge_population(
                network,
                name=population_name(spec["subject"]),
                provenance=provenance,
                attributes={
                    "homeostatic_target_rate_hz": extract_numeric(
                        spec.get("condition")
                    ),
                    "homeostatic_condition": spec.get("condition"),
                    "homeostatic_action": spec.get("action"),
                },
            )
        elif concept == "neuromodulation":
            network.metadata.setdefault("provenance", []).append(provenance)
            network.metadata.setdefault("neuromodulation_rules", []).append(
                {
                    "modulator": population_name(spec["subject"]),
                    "factor": extract_numeric(spec.get("condition")),
                    "condition": spec.get("condition"),
                    "action": spec.get("action"),
                    "negated": bool(spec.get("negated")),
                    "raw": spec.get("raw"),
                }
            )
        elif concept == "short_term_plasticity":
            condition = spec.get("condition") or ""
            stp_data = parse_short_term_plasticity(condition)
            subject = spec.get("subject") or ""
            if " to " in subject:
                source, target = connection_endpoints(subject)
                merge_population(network, name=source, provenance=provenance)
                merge_population(network, name=target, provenance=provenance)
                merge_connection(
                    network,
                    source=source,
                    target=target,
                    provenance=provenance,
                    attributes={
                        "short_term_plasticity_type": stp_data["stp_type"],
                        "short_term_plasticity_recovery_time": stp_data[
                            "recovery_time"
                        ],
                        "utilization_rate": stp_data.get("utilization_rate"),
                        "short_term_plasticity_condition": condition,
                        "short_term_plasticity_action": spec.get("action"),
                    },
                )
            else:
                network.metadata.setdefault("provenance", []).append(provenance)
                network.metadata.setdefault("short_term_plasticity_rules", []).append(
                    {
                        **stp_data,
                        "condition": condition,
                        "action": spec.get("action"),
                        "subject": subject,
                    }
                )
        elif concept == "timing_declaration":
            condition = spec.get("condition") or ""
            if condition.startswith("simulation time of "):
                network.timing_declarations.append(
                    TimingDeclarationIR(
                        kind="simulation_time",
                        value=extract_numeric(condition),
                        unit="seconds",
                        provenance=[provenance],
                    )
                )
            elif condition.startswith("timestep of "):
                network.timing_declarations.append(
                    TimingDeclarationIR(
                        kind="timestep",
                        value=extract_numeric(condition),
                        unit="seconds",
                        provenance=[provenance],
                    )
                )
            elif condition.startswith("delay quantization of "):
                network.timing_declarations.append(
                    TimingDeclarationIR(
                        kind="delay_quantization",
                        value=extract_numeric(condition),
                        unit="seconds",
                        provenance=[provenance],
                    )
                )
            elif condition.startswith("biological speed multiplier of "):
                network.timing_declarations.append(
                    TimingDeclarationIR(
                        kind="biological_speed_multiplier",
                        value=extract_numeric(condition),
                        unit="multiplier",
                        provenance=[provenance],
                    )
                )
            else:
                raise LoweringError(
                    f"Unsupported timing declaration condition {condition!r}."
                )
        elif concept == "akida_hardware":
            if network.akida_hardware is not None:
                raise LoweringError("Multiple Akida hardware declarations found.")
            network.akida_hardware = AkidaHardwareIR(
                version=spec.get("condition") or "", provenance=[provenance]
            )
        elif concept == "akida_spatiotemporal":
            condition = (spec.get("condition") or "").lower()
            block_type = (
                AkidaBlockType.SPATIAL
                if "spatial" in condition
                else AkidaBlockType.TEMPORAL
            )

            subject = spec.get("subject", "")
            source = None
            target = None
            if " to " in subject:
                source, target = connection_endpoints(subject)

            network.akida_connection_properties.append(
                AkidaConnectionPropertyIR(
                    block_type=block_type,
                    source=source,
                    target=target,
                    provenance=[provenance],
                )
            )

    return network
