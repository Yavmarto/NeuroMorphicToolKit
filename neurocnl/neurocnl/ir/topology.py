from collections import defaultdict, deque

from neurocnl.ir.types import PORT_POPULATION_TYPES, NetworkIR, PopulationIR


def is_io_port(pop: PopulationIR) -> bool:
    """Return True when a population is a declared I/O port, not neurons.

    See ``PORT_POPULATION_TYPES``: NIR-native lowering represents input/output
    ports as populations so they can be named and connected, but they carry no
    neuron model and occupy no hardware neurons. ``role`` is checked as well as
    ``population_type`` because the two are set independently.
    """
    return pop.role in PORT_POPULATION_TYPES or pop.population_type in PORT_POPULATION_TYPES


class NetworkTopologyAnalyzer:
    """Analyzes the structural topology of a NetworkIR for hardware backend constraints."""

    def __init__(self, ir: NetworkIR):
        self.ir = ir
        self.out_edges, self.in_edges = self._build_graph()

    def _graph_nodes(self) -> set[str]:
        nodes = set(self.ir.populations.keys())
        nodes.update(pop.name for pop in self.ir.populations.values())
        for conn in self.ir.connections:
            nodes.add(conn.source)
            nodes.add(conn.target)
        return nodes

    def _build_graph(self) -> tuple[dict[str, list[str]], dict[str, list[str]]]:
        out_edges: dict[str, set[str]] = defaultdict(set)
        in_edges: dict[str, set[str]] = defaultdict(set)

        for node in self._graph_nodes():
            out_edges[node]
            in_edges[node]

        for conn in self.ir.connections:
            out_edges[conn.source].add(conn.target)
            in_edges[conn.target].add(conn.source)
        return (
            {node: sorted(targets) for node, targets in out_edges.items()},
            {node: sorted(sources) for node, sources in in_edges.items()},
        )

    def oversized_population(self, max_size: int = 256) -> tuple[str, int] | None:
        """Return the first neuron population over ``max_size``, or None.

        I/O ports are skipped: they are graph endpoints, not neurons, and there
        is no parameter a user could lower to satisfy the limit — the input
        width is dictated by the dataset.
        """
        for name, pop in self.ir.populations.items():
            if pop.size is None or is_io_port(pop):
                continue
            if pop.size > max_size:
                return (name, pop.size)
        return None

    def check_np_size_constraints(self, max_size: int = 256) -> bool:
        """Returns True if any neuron population size exceeds max_size."""
        return self.oversized_population(max_size) is not None

    # Attributes that are known semantic markers and do not indicate an
    # unsupported or unknown topology feature.
    _SAFE_ATTRIBUTES: frozenset[str] = frozenset({"projection_only", "nir_native"})

    def _has_unknown_topology_features(self) -> bool:
        for conn in self.ir.connections:
            attrs = getattr(conn, "attributes", None)
            if attrs:
                unknown = set(attrs) - self._SAFE_ATTRIBUTES
                if unknown:
                    return True
        return False

    def _non_isolated_nodes(self) -> set[str]:
        return {node for node in self.out_edges if self.out_edges[node] or self.in_edges[node]}

    def _is_weakly_connected(self, nodes: set[str]) -> bool:
        if not nodes:
            return True

        start = next(iter(nodes))
        seen = {start}
        queue = deque([start])

        while queue:
            node = queue.popleft()
            neighbors = set(self.out_edges.get(node, [])) | set(self.in_edges.get(node, []))
            for neighbor in neighbors:
                if neighbor in nodes and neighbor not in seen:
                    seen.add(neighbor)
                    queue.append(neighbor)

        return seen == nodes

    def is_sequential(self) -> bool:
        """
        A topology is sequential if it forms a directed path with no branching,
        no skip connections, and no recurrence.
        Fails closed for any connections with unhandled properties or unexpected structures.
        """
        if self._has_unknown_topology_features():
            return False
        if not self.ir.connections:
            return True

        nodes = self._non_isolated_nodes()
        if not self._is_weakly_connected(nodes):
            return False
        if self.has_recurrent():
            return False

        edge_count = sum(len(edges) for edges in self.out_edges.values())
        if edge_count != len(nodes) - 1:
            return False

        sources = 0
        sinks = 0
        for node in nodes:
            in_degree = len(self.in_edges.get(node, []))
            out_degree = len(self.out_edges.get(node, []))

            if in_degree > 1 or out_degree > 1:
                return False
            if in_degree == 0:
                sources += 1
            if out_degree == 0:
                sinks += 1

        return sources == 1 and sinks == 1

    def has_recurrent(self) -> bool:
        """Returns True if there is a recurrent loop (cycle) in the network."""
        visited: set[str] = set()
        rec_stack: set[str] = set()

        def is_cyclic(node: str) -> bool:
            visited.add(node)
            rec_stack.add(node)
            for neighbor in self.out_edges.get(node, []):
                if neighbor not in visited:
                    if is_cyclic(neighbor):
                        return True
                elif neighbor in rec_stack:
                    return True
            rec_stack.remove(node)
            return False

        for node in self.out_edges:
            if node not in visited:
                if is_cyclic(node):
                    return True

        return False

    def has_unconstrained_random_topology(self) -> bool:
        """
        Heuristic for unconstrained random topology:
        Nodes with many in-edges (>10) as a proxy.
        """
        return any(len(edges) > 10 for edges in self.in_edges.values())

    def has_lateral_inhibitory(self) -> bool:
        """Returns True if there is an inhibitory connection or inhibitory population acting laterally."""
        for conn in self.ir.connections:
            if conn.polarity == "inhibitory":
                return True
            source_pop = self.ir.populations.get(conn.source)
            if source_pop and source_pop.population_type == "inhibitory":
                return True
        return False
