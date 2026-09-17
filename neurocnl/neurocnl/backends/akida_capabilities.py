"""Shared topology checks for Akida capability planning and validation."""

from __future__ import annotations

from neurocnl.ir import NetworkIR
from neurocnl.ir.topology import NetworkTopologyAnalyzer


def _has_high_in_degree(in_edges: dict[str, list[str]], max_in_edges: int) -> bool:
    return any(len(edges) > max_in_edges for edges in in_edges.values())


class Akida1CapabilityChecker:
    """Topology classifier for Akida 1's strict sequential subset."""

    def check_network_topology(self, ir: NetworkIR) -> str:
        analyzer = NetworkTopologyAnalyzer(ir)

        if analyzer.check_np_size_constraints(256):
            return "unsupported"

        if ir.akida_connection_properties:
            return "unsupported"

        if analyzer.has_lateral_inhibitory():
            return "unsupported"

        if not analyzer.is_sequential():
            return "unsupported"

        return "faithful"


class Akida2CapabilityChecker:
    """Topology classifier for Akida 2's documented subset."""

    def check_network_topology(self, ir: NetworkIR) -> str:
        analyzer = NetworkTopologyAnalyzer(ir)

        if analyzer.check_np_size_constraints(256):
            return "unsupported"

        if _has_high_in_degree(analyzer.in_edges, max_in_edges=10):
            return "unsupported"

        if analyzer.has_recurrent():
            return "approximate"

        return "faithful"
