"""NeuroCNL → Neurochip Teensy handoff mapper.

Maps a validated ``NetworkIR`` into the exact payload that Neurochip's
``NetworkInput`` schema expects for Teensy firmware generation.

Fail-closed: raises ``TeensyHandoffRejectedError`` when the network is
not deployable, carrying the full ``TeensyDeploymentResult`` with all
rejection reasons.

Deterministic: population and connection ordering is sorted so repeated
calls on the same IR always produce identical payloads.
"""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass, field
from typing import Any

from neurocnl.contracts.teensy_deployment_contract import (
    TeensyDeployabilityVerdict,
    TeensyDeploymentResult,
)
from neurocnl.ir.types import NetworkIR, SourceProvenance
from neurocnl.planner import _DEFAULT_POPULATION_SIZE, plan_teensy_deployability

# ---------------------------------------------------------------------------
# Exceptions
# ---------------------------------------------------------------------------


class TeensyHandoffRejectedError(Exception):
    """Raised when the network fails the Teensy deployability gate.

    Attributes
    ----------
    deployment_result : TeensyDeploymentResult
        Full result including verdict, rejection reasons, and warnings.
    """

    def __init__(self, deployment_result: TeensyDeploymentResult) -> None:
        self.deployment_result = deployment_result
        reasons = ", ".join(r.value for r in deployment_result.rejections)
        super().__init__(f"Network not deployable to Teensy: {reasons}")


# ---------------------------------------------------------------------------
# Provenance tracking
# ---------------------------------------------------------------------------


@dataclass(slots=True)
class HandoffProvenance:
    """Provenance summary attached to the handoff payload.

    Tracks the NeuroCNL source lines and concepts that contributed to
    each population and connection in the output payload.
    """

    populations: dict[str, list[dict[str, Any]]] = field(default_factory=dict)
    connections: list[dict[str, Any]] = field(default_factory=list)
    metadata: dict[str, Any] = field(default_factory=dict)


# ---------------------------------------------------------------------------
# Handoff result
# ---------------------------------------------------------------------------


@dataclass(slots=True)
class HandoffResult:
    """Outcome of a successful NeuroCNL → Neurochip Teensy handoff.

    Attributes
    ----------
    payload : dict
        Dict whose keys match the ``NetworkInput`` Pydantic schema in
        ``Neurochip/neurochip/app/schemas/estimation.py``.
    provenance : HandoffProvenance
        Source provenance for every element in the payload.
    deployment_result : TeensyDeploymentResult
        The full deployability assessment (``DEPLOYABLE`` or
        ``DEPLOYABLE_WITH_WARNINGS``).
    """

    payload: dict[str, Any]
    provenance: HandoffProvenance
    deployment_result: TeensyDeploymentResult


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _provenance_to_dict(prov: SourceProvenance) -> dict[str, Any]:
    return {
        "line": prov.line,
        "raw": prov.raw,
        "concept": prov.concept,
    }


def _collect_provenance(ir: NetworkIR) -> HandoffProvenance:
    populations: dict[str, list[dict[str, Any]]] = {}
    for name in sorted(ir.populations):
        pop = ir.populations[name]
        populations[name] = [_provenance_to_dict(p) for p in pop.provenance]

    connections: list[dict[str, Any]] = []
    for conn in sorted(ir.connections, key=lambda c: (c.source, c.target)):
        connections.append(
            {
                "source": conn.source,
                "target": conn.target,
                "provenance": [_provenance_to_dict(p) for p in conn.provenance],
            }
        )

    metadata: dict[str, Any] = {}
    for prov in ir.metadata.get("provenance", []):
        concept = getattr(prov, "concept", None)
        if concept:
            metadata.setdefault("concepts", []).append(concept)

    return HandoffProvenance(
        populations=populations,
        connections=connections,
        metadata=metadata,
    )


def _compute_network_depth(ir: NetworkIR) -> int:
    """Compute network depth as the longest path from any root population.

    Roots are populations with no incoming connections.  Uses BFS with
    longest-path tracking to find the maximum depth.

    Returns ``max(1, depth)`` so a single-population network has depth 1.
    """
    if not ir.populations:
        return 1

    # Build adjacency and in-degree
    adjacency: dict[str, list[str]] = {name: [] for name in ir.populations}
    in_degree: dict[str, int] = dict.fromkeys(ir.populations, 0)
    for conn in ir.connections:
        if conn.source in adjacency and conn.target in adjacency:
            adjacency[conn.source].append(conn.target)
            in_degree[conn.target] = in_degree.get(conn.target, 0) + 1

    # Roots: populations with no incoming edges
    roots = [name for name in sorted(ir.populations) if in_degree[name] == 0]
    if not roots:
        # All populations have incoming edges (shouldn't happen in a valid
        # feedforward network, but handle gracefully).
        return len(ir.populations)

    # BFS longest-path (topological order, since feedforward is a DAG)
    depth: dict[str, int] = dict.fromkeys(ir.populations, 0)
    queue: deque[str] = deque(roots)
    for root in roots:
        depth[root] = 1

    visited_order: list[str] = []
    remaining_in = dict(in_degree)

    for root in roots:
        remaining_in[root] = 0

    queue = deque(roots)
    while queue:
        node = queue.popleft()
        visited_order.append(node)
        for neighbor in sorted(adjacency[node]):
            depth[neighbor] = max(depth[neighbor], depth[node] + 1)
            remaining_in[neighbor] -= 1
            if remaining_in[neighbor] == 0:
                queue.append(neighbor)

    return max(1, max(depth.values()) if depth else 1)


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def map_network_ir_to_teensy_payload(
    ir: NetworkIR,
    weight_bit_width: int = 32,
) -> HandoffResult:
    """Map a validated ``NetworkIR`` to a Neurochip ``NetworkInput`` payload.

    Parameters
    ----------
    ir : NetworkIR
        Intermediate representation produced by the NeuroCNL pipeline.
    weight_bit_width : int
        Weight quantization bit-width (8, 16, or 32).

    Returns
    -------
    HandoffResult
        Payload dict, provenance, and deployment assessment.

    Raises
    ------
    TeensyHandoffRejectedError
        If the network fails the Teensy deployability gate (verdict is
        ``NOT_DEPLOYABLE``).  The error carries the full
        ``TeensyDeploymentResult``.
    """
    # -- 1. Fail-closed gate -------------------------------------------------
    deployment_result = plan_teensy_deployability(ir)
    if deployment_result.verdict == TeensyDeployabilityVerdict.NOT_DEPLOYABLE:
        raise TeensyHandoffRejectedError(deployment_result)

    # -- 2. Population mapping (sorted for determinism) ----------------------
    populations: list[dict[str, Any]] = []
    num_neurons = 0
    pop_sizes: dict[str, int] = {}

    for name in sorted(ir.populations):
        pop = ir.populations[name]
        size = pop.size if pop.size else _DEFAULT_POPULATION_SIZE
        populations.append({"name": name, "size": size})
        pop_sizes[name] = size
        num_neurons += size

    # -- 3. Connection mapping (sorted for determinism) ----------------------
    connections: list[dict[str, Any]] = []
    num_synapses = 0

    for conn in sorted(ir.connections, key=lambda c: (c.source, c.target)):
        pre_size = pop_sizes.get(conn.source, _DEFAULT_POPULATION_SIZE)
        post_size = pop_sizes.get(conn.target, _DEFAULT_POPULATION_SIZE)
        weight_count = pre_size * post_size
        connections.append(
            {
                "pre": conn.source,
                "post": conn.target,
                "weight_count": weight_count,
            }
        )
        num_synapses += weight_count

    # -- 4. Neuron model (validated upstream as LIF) -------------------------
    neuron_model = "LIF"

    # -- 5. Network depth ----------------------------------------------------
    network_depth = _compute_network_depth(ir)

    # -- 6. Assemble payload matching NetworkInput schema ---------------------
    payload: dict[str, Any] = {
        "num_neurons": num_neurons,
        "num_synapses": num_synapses,
        "neuron_model": neuron_model,
        "populations": populations,
        "connections": connections,
        "weight_bit_width": weight_bit_width,
        "network_depth": network_depth,
    }

    # -- 7. Provenance -------------------------------------------------------
    provenance = _collect_provenance(ir)

    return HandoffResult(
        payload=payload,
        provenance=provenance,
        deployment_result=deployment_result,
    )
