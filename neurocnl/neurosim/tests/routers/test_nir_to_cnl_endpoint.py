"""Tests for the .nir upload -> CNL endpoint."""

from __future__ import annotations

from pathlib import Path

from fastapi.testclient import TestClient

from neurosim.app.main import app

client = TestClient(app)


def test_generate_cnl_from_nir_upload_returns_cnl(tmp_path: Path) -> None:
    import nir
    import numpy as np

    graph = nir.NIRGraph(
        nodes={
            "inp": nir.Input(input_type={"input": np.array([4])}),
            "pop_a": nir.LIF(
                tau=np.full(4, 0.02),
                r=np.full(4, 1.0),
                v_leak=np.full(4, 0.0),
                v_threshold=np.full(4, 1.0),
            ),
            "out": nir.Output(output_type={"output": np.array([4])}),
        },
        edges=[("inp", "pop_a"), ("pop_a", "out")],
    )
    nir_path = tmp_path / "network.nir"
    nir.write(str(nir_path), graph)

    with nir_path.open("rb") as handle:
        response = client.post(
            "/api/neurosim/generate-cnl-from-nir",
            content=handle.read(),
            headers={"Content-Type": "application/octet-stream"},
        )

    assert response.status_code == 200
    body = response.json()
    assert "cnl_text" in body
    assert "pop_a" in body["cnl_text"]


def test_generate_cnl_from_nir_upload_rejects_unsupported_graph(tmp_path: Path) -> None:
    """The 422 path fires when the renderer encounters a primitive type not in
    primitive_phrases.  All 18 current NIR primitives are supported, so we
    temporarily remove CubaLIF from the support table to exercise this path."""
    from unittest.mock import patch

    import nir
    import numpy as np

    from neurocnl.nir_cnl import grammar_tables

    graph = nir.NIRGraph(
        nodes={
            "input": nir.Input(input_type={"input": np.array([1])}),
            "cuba": nir.CubaLIF(
                tau_syn=np.array([0.01]),
                tau_mem=np.array([0.02]),
                r=np.array([1.0]),
                v_leak=np.array([0.0]),
                v_threshold=np.array([1.0]),
                input_type={"input": np.array([1])},
                output_type={"output": np.array([1])},
            ),
            "output": nir.Output(output_type={"output": np.array([1])}),
        },
        edges=[("input", "cuba"), ("cuba", "output")],
        type_check=False,
    )
    nir_path = tmp_path / "unsupported.nir"
    nir.write(str(nir_path), graph)

    restricted = {
        k: v for k, v in grammar_tables.primitive_phrases.items() if k != "CubaLIF"
    }
    with (
        patch.dict(grammar_tables.primitive_phrases, restricted, clear=True),
        nir_path.open("rb") as handle,
    ):
        response = client.post(
            "/api/neurosim/generate-cnl-from-nir",
            content=handle.read(),
            headers={"Content-Type": "application/octet-stream"},
        )

    assert response.status_code == 422
    detail = response.json()["detail"]
    assert detail["code"] == "unsupported_nir_import"
    assert any("CubaLIF" in d["message"] for d in detail["diagnostics"])
