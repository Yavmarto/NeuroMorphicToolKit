"""Teensy 4.1 fail-closed deployability planner."""

from __future__ import annotations

from typing import TYPE_CHECKING

from neurocnl.ir import NetworkIR
from neurocnl.ir.types import PORT_POPULATION_TYPES as _PORT_POPULATION_TYPES
from neurocnl.network_facts import DEFAULT_POPULATION_SIZE as _DEFAULT_POPULATION_SIZE
from neurocnl.network_facts import NetworkFacts

from ._shared import _estimate_memory_kb

if TYPE_CHECKING:
    from neurocnl.contracts.teensy_deployment_contract import TeensyDeploymentResult


def plan_teensy_deployability(ir: NetworkIR) -> TeensyDeploymentResult:
    """Fail-closed deployability assessment for Teensy 4.1.

    Checks every constraint in the Teensy deployment contract and returns
    a ``TeensyDeploymentResult`` with verdict, rejection reasons, and
    warnings.  The result's model validator enforces the fail-closed
    invariant: verdict is ``DEPLOYABLE`` only when rejections is empty.

    Parameters
    ----------
    ir : NetworkIR
        The intermediate representation of a NeuroCNL-authored network.

    Returns
    -------
    TeensyDeploymentResult
        Verdict, list of rejections, warnings, and network summary.
    """
    from neurocnl.contracts.teensy_deployment_contract import (
        TEENSY_LIMITS,
        TEENSY_TOPOLOGY,
        TeensyDeployabilityVerdict,
        TeensyDeploymentResult,
        TeensyRejectionReason,
    )

    facts = NetworkFacts.from_ir(ir)
    rejections: list[TeensyRejectionReason] = []
    warnings: list[str] = []

    # -- 1. Count total neurons --
    n_neurons = facts.n_neurons_total

    if n_neurons > TEENSY_LIMITS.MAX_NEURONS:
        rejections.append(TeensyRejectionReason.EXCEEDS_NEURON_CAPACITY)
    elif n_neurons > TEENSY_LIMITS.MAX_NEURONS * 0.8:
        warnings.append(
            f"Network uses {n_neurons}/{TEENSY_LIMITS.MAX_NEURONS} neurons (>{80}% capacity)"
        )

    # -- 2. Estimate synapse count --
    n_synapses = facts.n_synapses_total
    max_synapses = TEENSY_LIMITS.MAX_SYNAPSES_FLOAT32  # Conservative: 32-bit
    if n_synapses > max_synapses:
        rejections.append(TeensyRejectionReason.EXCEEDS_SYNAPSE_CAPACITY)
    elif max_synapses > 0 and n_synapses > max_synapses * 0.8:
        warnings.append(
            f"Network uses {n_synapses}/{max_synapses} synapses (>{80}% capacity)"
        )

    # -- 3. Estimate memory --
    memory_kb = _estimate_memory_kb(n_neurons, n_synapses)
    if memory_kb > TEENSY_LIMITS.MEMORY_BUDGET_KB:
        rejections.append(TeensyRejectionReason.EXCEEDS_MEMORY_BUDGET)
    elif memory_kb > TEENSY_LIMITS.MEMORY_BUDGET_KB * 0.8:
        warnings.append(
            f"Estimated memory {memory_kb:.1f} KB / {TEENSY_LIMITS.MEMORY_BUDGET_KB} KB "
            f"(>{80}% capacity)"
        )

    # -- 4. Check neuron models --
    allowed_models = {m.lower() for m in TEENSY_TOPOLOGY.allowed_neuron_models}
    semantic_roles = {"excitatory", "inhibitory"} | _PORT_POPULATION_TYPES
    for pop in ir.populations.values():
        if (
            pop.population_type
            and pop.population_type.lower() not in semantic_roles
            and pop.population_type.lower() not in allowed_models
        ):
            rejections.append(TeensyRejectionReason.UNSUPPORTED_NEURON_MODEL)
            break

    # -- 5. Check learning rules --
    if ir.learning_rules and not TEENSY_TOPOLOGY.allow_learning_rules:
        rejections.append(TeensyRejectionReason.UNSUPPORTED_LEARNING_RULE)

    # -- 6. Check recurrent connections --
    if not TEENSY_TOPOLOGY.allow_recurrent and facts.has_recurrent_connections:
        rejections.append(TeensyRejectionReason.UNSUPPORTED_TOPOLOGY)

    # -- 7. Check axonal delays --
    if not TEENSY_TOPOLOGY.allow_axonal_delays and facts.has_axonal_delays:
        rejections.append(TeensyRejectionReason.UNSUPPORTED_AXONAL_DELAY)

    # -- 8. Check unsupported concepts (lateral inhibition, spatial connectivity) --
    unsupported_concepts = {"lateral_inhibition", "spatial_connectivity"}
    found_unsupported = facts.provenance_concepts & unsupported_concepts
    if (
        found_unsupported
        and TeensyRejectionReason.UNSUPPORTED_TOPOLOGY not in rejections
    ):
        rejections.append(TeensyRejectionReason.UNSUPPORTED_TOPOLOGY)

    # -- 9. Check I/O shape --
    pop_names = list(ir.populations.keys())
    if pop_names:
        first_pop = ir.populations[pop_names[0]]
        last_pop = ir.populations[pop_names[-1]]
        first_size = first_pop.size or _DEFAULT_POPULATION_SIZE
        last_size = last_pop.size or _DEFAULT_POPULATION_SIZE
        if first_size > TEENSY_LIMITS.MAX_IO_PINS:
            rejections.append(TeensyRejectionReason.IO_SHAPE_MISMATCH)
        if (
            last_size > TEENSY_LIMITS.MAX_IO_PINS
            and TeensyRejectionReason.IO_SHAPE_MISMATCH not in rejections
        ):
            rejections.append(TeensyRejectionReason.IO_SHAPE_MISMATCH)

    # -- 10. Check timestep --
    for decl in ir.timing_declarations:
        if decl.kind == "timestep" and decl.value is not None:
            if decl.value < TEENSY_LIMITS.TIMESTEP_SECONDS:
                rejections.append(TeensyRejectionReason.TIMESTEP_INCOMPATIBLE)
                break

    # -- Build verdict --
    # De-duplicate rejections
    rejections = list(dict.fromkeys(rejections))

    if rejections:
        verdict = TeensyDeployabilityVerdict.NOT_DEPLOYABLE
    elif warnings:
        verdict = TeensyDeployabilityVerdict.DEPLOYABLE_WITH_WARNINGS
    else:
        verdict = TeensyDeployabilityVerdict.DEPLOYABLE

    return TeensyDeploymentResult(
        verdict=verdict,
        rejections=rejections,
        warnings=warnings,
        network_summary={
            "n_neurons": n_neurons,
            "n_synapses": n_synapses,
            "memory_estimate_kb": round(memory_kb, 2),
            "n_populations": len(ir.populations),
            "n_connections": len(ir.connections),
            "n_learning_rules": len(ir.learning_rules),
        },
    )
