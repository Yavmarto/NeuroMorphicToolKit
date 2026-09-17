"""Advisory backend support classification — the planner's public API entry point."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from neurocnl.backends import get_backend_capability
from neurocnl.ir import NetworkIR
from neurocnl.network_facts import NetworkFacts

from ._shared import _append_warning

_NIR_CONCEPT_POLICY_WARNINGS = {
    "receptor_dynamics": (
        "Concept 'receptor_dynamics' is exportable on backend 'nir' as metadata only. "
        "NeuroCNL preserves receptor type and time constant for downstream consumers, but the "
        "current Input/LIF/Linear bridge does not have an executable synapse-operator lowering "
        "path and treats this as a stable metadata-only contract."
    ),
    "spatial_connectivity": (
        "Concept 'spatial_connectivity' is only partially exportable on backend 'nir'. "
        "One-to-one and explicit binary-mask families lower executable weights, while "
        "local-radius and probability-based forms remain unsupported."
    ),
}


@dataclass(slots=True)
class PlannerResult:
    """Advisory backend support summary."""

    backend: str
    verdict: str
    supported_concepts: list[str] = field(default_factory=list)
    approximated_concepts: list[str] = field(default_factory=list)
    unsupported_concepts: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)


def _collect_ir_concepts(ir: NetworkIR) -> list[str]:
    concepts: set[str] = set()

    for population in ir.populations.values():
        concepts.update(
            provenance.concept
            for provenance in population.provenance
            if provenance.concept
        )
    for connection in ir.connections:
        concepts.update(
            provenance.concept
            for provenance in connection.provenance
            if provenance.concept
        )
    for learning_rule in ir.learning_rules:
        concepts.update(
            provenance.concept
            for provenance in learning_rule.provenance
            if provenance.concept
        )
    for declaration in ir.timing_declarations:
        concepts.update(
            provenance.concept
            for provenance in declaration.provenance
            if provenance.concept
        )
    for provenance in ir.metadata.get("provenance", []):
        concept = getattr(provenance, "concept", None)
        if concept:
            concepts.add(concept)

    return sorted(concepts)


def plan_backend_support(
    ir: NetworkIR, backend: str, validator_report: dict[str, Any] | None = None
) -> PlannerResult:
    """Advisory support classification for a target backend."""
    profile = get_backend_capability(backend)
    facts = NetworkFacts.from_ir(ir)
    concepts = _collect_ir_concepts(ir)
    supported: list[str] = []
    approximated: list[str] = []
    unsupported: list[str] = []
    warnings: list[str] = []

    nir_concept_status: dict[str, str] | None = None
    if profile.name == "nir":
        from neurocnl.export.nir_exporter import summarize_nir_lowering

        verdict_map = {
            "lowered_faithfully": "faithful",
            "lowered_as_metadata": "approximate",
            "lowered_approximately": "approximate",
            "not_lowered": "unsupported",
        }
        lowering_summary = summarize_nir_lowering(ir)
        nir_concept_status = {
            concept: verdict_map.get(verdict, "unsupported")
            for concept, verdict in lowering_summary.concept_verdicts.items()
        }
        for message in lowering_summary.warning_summary.values():
            _append_warning(warnings, message)

    for concept in concepts:
        status = (
            nir_concept_status.get(concept, "unsupported")
            if nir_concept_status is not None
            else profile.concept_support.get(concept, "unsupported")
        )
        if status == "faithful":
            supported.append(concept)
        elif status == "approximate":
            approximated.append(concept)
            _append_warning(
                warnings,
                (
                    _NIR_CONCEPT_POLICY_WARNINGS.get(
                        concept,
                        f"Concept {concept!r} is only approximately supported on backend {profile.name!r}.",
                    )
                    if profile.name == "nir"
                    else f"Concept {concept!r} is only approximately supported on backend {profile.name!r}."
                ),
            )
        else:
            unsupported.append(concept)
            _append_warning(
                warnings,
                f"Concept {concept!r} is unsupported on backend {profile.name!r}.",
            )

    timestep = facts.declared_timestep_seconds
    if (
        timestep is not None
        and profile.timing_resolution_seconds is not None
        and timestep != profile.timing_resolution_seconds
    ):
        warnings.append(
            "Declared timestep "
            f"{timestep} differs from backend timing resolution "
            f"{profile.timing_resolution_seconds}."
        )

    quantization = facts.declared_delay_quantization_seconds
    if (
        quantization is not None
        and profile.timing_resolution_seconds is not None
        and quantization < profile.timing_resolution_seconds
    ):
        warnings.append(
            "Declared delay quantization "
            f"{quantization} is finer than backend timing resolution "
            f"{profile.timing_resolution_seconds}."
        )

    if unsupported:
        verdict = "unsupported"
    elif approximated or warnings:
        verdict = "approximate"
    else:
        verdict = "faithful"

    if profile.name == "loihi" and validator_report is not None:
        failed_entries = validator_report.get("failed", [])
        for entry in failed_entries:
            code = entry.get("code", "")
            if code.startswith("loihi_"):
                verdict = "unsupported"
                warnings.append(entry.get("message", f"Constraint {code} failed"))

        warning_entries = validator_report.get("warnings", [])
        for entry in warning_entries:
            code = entry.get("code", "")
            if code.startswith("loihi_"):
                message = entry.get("message") or entry.get(
                    "reason", f"Constraint {code} warning"
                )
                if message not in warnings:
                    warnings.append(message)
                if verdict == "faithful":
                    verdict = "approximate"

    if profile.name == "teensy":
        from neurocnl.contracts.teensy_deployment_contract import (
            TeensyDeployabilityVerdict,
        )

        from ._teensy import plan_teensy_deployability

        teensy_result = plan_teensy_deployability(ir)
        summary = teensy_result.network_summary or {}

        if teensy_result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE:
            verdict = "unsupported"
            for rejection in teensy_result.rejections:
                n_neurons = summary.get("n_neurons", "?")
                n_synapses = summary.get("n_synapses", "?")
                memory_kb = summary.get("memory_estimate_kb", "?")
                code = rejection.value
                if code == "exceeds_neuron_capacity":
                    warnings.append(
                        f"Teensy: network requires {n_neurons} neurons, "
                        "exceeds Teensy 4.1 limit of 4096"
                    )
                elif code == "exceeds_synapse_capacity":
                    warnings.append(
                        f"Teensy: network requires {n_synapses} synapses, "
                        "exceeds Teensy 4.1 memory budget at 32-bit weights"
                    )
                elif code == "exceeds_memory_budget":
                    warnings.append(
                        f"Teensy: estimated memory {memory_kb} KB exceeds "
                        "Teensy 4.1 budget of 1024 KB"
                    )
                elif code == "unsupported_neuron_model":
                    warnings.append(
                        "Teensy: network contains non-LIF neuron model; only LIF is supported"
                    )
                elif code == "unsupported_learning_rule":
                    warnings.append(
                        "Teensy: network contains learning rules; "
                        "only static synapses are supported"
                    )
                elif code == "unsupported_topology":
                    warnings.append(
                        "Teensy: network topology (recurrent connections, lateral "
                        "inhibition, or spatial connectivity) is not supported"
                    )
                elif code == "unsupported_axonal_delay":
                    warnings.append(
                        "Teensy: axonal delays are not supported; "
                        "all connections must be instantaneous"
                    )
                elif code == "io_shape_mismatch":
                    warnings.append(
                        "Teensy: input/output population size exceeds available I/O pins (max 55)"
                    )
                elif code == "timestep_incompatible":
                    warnings.append(
                        "Teensy: declared timestep is finer than the 1 ms Teensy timing resolution"
                    )
                else:
                    warnings.append(f"Teensy: deployment rejected ({code})")

        elif (
            teensy_result.verdict == TeensyDeployabilityVerdict.DEPLOYABLE_WITH_WARNINGS
        ):
            if verdict == "faithful":
                verdict = "approximate"
            for w in teensy_result.warnings:
                if w not in warnings:
                    warnings.append(f"Teensy: {w}")

    if profile.name == "pynq":
        from neurocnl.contracts.pynq_deployment_contract import (
            PYNQ_LIMITS,
            PynqSupportState,
        )

        from ._pynq import plan_pynq_exportability

        pynq_result = plan_pynq_exportability(ir)
        summary = pynq_result.network_summary or {}

        if pynq_result.support_state == PynqSupportState.NOT_EXPORTABLE:
            verdict = "not_exportable"
            for pynq_rejection in pynq_result.rejections:
                n_neurons = summary.get("n_neurons", "?")
                n_synapses = summary.get("n_synapses", "?")
                memory_kb = summary.get("memory_estimate_kb", "?")
                code = pynq_rejection.value
                if code == "exceeds_neuron_capacity":
                    warnings.append(
                        f"PYNQ: network requires {n_neurons} neurons, "
                        f"exceeds PYNQ Z2 limit of {PYNQ_LIMITS.MAX_NEURONS}"
                    )
                elif code == "exceeds_synapse_capacity":
                    warnings.append(
                        f"PYNQ: network requires {n_synapses} synapses, "
                        f"exceeds PYNQ Z2 limit of {PYNQ_LIMITS.MAX_SYNAPSES}"
                    )
                elif code == "exceeds_memory_budget":
                    warnings.append(
                        f"PYNQ: estimated memory {memory_kb} KB exceeds PYNQ Z2 budget of 512 KB"
                    )
                elif code == "weight_not_quantizable":
                    warnings.append(
                        "PYNQ: one or more weights cannot be mapped to "
                        "fixed-point integer representation"
                    )
                elif code == "unsupported_neuron_model":
                    warnings.append(
                        "PYNQ: network contains unsupported neuron model; "
                        f"only {', '.join(PYNQ_LIMITS.SUPPORTED_NEURON_MODELS)} are supported"
                    )
                elif code == "unsupported_learning_rule":
                    warnings.append(
                        "PYNQ: network contains learning rules; "
                        "only static synapses are supported on FPGA overlay"
                    )
                elif code == "unsupported_topology":
                    warnings.append(
                        "PYNQ: network topology (recurrent connections, lateral "
                        "inhibition, or spatial connectivity) is not supported"
                    )
                elif code == "weight_bit_width_unsupported":
                    warnings.append(
                        "PYNQ: requested weight bit-width not in supported set {4, 8, 16}"
                    )
                else:
                    warnings.append(f"PYNQ: export rejected ({code})")

        elif pynq_result.support_state == PynqSupportState.EXPORTABLE_WITH_WARNINGS:
            verdict = "exportable_with_warnings"
            for w in pynq_result.warnings:
                if w not in warnings:
                    warnings.append(f"PYNQ: {w}")

        elif pynq_result.support_state == PynqSupportState.EXPORTABLE:
            verdict = "exportable"

    if profile.name in ("akida", "akida1", "akida2"):
        from neurocnl.contracts.akida_deployment_contract import (
            AkidaRejectionReason,
            AkidaSupportState,
        )

        from ._akida import plan_akida_exportability

        akida_result = plan_akida_exportability(ir, akida_version=profile.name)
        topology_related_rejections = {
            AkidaRejectionReason.EXCEEDS_NP_SIZE,
            AkidaRejectionReason.UNSUPPORTED_TOPOLOGY,
            AkidaRejectionReason.CONNECTION_PROPERTIES_ON_V1,
            AkidaRejectionReason.AKIDA_VERSION_MISMATCH,
        }

        if akida_result.topology_verdict == "unsupported" or any(
            rejection in topology_related_rejections
            for rejection in akida_result.rejections
        ):
            if "network_topology" in supported:
                supported.remove("network_topology")
            if "network_topology" in approximated:
                approximated.remove("network_topology")
            if "network_topology" not in unsupported:
                unsupported.append("network_topology")
        elif akida_result.topology_verdict == "faithful":
            if "network_topology" in unsupported:
                unsupported.remove("network_topology")
            if "network_topology" in approximated:
                approximated.remove("network_topology")
            if "network_topology" not in supported:
                supported.append("network_topology")
        elif akida_result.topology_verdict == "approximate":
            if "network_topology" in supported:
                supported.remove("network_topology")
            if "network_topology" in unsupported:
                unsupported.remove("network_topology")
            if "network_topology" not in approximated:
                approximated.append("network_topology")

        if akida_result.support_state == AkidaSupportState.UNSUPPORTED:
            verdict = "unsupported"
            # One message source, shared with the deploy endpoint. The previous
            # hand-rolled chain here restated every limit as a literal, so the
            # numbers drifted from AKIDA_LIMITS and named no offending node.
            for message in akida_result.rejection_messages():
                warnings.append(f"Akida: {message}")

        elif akida_result.topology_verdict == "approximate" or akida_result.warnings:
            if verdict == "faithful":
                verdict = "approximate"
            for w in akida_result.warnings:
                if w not in warnings:
                    warnings.append(f"Akida: {w}")

        warnings = [
            warning
            for warning in warnings
            if not warning.startswith("Concept 'network_topology' ")
        ]
        if unsupported:
            verdict = "unsupported"
        elif approximated or warnings:
            verdict = "approximate"
        else:
            verdict = "faithful"

    return PlannerResult(
        backend=profile.name,
        verdict=verdict,
        supported_concepts=supported,
        approximated_concepts=approximated,
        unsupported_concepts=unsupported,
        warnings=warnings,
    )
