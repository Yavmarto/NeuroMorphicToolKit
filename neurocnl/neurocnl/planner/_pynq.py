"""PYNQ Z2 fail-closed exportability planner."""

from __future__ import annotations

from typing import TYPE_CHECKING

from neurocnl.ir import NetworkIR
from neurocnl.ir.types import PORT_POPULATION_TYPES as _PORT_POPULATION_TYPES
from neurocnl.network_facts import NetworkFacts

if TYPE_CHECKING:
    from neurocnl.contracts.pynq_deployment_contract import PynqExportResult


def _is_linear_chain(pairs: set[tuple[str, str]]) -> bool:
    """Whether these connections form one unbranched feedforward path.

    The PYNQ overlay walks its layers in order, handing each layer's spikes to
    the next, so a branch, a merge, or two disjoint chains have nowhere to go.
    An empty set is a chain of one population and no weight matrices.
    """
    if not pairs:
        return True

    out_degree: dict[str, int] = {}
    in_degree: dict[str, int] = {}
    for source, target in pairs:
        out_degree[source] = out_degree.get(source, 0) + 1
        in_degree[target] = in_degree.get(target, 0) + 1

    if any(count > 1 for count in out_degree.values()):
        return False
    if any(count > 1 for count in in_degree.values()):
        return False

    nodes = set(out_degree) | set(in_degree)
    starts = [node for node in nodes if in_degree.get(node, 0) == 0]
    if len(starts) != 1:
        # No start at all means a cycle; more than one means disjoint chains.
        return False

    successor = dict(pairs)
    visited: set[str] = set()
    node: str | None = starts[0]
    while node is not None and node not in visited:
        visited.add(node)
        node = successor.get(node)
    return visited == nodes


def _estimate_pynq_memory_kb(
    n_neurons: int, n_synapses: int, bit_width: int = 8
) -> float:
    """Estimate PYNQ overlay memory usage in KB.

    Delegates to the deployment contract so the planner and the Neurochip-side
    payload gate cannot drift apart. The v1 formula also charged 8 bytes per
    synapse for pre/post index pairs; the overlay stores a dense row-major
    matrix, which has no indices.
    """
    from neurocnl.contracts.pynq_deployment_contract import PYNQ_LIMITS

    return PYNQ_LIMITS.estimate_memory_kb(
        num_neurons=n_neurons, num_synapses=n_synapses, bit_width=bit_width
    )


def plan_pynq_exportability(ir: NetworkIR, bit_width: int = 8) -> PynqExportResult:
    """Fail-closed exportability assessment for PYNQ Z2.

    Checks every constraint in the PYNQ deployment contract and returns
    a ``PynqExportResult`` with support state, rejection reasons, and
    warnings.  The result's model validator enforces the fail-closed
    invariant: support_state is ``EXPORTABLE`` only when rejections is empty.

    Parameters
    ----------
    ir : NetworkIR
        The intermediate representation of a NeuroCNL-authored network.
    bit_width : int
        Target weight quantization bit-width (default 4).

    Returns
    -------
    PynqExportResult
        Support state, list of rejections, warnings, and network summary.
    """
    from neurocnl.contracts.pynq_deployment_contract import (
        PYNQ_LIMITS,
        PYNQ_TOPOLOGY,
        PynqExportResult,
        PynqRejectionReason,
        PynqSupportState,
    )

    facts = NetworkFacts.from_ir(ir)
    rejections: list[PynqRejectionReason] = []
    warnings: list[str] = []

    # -- 1. Validate bit-width --
    if bit_width not in PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS:
        rejections.append(PynqRejectionReason.WEIGHT_BIT_WIDTH_UNSUPPORTED)

    # Port populations (declared input/output ports) are DMA-mapped I/O
    # boundaries, not hardware neuron populations — the overlay-v1 contract only
    # knows about the real neuron populations it maps to weight-matrix
    # connections. `export_pynq_from_ir` drops ports from both its population
    # list and its weight matrix, so every capacity gate below has to measure
    # the same thing the exporter emits: counting a 784-pixel input port as
    # neurons rejected networks the exporter would have built happily.
    real_population_names = facts.real_population_names

    # -- 2. Count total neurons --
    n_neurons = facts.n_neurons_excluding_ports

    if n_neurons > PYNQ_LIMITS.MAX_NEURONS:
        rejections.append(PynqRejectionReason.EXCEEDS_NEURON_CAPACITY)
    elif n_neurons > PYNQ_LIMITS.MAX_NEURONS * 0.8:
        warnings.append(
            f"Network uses {n_neurons}/{PYNQ_LIMITS.MAX_NEURONS} neurons (>{80}% capacity)"
        )

    # -- 3. Estimate synapse count --
    n_synapses = facts.n_synapses_excluding_ports
    max_synapses = PYNQ_LIMITS.max_synapses_for_bit_width(bit_width)
    if n_synapses > max_synapses:
        rejections.append(PynqRejectionReason.EXCEEDS_SYNAPSE_CAPACITY)
    elif max_synapses > 0 and n_synapses > max_synapses * 0.8:
        warnings.append(
            f"Network uses {n_synapses}/{max_synapses} synapses (>{80}% capacity)"
        )

    # -- 3b. Fixed overlay-v1 population contract --
    n_populations = facts.n_populations_excluding_ports
    if n_populations > PYNQ_LIMITS.MAX_POPULATIONS:
        rejections.append(PynqRejectionReason.UNSUPPORTED_TOPOLOGY)

    # -- 4. Estimate memory --
    memory_kb = _estimate_pynq_memory_kb(n_neurons, n_synapses, bit_width)
    if memory_kb > PYNQ_LIMITS.MEMORY_BUDGET_KB:
        rejections.append(PynqRejectionReason.EXCEEDS_MEMORY_BUDGET)
    elif memory_kb > PYNQ_LIMITS.MEMORY_BUDGET_KB * 0.8:
        warnings.append(
            f"Estimated memory {memory_kb:.1f} KB / {PYNQ_LIMITS.MEMORY_BUDGET_KB} KB "
            f"(>{80}% capacity)"
        )

    # -- 5. Check neuron models --
    allowed_models = {m.lower() for m in PYNQ_TOPOLOGY.allowed_neuron_models}
    semantic_roles = {"excitatory", "inhibitory"} | _PORT_POPULATION_TYPES
    for pop in ir.populations.values():
        if (
            pop.population_type
            and pop.population_type.lower() not in semantic_roles
            and pop.population_type.lower() not in allowed_models
        ):
            rejections.append(PynqRejectionReason.UNSUPPORTED_NEURON_MODEL)
            break

    # -- 6. Check learning rules --
    if ir.learning_rules and not PYNQ_TOPOLOGY.allow_learning_rules:
        rejections.append(PynqRejectionReason.UNSUPPORTED_LEARNING_RULE)

    # -- 7. Check recurrent connections --
    if not PYNQ_TOPOLOGY.allow_recurrent and facts.has_recurrent_connections:
        rejections.append(PynqRejectionReason.UNSUPPORTED_TOPOLOGY)

    # -- 8. Check unsupported concepts (lateral inhibition, spatial connectivity) --
    unsupported_concepts = {"lateral_inhibition", "spatial_connectivity"}
    found_unsupported = facts.provenance_concepts & unsupported_concepts
    if found_unsupported and PynqRejectionReason.UNSUPPORTED_TOPOLOGY not in rejections:
        rejections.append(PynqRejectionReason.UNSUPPORTED_TOPOLOGY)

    # Only connections between two real (non-port) populations count as weight
    # matrices — a port feeding into or out of a real population is the fixed
    # DMA path, not a layer.
    #
    # Overlay-v1 could hold exactly one matrix. v2 holds up to MAX_LAYERS, but
    # they must form a single feedforward chain: the engine walks layer 0, 1, 2…
    # in order, handing each layer's spikes to the next. A branch or a merge has
    # nowhere to go.
    connection_pairs = set(facts.real_connection_pairs)
    if len(connection_pairs) > PYNQ_LIMITS.MAX_LAYERS or not _is_linear_chain(
        connection_pairs
    ):
        if PynqRejectionReason.UNSUPPORTED_TOPOLOGY not in rejections:
            rejections.append(PynqRejectionReason.UNSUPPORTED_TOPOLOGY)

    # Each layer's neurons live in a fixed-width on-chip state array, so a
    # single oversized population is rejected even when the total fits.
    oversized = [
        name
        for name in real_population_names
        if facts.population_sizes[name] > PYNQ_LIMITS.MAX_NEURONS_PER_LAYER
    ]
    if oversized:
        rejections.append(PynqRejectionReason.EXCEEDS_NEURON_CAPACITY)
        warnings.append(
            f"Population(s) {', '.join(sorted(oversized))} exceed the "
            f"{PYNQ_LIMITS.MAX_NEURONS_PER_LAYER}-neuron per-layer limit"
        )

    # -- 9. Check weight quantizability --
    # int8 quantisation is lossy by construction, so "quantizable" cannot mean
    # "lands exactly on an integer after scaling" — that is a test almost no
    # trained matrix passes, and it stayed invisible only because PYNQ weights
    # were always zeros (max_abs 0 skipped the loop) or hand-picked literals.
    # Reject what genuinely has no fixed-point image; warn proportionally about
    # the rest. See `quantisation_fidelity`.
    weights = facts.connection_weights_excluding_ports
    if weights:
        from neurocnl.transforms.quantise import quantisation_fidelity

        fidelity = quantisation_fidelity(list(weights), bits=bit_width)
        if not fidelity.representable:
            rejections.append(PynqRejectionReason.WEIGHT_NOT_QUANTIZABLE)
        elif fidelity.collapsed:
            # Some weights round to zero, so those synapses vanish on the board.
            # Deployable, but the user should know before wondering why accuracy
            # dropped.
            warnings.append(
                f"{fidelity.collapsed} of {fidelity.total_nonzero} non-zero weights "
                f"({fidelity.collapsed_fraction * 100:.1f}%) round to zero at "
                f"{bit_width}-bit precision and will not fire on the board"
            )

    # -- Build verdict --
    # De-duplicate rejections
    rejections = list(dict.fromkeys(rejections))

    if rejections:
        support_state = PynqSupportState.NOT_EXPORTABLE
    elif warnings:
        support_state = PynqSupportState.EXPORTABLE_WITH_WARNINGS
    else:
        support_state = PynqSupportState.EXPORTABLE

    return PynqExportResult(
        support_state=support_state,
        rejections=rejections,
        warnings=warnings,
        network_summary={
            "n_neurons": n_neurons,
            "n_synapses": n_synapses,
            "memory_estimate_kb": round(memory_kb, 2),
            "quantization_bits": bit_width,
            # Report the counts the gates above actually used, so the UI's
            # "N neurons · N synapses" line matches the verdict it explains.
            "n_populations": n_populations,
            "n_connections": len(connection_pairs),
            "n_learning_rules": len(ir.learning_rules),
        },
    )
