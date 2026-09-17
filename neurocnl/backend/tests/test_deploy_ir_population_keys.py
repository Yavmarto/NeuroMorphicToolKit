"""The deploy IR must key populations the way connections name them.

``PopulationIR`` and ``ConnectionIR`` both lower-case their identifiers, so a
populations dict keyed by the raw CNL name is unreachable from a connection.
Every consumer looks populations up *through* a connection endpoint, so the
mismatch is silent: ports stop being recognised as ports and sizes read as zero.
An MNIST 784→256→10 network was reported to the user as "4 layers … 0×0 → 0×0 →
0×0 → 0×0", which is neither its layer count nor its shapes.
"""

from __future__ import annotations

from backend.app.services.neurocnl_bridge import _nir_native_records_to_deploy_ir
from neurocnl.planner import _is_port_population

MNIST_SPEC = """Define a network named graph.
Define an input port named nir.Input_1 with shape (784,).
Define a LIF neuron named nir.LIF_1 with time constant 0.002, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.
Define a linear transformation named nir.Linear_1 with weight matrix shape (256, 784).
Define a LIF neuron named nir.LIF_2 with time constant 0.002, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.
Define a linear transformation named nir.Linear_2 with weight matrix shape (10, 256).
Define a LIF neuron named nir.LIF_3 with time constant 0.002, resistance 1.0, leak voltage 0.0, and firing threshold 1.0.
Define an output port named nir.Output_1 with shape (10,).

nir.Input_1 connects to nir.LIF_1.
nir.LIF_1 connects to nir.Linear_1.
nir.Linear_1 connects to nir.LIF_2.
nir.LIF_2 connects to nir.Linear_2.
nir.Linear_2 connects to nir.LIF_3.
nir.LIF_3 connects to nir.Output_1.
"""


def test_every_connection_endpoint_resolves_to_a_population() -> None:
    ir = _nir_native_records_to_deploy_ir(MNIST_SPEC)

    for connection in ir.connections:
        assert ir.populations.get(connection.source) is not None, connection.source
        assert ir.populations.get(connection.target) is not None, connection.target


def test_port_populations_are_recognised_through_their_connections() -> None:
    """Unreachable populations made every connection look like a weight matrix."""
    ir = _nir_native_records_to_deploy_ir(MNIST_SPEC)

    layers = [
        connection
        for connection in ir.connections
        if not (
            _is_port_population(ir.populations.get(connection.source))
            or _is_port_population(ir.populations.get(connection.target))
        )
    ]

    # Two weight matrices, not four: the input and output ports are streamed.
    assert [(c.source, c.target) for c in layers] == [
        ("nir.lif_1", "nir.lif_2"),
        ("nir.lif_2", "nir.lif_3"),
    ]


def test_layer_shapes_match_the_declared_weight_matrices() -> None:
    ir = _nir_native_records_to_deploy_ir(MNIST_SPEC)
    shapes = [
        (
            ir.populations[connection.target].size,
            ir.populations[connection.source].size,
        )
        for connection in ir.connections
        if not (
            _is_port_population(ir.populations.get(connection.source))
            or _is_port_population(ir.populations.get(connection.target))
        )
    ]

    assert shapes == [(256, 784), (10, 256)]
