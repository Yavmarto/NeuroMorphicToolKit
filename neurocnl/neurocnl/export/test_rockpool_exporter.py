from pathlib import Path

import nengo
import nir
import pytest

from neurocnl.converter.rockpool_io import RockpoolIO
from neurocnl.export.rockpool_exporter import export_to_rockpool


def test_export_to_rockpool_uses_nir_conversion(
    monkeypatch: pytest.MonkeyPatch, tmp_path: Path
) -> None:
    captured = {}

    def fake_from_nir(self: RockpoolIO, graph: nir.NIRGraph, **kwargs: object) -> str:
        captured["graph"] = graph
        return "converted-rockpool"

    monkeypatch.setattr(RockpoolIO, "from_nir", fake_from_nir)

    with nengo.Network(label="rockpool_test") as net:
        source = nengo.Ensemble(10, 1, label="source")
        target = nengo.Ensemble(10, 1, label="target")
        nengo.Connection(source, target, transform=0.5)

    output = export_to_rockpool(net, filename=tmp_path / "model.nir")

    assert output == "converted-rockpool"
    assert "graph" in captured
    assert len(captured["graph"].nodes) > 0
