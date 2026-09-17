"""Tests for backend capability profiles."""

from neurocnl.backends import (
    BACKEND_CAPABILITIES,
    BackendCapabilityProfile,
    get_backend_capability,
    list_backend_capabilities,
)
from neurocnl.backends.akida_capabilities import (
    Akida1CapabilityChecker,
    Akida2CapabilityChecker,
)
from neurocnl.ir.topology import NetworkTopologyAnalyzer
from neurocnl.ir.types import ConnectionIR, NetworkIR, PopulationIR


def test_all_expected_backends_exist() -> None:
    assert {
        "nengo",
        "loihi",
        "lava",
        "spinnaker",
        "teensy",
        "akida1",
        "akida2",
    }.issubset(set(BACKEND_CAPABILITIES))


def test_backend_profiles_have_required_shape() -> None:
    for name, profile in BACKEND_CAPABILITIES.items():
        assert isinstance(profile, BackendCapabilityProfile)
        assert profile.name == name
        assert isinstance(profile.neuron_models, frozenset)
        assert isinstance(profile.learning_rules, frozenset)
        assert isinstance(profile.synapse_models, frozenset)
        assert isinstance(profile.concept_support, dict)
        assert profile.unsupported_features


def test_list_backend_capabilities_returns_copy() -> None:
    profiles = list_backend_capabilities()
    assert profiles["nengo"].name == "nengo"
    assert profiles is not BACKEND_CAPABILITIES


def test_get_backend_capability_normalizes_name() -> None:
    assert get_backend_capability(" Loihi ").name == "loihi"


def test_akida1_checker_rejects_branching_topology() -> None:
    ir = NetworkIR(
        populations={
            "a": PopulationIR(name="a", size=10),
            "b": PopulationIR(name="b", size=10),
            "c": PopulationIR(name="c", size=10),
        },
        connections=[ConnectionIR("a", "b"), ConnectionIR("a", "c")],
    )
    assert Akida1CapabilityChecker().check_network_topology(ir) == "unsupported"


def test_akida1_checker_accepts_strict_path() -> None:
    ir = NetworkIR(
        populations={
            "a": PopulationIR(name="a", size=10),
            "b": PopulationIR(name="b", size=10),
            "c": PopulationIR(name="c", size=10),
        },
        connections=[ConnectionIR("a", "b"), ConnectionIR("b", "c")],
    )
    assert Akida1CapabilityChecker().check_network_topology(ir) == "faithful"


def test_akida2_checker_marks_cycles_approximate() -> None:
    ir = NetworkIR(
        populations={
            "a": PopulationIR(name="a", size=10),
            "b": PopulationIR(name="b", size=10),
        },
        connections=[ConnectionIR("a", "b"), ConnectionIR("b", "a")],
    )
    assert Akida2CapabilityChecker().check_network_topology(ir) == "approximate"


def test_akida1_checker_rejects_unknown_connection_attributes() -> None:
    ir = NetworkIR(
        populations={
            "a": PopulationIR(name="a", size=10),
            "b": PopulationIR(name="b", size=10),
            "c": PopulationIR(name="c", size=10),
        },
        connections=[
            ConnectionIR("a", "b"),
            # Must be an attribute outside _SAFE_ATTRIBUTES: "projection_only"
            # was moved into that set, which left this test asserting the
            # opposite of what its name says.
            ConnectionIR("b", "c", attributes={"spatial_kernel": (3, 3)}),
        ],
    )
    assert Akida1CapabilityChecker().check_network_topology(ir) == "unsupported"


def test_akida1_checker_accepts_known_safe_connection_attributes() -> None:
    ir = NetworkIR(
        populations={
            "a": PopulationIR(name="a", size=10),
            "b": PopulationIR(name="b", size=10),
            "c": PopulationIR(name="c", size=10),
        },
        connections=[
            ConnectionIR("a", "b"),
            ConnectionIR("b", "c", attributes={"projection_only": True}),
        ],
    )
    assert Akida1CapabilityChecker().check_network_topology(ir) == "faithful"


def _mnist_fcn_ir(hidden: int) -> NetworkIR:
    """The guide's Model canvas: Input(784) -> LIF(hidden) -> LIF(10) -> Output."""
    return NetworkIR(
        populations={
            "inp": PopulationIR(
                name="inp",
                size=784,
                shape=(784,),
                role="input",
                population_type="input",
            ),
            "lif1": PopulationIR(name="lif1", size=hidden, population_type="lif"),
            "lif2": PopulationIR(name="lif2", size=10, population_type="lif"),
            "out": PopulationIR(
                name="out",
                size=10,
                shape=(10,),
                role="output",
                population_type="output",
            ),
        },
        connections=[
            ConnectionIR("inp", "lif1"),
            ConnectionIR("lif1", "lif2"),
            ConnectionIR("lif2", "out"),
        ],
    )


def test_io_ports_do_not_count_against_the_per_np_limit() -> None:
    """A 784-wide MNIST input port is I/O, not neurons.

    Counting it made every MNIST network unsupported no matter how narrow the
    hidden layer was, and named no parameter the user could lower.
    """
    ir = _mnist_fcn_ir(hidden=256)
    assert Akida1CapabilityChecker().check_network_topology(ir) == "faithful"
    assert Akida2CapabilityChecker().check_network_topology(ir) == "faithful"


def test_oversized_hidden_layer_is_still_rejected_and_named() -> None:
    ir = _mnist_fcn_ir(hidden=1000)
    assert Akida1CapabilityChecker().check_network_topology(ir) == "unsupported"

    analyzer = NetworkTopologyAnalyzer(ir)
    assert analyzer.oversized_population(256) == ("lif1", 1000)
