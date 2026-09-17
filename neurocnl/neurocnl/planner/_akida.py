"""BrainChip Akida fail-closed scaffold-exportability planner."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

from neurocnl.ir import NetworkIR
from neurocnl.ir.topology import NetworkTopologyAnalyzer
from neurocnl.network_facts import NetworkFacts

from ._shared import _estimate_memory_kb

if TYPE_CHECKING:
    from neurocnl.backends.akida_capabilities import (
        Akida1CapabilityChecker,
        Akida2CapabilityChecker,
    )
    from neurocnl.contracts.akida_deployment_contract import AkidaExportResult


def _akida_topology_detail(ir: NetworkIR, normalized_version: str) -> str:
    """Name the structural feature that made a topology unsupported.

    The capability checkers only return a verdict, so without this the user is
    told the topology is unsupported without being told which feature to
    change. Order matches the checkers' own order of tests.
    """
    from neurocnl.contracts.akida_deployment_contract import AKIDA_TOPOLOGY

    analyzer = NetworkTopologyAnalyzer(ir)

    if ir.akida_connection_properties:
        return "Akida connection properties, which require Akida 2"
    if normalized_version == "akida1":
        if analyzer.has_lateral_inhibitory():
            return "inhibitory connections, which require Akida 2"
        if analyzer.has_recurrent():
            return "a recurrent loop; Akida 1 needs a straight feed-forward chain"
        branching = [
            name for name, targets in analyzer.out_edges.items() if len(targets) > 1
        ]
        if branching:
            return (
                f"branching out of {', '.join(sorted(branching))}; "
                "Akida 1 needs a straight feed-forward chain"
            )
        merging = [
            name for name, sources in analyzer.in_edges.items() if len(sources) > 1
        ]
        if merging:
            return (
                f"more than one connection into {', '.join(sorted(merging))}; "
                "Akida 1 needs a straight feed-forward chain"
            )
        return "a non-sequential graph; Akida 1 needs a straight feed-forward chain"

    high_in_degree = [
        name
        for name, sources in analyzer.in_edges.items()
        if len(sources) > AKIDA_TOPOLOGY.akida2_max_in_edges
    ]
    if high_in_degree:
        return (
            f"more than {AKIDA_TOPOLOGY.akida2_max_in_edges} connections into "
            f"{', '.join(sorted(high_in_degree))}"
        )
    return "an unsupported graph structure"


def plan_akida_exportability(
    ir: NetworkIR, akida_version: str = "akida", bit_width: int = 4
) -> AkidaExportResult:
    """Fail-closed scaffold-exportability assessment for BrainChip Akida.

    Checks every constraint in the Akida deployment contract and returns
    an ``AkidaExportResult`` with support state, rejection reasons, and
    warnings.  The result's model validator enforces the fail-closed
    invariant: support_state is ``EXPORTABLE_SCAFFOLD`` only when
    rejections is empty.

    Topology classification is delegated to the shared Akida capability
    checkers rather than duplicated locally.

    Parameters
    ----------
    ir : NetworkIR
        The intermediate representation of a NeuroCNL-authored network.
    akida_version : str
        Akida variant to check against: ``"akida"`` (defaults to Akida1
        behaviour), ``"akida1"``, or ``"akida2"``.
    bit_width : int
        Target weight quantization bit-width (default 4).

    Returns
    -------
    AkidaExportResult
        Support state, list of rejections, warnings, and network summary.
    """
    from neurocnl.contracts.akida_deployment_contract import (
        AKIDA_LIMITS,
        AkidaExportResult,
        AkidaRejectionReason,
        AkidaSupportState,
        akida_version_label,
        normalize_akida_version,
    )

    normalized_version = normalize_akida_version(akida_version)
    rejections: list[AkidaRejectionReason] = []
    warnings: list[str] = []
    topology_verdict = "unknown"
    # Values the AKIDA_REJECTION_MESSAGES templates interpolate, so every
    # rejection can name the offending node and the limit it crossed.
    details: dict[str, Any] = {
        "bit_width": bit_width,
        "version": akida_version_label(normalized_version),
    }

    facts = NetworkFacts.from_ir(ir)

    # -- 1. Validate bit-width --
    if bit_width not in AKIDA_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS:
        rejections.append(AkidaRejectionReason.WEIGHT_BIT_WIDTH_UNSUPPORTED)

    # -- 2. Count total neurons --
    n_neurons = facts.n_neurons_total

    details["n_neurons"] = n_neurons
    if n_neurons > AKIDA_LIMITS.MAX_NEURONS:
        rejections.append(AkidaRejectionReason.EXCEEDS_NEURON_CAPACITY)
    elif n_neurons > AKIDA_LIMITS.MAX_NEURONS * 0.8:
        warnings.append(
            f"Network uses {n_neurons}/{AKIDA_LIMITS.MAX_NEURONS:,} neurons (>{80}% capacity)"
        )

    # -- 3. Check per-NP population size --
    # NetworkTopologyAnalyzer owns this check so the planner and the V1/V2
    # capability checkers cannot drift apart. It skips I/O ports, which are
    # graph endpoints rather than neurons — an input port's width comes from
    # the dataset, so rejecting it named no parameter the user could change.
    oversized = NetworkTopologyAnalyzer(ir).oversized_population(
        AKIDA_LIMITS.MAX_NEURONS_PER_NP
    )
    if oversized is not None:
        rejections.append(AkidaRejectionReason.EXCEEDS_NP_SIZE)
        details["population"] = oversized[0]
        details["pop_size"] = oversized[1]

    # -- 4. Estimate synapse count --
    n_synapses = facts.n_synapses_total

    # -- 5. Estimate memory --
    # Same formula as Teensy's estimate; only the bit-width default differs.
    memory_kb = _estimate_memory_kb(n_neurons, n_synapses, bit_width)
    details["memory_kb"] = round(memory_kb, 1)
    if memory_kb > AKIDA_LIMITS.MEMORY_BUDGET_KB:
        rejections.append(AkidaRejectionReason.EXCEEDS_MEMORY_BUDGET)
    elif memory_kb > AKIDA_LIMITS.MEMORY_BUDGET_KB * 0.8:
        warnings.append(
            f"Estimated memory {memory_kb:.1f} KB / "
            f"{AKIDA_LIMITS.MEMORY_BUDGET_KB:,} KB (>{80}% capacity)"
        )

    # -- 6. Check neuron models --
    allowed_models = {m.lower() for m in AKIDA_LIMITS.SUPPORTED_NEURON_MODELS}
    explicitly_modeled_neuron_types = {"lif", "izhikevich", "iaf", "adex"}
    for pop in ir.populations.values():
        if (
            pop.population_type
            and pop.population_type.lower() in explicitly_modeled_neuron_types
            and pop.population_type.lower() not in allowed_models
        ):
            rejections.append(AkidaRejectionReason.UNSUPPORTED_NEURON_MODEL)
            details["population"] = pop.name
            details["model"] = pop.population_type
            break

    # -- 7. Check learning rules --
    if ir.learning_rules:
        rejections.append(AkidaRejectionReason.UNSUPPORTED_LEARNING_RULE)
        details["rule"] = ir.learning_rules[0].kind

    # -- 8. Check weight magnitudes --
    weights = facts.connection_weights_total
    if weights:
        max_abs = facts.max_abs_weight or 0.0
        if max_abs > AKIDA_LIMITS.MAX_WEIGHT:
            rejections.append(AkidaRejectionReason.WEIGHT_EXCEEDS_MAX)
            details["weight"] = max_abs

    # -- 9. Check weight quantizability --
    # Deliberately NOT `quantisation_fidelity` (used by PYNQ's equivalent check
    # above): that measures whether *any* fixed-point image exists (rejects
    # only non-finite weights or a matrix that collapses entirely to zero).
    # This check instead requires every weight's scaled value to round-trip to
    # within 1e-3 of an integer — a materially stricter, different question.
    # Unifying them would change which networks Akida accepts, which is a
    # policy change out of scope for this behavior-preserving slice.
    if weights and AkidaRejectionReason.WEIGHT_EXCEEDS_MAX not in rejections:
        max_int_val = (2 ** (bit_width - 1)) - 1
        max_abs_weight = facts.max_abs_weight or 0.0
        if max_abs_weight > 0:
            scale_factor = max_int_val / max_abs_weight
            for w in weights:
                scaled = w * scale_factor
                if abs(scaled - round(scaled)) > 1e-3:
                    rejections.append(AkidaRejectionReason.WEIGHT_NOT_QUANTIZABLE)
                    break

    # -- 10. Run topology check via capability checker --
    declared_version = None
    if ir.akida_hardware is not None:
        declared_version = normalize_akida_version(ir.akida_hardware.version)
        if declared_version != normalized_version:
            rejections.append(AkidaRejectionReason.AKIDA_VERSION_MISMATCH)
            details["declared_version"] = akida_version_label(declared_version)
            details["requested_version"] = akida_version_label(normalized_version)

    checker: Akida1CapabilityChecker | Akida2CapabilityChecker
    if normalized_version == "akida1":
        from neurocnl.backends.akida_capabilities import Akida1CapabilityChecker

        checker = Akida1CapabilityChecker()
        topology_verdict = checker.check_network_topology(ir)

        # Akida1 does not support connection properties
        if (
            hasattr(ir, "akida_connection_properties")
            and ir.akida_connection_properties
        ):
            rejections.append(AkidaRejectionReason.CONNECTION_PROPERTIES_ON_V1)
    elif normalized_version == "akida2":
        from neurocnl.backends.akida_capabilities import Akida2CapabilityChecker

        checker = Akida2CapabilityChecker()
        topology_verdict = checker.check_network_topology(ir)
        if topology_verdict == "approximate":
            warnings.append(
                "Recurrent connections will be approximated via temporal blocks on Akida 2"
            )

    # An oversized layer already makes the capability checkers return
    # "unsupported", so reporting UNSUPPORTED_TOPOLOGY as well would show the
    # user two codes for one cause and hide which one is actionable. The
    # verdict still stays "unsupported" — only the duplicate code is dropped.
    if (
        topology_verdict == "unsupported"
        and AkidaRejectionReason.EXCEEDS_NP_SIZE not in rejections
    ):
        rejections.append(AkidaRejectionReason.UNSUPPORTED_TOPOLOGY)
        details["detail"] = _akida_topology_detail(ir, normalized_version)

    # -- Build verdict --
    # De-duplicate rejections
    rejections = list(dict.fromkeys(rejections))

    if rejections:
        support_state = AkidaSupportState.UNSUPPORTED
    else:
        support_state = AkidaSupportState.EXPORTABLE_SCAFFOLD

    return AkidaExportResult(
        support_state=support_state,
        akida_version=normalized_version,
        rejections=rejections,
        warnings=warnings,
        topology_verdict=topology_verdict,
        network_summary={
            "n_neurons": n_neurons,
            "n_synapses": n_synapses,
            "memory_estimate_kb": round(memory_kb, 2),
            "quantization_bits": bit_width,
            "n_populations": len(ir.populations),
            "n_connections": len(ir.connections),
            "n_learning_rules": len(ir.learning_rules),
        },
        rejection_details=details,
    )
