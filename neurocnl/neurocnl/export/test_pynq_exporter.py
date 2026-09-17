import json
import zipfile
from pathlib import Path

import nengo
import pytest

from neurocnl.contracts.pynq_runtime_artifact_contract import REQUIRED_ARTIFACT_FILES
from neurocnl.export.pynq_exporter import (
    PynqOverlayConfig,
    export_pynq,
    export_pynq_artifact,
)


def _make_feedforward_net() -> nengo.Network:
    with nengo.Network("overlay_v1_net") as net:
        source = nengo.Ensemble(2, 1, label="input")
        sink = nengo.Ensemble(1, 1, label="output")
        nengo.Connection(source.neurons, sink.neurons, transform=[[0.5, -0.5]])
    return net


def test_export_pynq_quantisation() -> None:
    net = _make_feedforward_net()

    config = export_pynq(net, bits=8)

    assert isinstance(config, PynqOverlayConfig)
    assert config.quantisation["bits"] == 8
    assert config.quantisation["scale_factor"] == pytest.approx(254.0)
    assert [conn["weight"] for conn in config.connections] == [127, -127]
    assert config.overlay_id == "snn_overlay_v2"
    assert config.overlay_version == "2.0.0"


def test_export_pynq_accepts_ordinary_float_weights() -> None:
    """Lossy quantisation is the point; it must not be treated as a failure.

    This used to raise: the guard demanded every scaled weight land exactly on an
    integer, which contradicted the `np.round` inside the quantiser and rejected
    any realistic trained matrix. It stayed invisible only because PYNQ weights
    were previously always zeros or hand-picked literals.
    """
    with nengo.Network("ordinary_net") as net:
        source = nengo.Ensemble(2, 1, label="input")
        sink = nengo.Ensemble(1, 1, label="output")
        nengo.Connection(source.neurons, sink.neurons, transform=[[1.0, 0.1234]])

    config = export_pynq(net, bits=8)
    weights = [conn["weight"] for conn in config.connections]
    assert all(isinstance(w, int) for w in weights)
    # 0.1234 * (127 / 1.0) = 15.67 -> 16. Rounded, not rejected, and not lost.
    assert sorted(weights) == [16, 127]


def test_export_pynq_rejects_non_finite_weights() -> None:
    """NaN has no fixed-point image, so this is a genuine refusal."""
    with nengo.Network("nan_net") as net:
        source = nengo.Ensemble(2, 1, label="input")
        sink = nengo.Ensemble(1, 1, label="output")
        nengo.Connection(source.neurons, sink.neurons, transform=[[1.0, float("nan")]])

    with pytest.raises(ValueError, match="non-finite"):
        export_pynq(net, bits=8)


def test_export_pynq_keeps_wide_dynamic_range_weights() -> None:
    """A weight far below the maximum rounds to zero — deployable, not rejected.

    The largest weight always maps to ±127 under max-abs scaling, so a network can
    never lose *every* synapse this way. Small weights individually vanishing is a
    fidelity cost the planner warns about (see
    `test_pynq_deployment_contract.py::TestPlanPynqQuantisation`), not a reason to
    refuse the export.
    """
    with nengo.Network("wide_range_net") as net:
        source = nengo.Ensemble(2, 1, label="input")
        sink = nengo.Ensemble(1, 1, label="output")
        nengo.Connection(source.neurons, sink.neurons, transform=[[100.0, 1e-4]])

    config = export_pynq(net, bits=8)
    weights = sorted(int(conn["weight"]) for conn in config.connections)
    assert weights == [0, 127]


def test_export_pynq_accepts_a_multi_layer_chain() -> None:
    """Overlay-v1 held one weight matrix; v2 holds a chain of them."""
    with nengo.Network("three_layer") as net:
        a = nengo.Ensemble(1, 1, label="a")
        b = nengo.Ensemble(1, 1, label="b")
        c = nengo.Ensemble(1, 1, label="c")
        nengo.Connection(a, b, transform=0.5)
        nengo.Connection(b, c, transform=0.5)

    config = export_pynq(net, bits=8)

    assert len(config.populations) == 3
    assert {(conn["pre"], conn["post"]) for conn in config.connections} == {
        ("a", "b"),
        ("b", "c"),
    }


def test_export_pynq_rejects_more_populations_than_the_overlay_has() -> None:
    with nengo.Network("too_deep") as net:
        ensembles = [nengo.Ensemble(1, 1, label=f"e{i}") for i in range(5)]
        for pre, post in zip(ensembles, ensembles[1:], strict=False):
            nengo.Connection(pre, post, transform=0.5)

    with pytest.raises(ValueError, match="supports at most 4 populations"):
        export_pynq(net, bits=8)


def test_export_pynq_rejects_a_branching_topology() -> None:
    """The engine walks layers in order, so a fan-out has nowhere to go."""
    with nengo.Network("branching") as net:
        a = nengo.Ensemble(1, 1, label="a")
        b = nengo.Ensemble(1, 1, label="b")
        c = nengo.Ensemble(1, 1, label="c")
        nengo.Connection(a, b, transform=0.5)
        nengo.Connection(a, c, transform=0.5)

    with pytest.raises(ValueError, match="branching or merging topology"):
        export_pynq(net, bits=8)


def test_pynq_overlay_config_to_files(tmp_path: Path) -> None:
    config = PynqOverlayConfig(
        network_name="test_net",
        populations=[
            {
                "id": "input",
                "n_neurons": 2,
                "neuron_model": "LIF",
                "params": {"v_threshold": 127},
            },
            {
                "id": "output",
                "n_neurons": 1,
                "neuron_model": "LIF",
                "params": {"v_threshold": 127},
            },
        ],
        connections=[
            {"pre": "input", "post": "output", "weight": 7},
            {"pre": "input", "post": "output", "weight": -4},
            {"pre": "input", "post": "output", "weight": 2},
        ],
        quantisation={"bits": 8, "scale_factor": 127.0},
    )

    config.to_files(tmp_path)

    assert (tmp_path / "overlay_config.json").exists()
    assert (tmp_path / "register_map.json").exists()
    assert (tmp_path / "overlay_manifest.json").exists()
    assert (tmp_path / "weights.bin").exists()

    with open(tmp_path / "overlay_config.json", encoding="utf-8") as handle:
        data = json.load(handle)
        assert data["network_name"] == "test_net"
        assert data["overlay_id"] == "snn_overlay_v2"
        assert len(data["connections"]) == 3

    with open(tmp_path / "weights.bin", "rb") as handle:
        packed_bytes = handle.read()

    assert packed_bytes == bytes([7, 252, 2])


def test_export_pynq_artifact_produces_valid_artifact() -> None:
    net = _make_feedforward_net()
    config, artifact = export_pynq_artifact(net, bits=8)

    assert isinstance(config, PynqOverlayConfig)
    assert artifact.target_device == "PYNQ-Z2"
    assert artifact.weight_bit_width == 8
    assert artifact.overlay_manifest.overlay_id == "snn_overlay_v2"
    assert artifact.total_neurons > 0
    assert artifact.total_synapses >= 0


def test_export_pynq_artifact_writes_to_file(tmp_path: Path) -> None:
    net = _make_feedforward_net()
    out = tmp_path / "deploy.zip"
    export_pynq_artifact(net, output_path=out, bits=8)

    assert out.exists()
    assert out.stat().st_size > 0


def test_export_pynq_artifact_zip_contains_all_required_files(tmp_path: Path) -> None:
    net = _make_feedforward_net()
    out = tmp_path / "deploy.zip"
    export_pynq_artifact(net, output_path=out, bits=8)

    with zipfile.ZipFile(out, "r") as zf:
        names = set(zf.namelist())

    for required in REQUIRED_ARTIFACT_FILES:
        assert required in names, f"Missing required artifact file: {required}"


def test_export_pynq_artifact_register_map_defaults(tmp_path: Path) -> None:
    net = _make_feedforward_net()
    out = tmp_path / "deploy.zip"
    export_pynq_artifact(net, output_path=out, bits=8)

    with zipfile.ZipFile(out, "r") as zf:
        reg_map = json.loads(zf.read("pynq_deploy/register_map.json"))
        overlay_manifest = json.loads(zf.read("pynq_deploy/overlay_manifest.json"))

    # The artifact carries the register map of the overlay it targets, because
    # `PynqRuntimeArtifact` requires the two to be equal and the board drives the
    # engine through these offsets. This used to assert an explicitly unresolved
    # map, which matched only while the overlay was unbuilt: once the v2 build
    # resolved the manifest's offsets from the `.hwh`, every network was rejected
    # with "register_map must match the overlay manifest register map".
    assert reg_map == overlay_manifest["register_map"]
    assert reg_map["dma_channel"] == "axi_dma_0"
    assert overlay_manifest["overlay_id"] == "snn_overlay_v2"
    assert overlay_manifest["overlay_version"] == "2.0.0"
    assert overlay_manifest["max_synapses"] == 262144
    assert overlay_manifest["weight_layout"]["storage"] == "dma_ddr"
    assert overlay_manifest["supported_weight_bit_widths"] == [8]
