import nengo

from neurocnl.export.spinnaker2_exporter import export_spinnaker2


def test_export_spinnaker2_basic() -> None:
    with nengo.Network(label="TestNet") as net:
        ens_a = nengo.Ensemble(10, dimensions=1, label="pop_a")
        ens_b = nengo.Ensemble(20, dimensions=1, label="pop_b")
        nengo.Connection(ens_a, ens_b)

    code = export_spinnaker2(net)

    assert "import nengo" not in code
    assert "from spinnaker2 import snn, hardware" in code
    assert 'net = snn.Network("neurocnl_network")' in code
    assert "pop_a = snn.Population(" in code
    assert "pop_b = snn.Population(" in code
    assert "size=10" in code
    assert "size=20" in code
    assert 'neuron_model="lif"' in code
    assert "hw = hardware.SpiNNaker2Chip()" in code
    assert "hw.run(net, timesteps)" in code
    assert "pop_a_spikes = pop_a.get_spikes()" in code
    assert "net.add(pop_a)" in code
    assert "net.add(pop_b)" in code
    assert "net.add(proj_0)" in code
    assert "snn.FromListConnector" in code
    assert "weight_lookup_proj_0" in code


def test_export_spinnaker2_explicit_list() -> None:
    import numpy as np

    with nengo.Network(label="TestNetExplicit") as net:
        ens_a = nengo.Ensemble(2, dimensions=2, label="pop_a")
        ens_b = nengo.Ensemble(2, dimensions=2, label="pop_b")
        # Custom transform matrix to force explicit connection list
        nengo.Connection(ens_a, ens_b, transform=np.array([[1.0, 0.5], [0.2, 1.0]]))

    code = export_spinnaker2(net)
    assert "snn.FromListConnector" in code
    assert (
        "weight_lookup_proj_0 = np.array([[1.0, 0.5], [0.2, 1.0]], dtype=float)" in code
    )
    assert (
        "scaled_weight = int(round(weight_lookup_proj_0[post_dim, pre_dim] * 10))"
        in code
    )
