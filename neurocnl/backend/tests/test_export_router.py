"""Tests for the /api/export endpoint — NIR-native CNL contract."""

from pathlib import Path
from unittest.mock import MagicMock, mock_open, patch

import pytest
from fastapi.testclient import TestClient

from backend.app.main import app

client = TestClient(app)

# The canonical reflex-arc template is already in NIR-native format.
VALID_SPEC = (
    Path(__file__).resolve().parent.parent / "app" / "templates" / "reflex_arc.cnl"
).read_text()


# ---------------------------------------------------------------------------
# CNL export — returns spec verbatim
# ---------------------------------------------------------------------------


@pytest.mark.asyncio(loop_scope="function")
async def test_export_cnl():
    resp = client.post(
        "/api/export",
        json={"spec": VALID_SPEC, "format": "cnl", "filename": "test.cnl"},
    )
    assert resp.status_code == 200
    assert resp.text == VALID_SPEC
    assert 'attachment; filename="test.cnl"' in resp.headers["Content-Disposition"]


# ---------------------------------------------------------------------------
# HTML export — structured report
# ---------------------------------------------------------------------------


@pytest.mark.asyncio(loop_scope="function")
async def test_export_html_success():
    payload = {
        "spec": VALID_SPEC,
        "format": "html",
        "validation_summary": {
            "overall": True,
            "layer1": {"passed": [{"name": "Inv1", "description": "Desc1"}]},
            "layer2": {"checks_passed": ["Check1"], "neurons_found": ["N1"]},
            "backend_support": {
                "backend": "nir",
                "verdict": "faithful",
                "warnings": [],
            },
        },
        "network_summary": {
            "nodes": [{"id": 1, "type": "T1", "label": "L1"}],
            "edges": [{"source": 1, "target": 2, "params": {"transform": 1.0}}],
        },
        "simulation_summary": {"sensor_spike_count": 10},
    }
    resp = client.post("/api/export", json=payload)
    assert resp.status_code == 200
    assert "text/html" in resp.headers["Content-Type"]
    content = resp.text
    assert '<h2>Validation <span style="color:#22c55e">PASSED</span></h2>' in content
    assert "<h3>Layer 1: Biophysical Invariants</h3>" in content
    assert "<h3>Layer 2: Cross-Reference Checks</h3>" in content
    assert "<h2>Backend Support</h2>" in content
    assert "<h2>Network Topology</h2>" in content


@pytest.mark.asyncio(loop_scope="function")
async def test_export_html_failure():
    payload = {
        "spec": VALID_SPEC,
        "format": "html",
        "validation_summary": {"overall": False},
    }
    resp = client.post("/api/export", json=payload)
    assert resp.status_code == 200
    assert '<h2>Validation <span style="color:#ef4444">FAILED</span></h2>' in resp.text


# ---------------------------------------------------------------------------
# NIR export — binary HDF5 artifact
# ---------------------------------------------------------------------------


@pytest.mark.asyncio(loop_scope="function")
async def test_export_nir_success():
    """NIR export with a mocked compile_to_nir returns correct MIME, filename, and mock was called."""
    with (
        patch("backend.app.routers.export.compile_to_nir") as mock_compile,
        patch("backend.app.routers.export.Path") as mock_path,
        patch("builtins.open", mock_open(read_data=b"\x89HDF\r\n\x1a\n")),
    ):
        mock_compile.return_value = MagicMock()
        mock_path_inst = MagicMock()
        mock_path.return_value = mock_path_inst
        mock_path_inst.exists.return_value = True

        resp = client.post("/api/export", json={"spec": VALID_SPEC, "format": "nir"})

        assert resp.status_code == 200
        assert resp.content == b"\x89HDF\r\n\x1a\n"
        assert "application/octet-stream" in resp.headers["Content-Type"]
        assert 'attachment; filename="network.nir"' in resp.headers["Content-Disposition"]
        assert mock_compile.called
        assert mock_path_inst.unlink.called


@pytest.mark.asyncio(loop_scope="function")
async def test_export_nir_real_returns_faithful_verdict():
    """Real NIR export of a NIR-native spec returns verdict=faithful and advisory=absent."""
    resp = client.post("/api/export", json={"spec": VALID_SPEC, "format": "nir"})
    assert resp.status_code == 200
    assert resp.headers["X-NeuroCNL-Backend-Verdict"] == "faithful"
    assert resp.headers["X-NeuroCNL-NIR-Advisory-Semantics"] == "absent"
    assert resp.headers["X-NeuroCNL-Backend-Warning-Count"] == "0"


@pytest.mark.asyncio(loop_scope="function")
async def test_export_nir_failure():
    """A compile_to_nir exception returns 500 export_failed."""
    with (
        patch(
            "backend.app.routers.export.compile_to_nir",
            side_effect=Exception("NIR error"),
        ),
        patch("backend.app.routers.export.Path") as mock_path,
    ):
        mock_path_inst = MagicMock()
        mock_path.return_value = mock_path_inst
        mock_path_inst.exists.return_value = True

        resp = client.post("/api/export", json={"spec": VALID_SPEC, "format": "nir"})

        assert resp.status_code == 500
        detail = resp.json()["detail"]
        assert detail["error"] == "export_failed"
        assert "NIR error" in detail["messages"][0]
        assert mock_path_inst.unlink.called


@pytest.mark.asyncio(loop_scope="function")
async def test_export_nir_parse_error():
    """An invalid spec returns 400 parse_failed before attempting to compile."""
    resp = client.post("/api/export", json={"spec": "INVALID", "format": "nir"})
    assert resp.status_code == 400
    detail = resp.json()["detail"]
    assert detail["error"] == "parse_failed"
    assert detail["items"][0]["code"] is not None
    assert detail["items"][0]["message"] is not None
    assert detail["items"][0]["line"] == 1


@pytest.mark.asyncio(loop_scope="function")
async def test_export_nir_no_valid_sentences():
    """Whitespace-only spec returns 422 validation_failed."""
    resp = client.post("/api/export", json={"spec": "   ", "format": "nir"})
    assert resp.status_code == 422
    detail = resp.json()["detail"]
    assert detail["error"] == "validation_failed"
    assert detail["messages"] == ["No valid CNL sentences found."]
    assert detail["items"][0]["code"] == "no_valid_cnl_sentences"


# ---------------------------------------------------------------------------
# SNN-MLIR export — text artifact via the snn-mlir package
# ---------------------------------------------------------------------------


@pytest.mark.asyncio(loop_scope="function")
async def test_export_mlir_success():
    """MLIR export with mocked compile_to_nir/generate_mlir returns correct MIME and filename."""
    with (
        patch("backend.app.routers.export.compile_to_nir") as mock_compile,
        patch("backend.app.routers.export.Path") as mock_path,
        patch(
            "neurocnl.generation.snn_mlir_generator.generate_mlir",
            return_value="module {}\n",
        ) as mock_generate,
    ):
        mock_compile.return_value = MagicMock()
        mock_path_inst = MagicMock()
        mock_path.return_value = mock_path_inst
        mock_path_inst.exists.return_value = True

        resp = client.post("/api/export", json={"spec": VALID_SPEC, "format": "mlir"})

        assert resp.status_code == 200
        assert resp.text == "module {}\n"
        assert "text/plain" in resp.headers["Content-Type"]
        assert 'attachment; filename="network.mlir"' in resp.headers["Content-Disposition"]
        assert mock_compile.called
        assert mock_generate.called
        assert mock_path_inst.unlink.called


@pytest.mark.asyncio(loop_scope="function")
async def test_export_mlir_unsupported_topology_returns_400():
    """A RuntimeError from generate_mlir (e.g. recurrent topology) returns 400, not 500."""
    with (
        patch("backend.app.routers.export.compile_to_nir") as mock_compile,
        patch("backend.app.routers.export.Path") as mock_path,
        patch(
            "neurocnl.generation.snn_mlir_generator.generate_mlir",
            side_effect=RuntimeError("snn-mlir failed to lower NIR graph: recurrent connection"),
        ),
    ):
        mock_compile.return_value = MagicMock()
        mock_path_inst = MagicMock()
        mock_path.return_value = mock_path_inst
        mock_path_inst.exists.return_value = True

        resp = client.post("/api/export", json={"spec": VALID_SPEC, "format": "mlir"})

        assert resp.status_code == 400
        assert mock_path_inst.unlink.called


@pytest.mark.asyncio(loop_scope="function")
async def test_export_mlir_parse_error():
    """An invalid spec returns 400 parse_failed before attempting to compile."""
    resp = client.post("/api/export", json={"spec": "INVALID", "format": "mlir"})
    assert resp.status_code == 400
    detail = resp.json()["detail"]
    assert detail["error"] == "parse_failed"


# ---------------------------------------------------------------------------
# Legacy framework exports — all return 410 Gone
# ---------------------------------------------------------------------------


@pytest.mark.parametrize("format", ["neuroml", "c_header", "loihi", "lava", "spinnaker"])
@pytest.mark.asyncio(loop_scope="function")
async def test_export_legacy_frameworks_return_410(format):
    resp = client.post("/api/export", json={"spec": VALID_SPEC, "format": format})
    assert resp.status_code == 410
    detail = resp.json()["detail"]
    assert detail["error"] == "legacy_export_removed"
    assert detail["items"][0]["hint"]


@pytest.mark.asyncio(loop_scope="function")
async def test_export_unsupported_format():
    resp = client.post("/api/export", json={"spec": VALID_SPEC, "format": "unsupported_format"})
    assert resp.status_code == 400
    detail = resp.json()["detail"]
    assert detail["error"] == "unsupported_export_format"
    assert "Unsupported export format" in detail["messages"][0]


# ---------------------------------------------------------------------------
# HTML edge cases
# ---------------------------------------------------------------------------


@pytest.mark.asyncio(loop_scope="function")
async def test_export_html_complex_failure():
    payload = {
        "spec": VALID_SPEC,
        "format": "html",
        "validation_summary": {
            "overall": False,
            "layer1": {"failed": [{"name": "Fail1", "description": "Desc1"}]},
            "layer2": {"checks_failed": ["CheckFail1"]},
        },
    }
    resp = client.post("/api/export", json=payload)
    assert resp.status_code == 200
    assert 'color:#ef4444">✗' in resp.text
    assert "CheckFail1" in resp.text


# ---------------------------------------------------------------------------
# Export preflight — returns backend_support verdict without generating artifacts
# ---------------------------------------------------------------------------


@pytest.mark.asyncio(loop_scope="function")
async def test_export_preflight_valid_spec_returns_verdict():
    """Preflight on a valid NIR-native spec returns JSON backend_support with a verdict."""
    resp = client.post(
        "/api/export/preflight",
        json={"spec": VALID_SPEC, "format": "nir"},
    )
    assert resp.status_code == 200
    assert "application/json" in resp.headers["Content-Type"]
    assert "Content-Disposition" not in resp.headers
    data = resp.json()
    bs = data["backend_support"]
    assert bs is not None
    assert bs["backend"] == "nir"
    assert bs["verdict"] in {"faithful", "approximate", "unsupported"}


@pytest.mark.asyncio(loop_scope="function")
async def test_export_preflight_invalid_spec_returns_unsupported():
    """Preflight on an invalid spec returns 200 with verdict='unsupported' (no 4xx)."""
    resp = client.post(
        "/api/export/preflight",
        json={"spec": "NOT VALID CNL", "format": "nir"},
    )
    assert resp.status_code == 200
    data = resp.json()
    bs = data["backend_support"]
    assert bs["verdict"] == "unsupported"
    assert len(bs["warnings"]) > 0


@pytest.mark.asyncio(loop_scope="function")
async def test_export_preflight_empty_spec_returns_unsupported():
    """Preflight on whitespace-only spec returns 200 with verdict='unsupported'."""
    resp = client.post(
        "/api/export/preflight",
        json={"spec": "   ", "format": "nir"},
    )
    assert resp.status_code == 200
    data = resp.json()
    bs = data["backend_support"]
    assert bs["verdict"] == "unsupported"
    assert len(bs["warnings"]) > 0


@pytest.mark.asyncio(loop_scope="function")
async def test_export_preflight_unknown_format_returns_unsupported():
    """Preflight with an unrecognised backend format returns 200 with verdict='unsupported'."""
    resp = client.post(
        "/api/export/preflight",
        json={"spec": VALID_SPEC, "format": "unknown_backend"},
    )
    assert resp.status_code == 200
    data = resp.json()
    bs = data["backend_support"]
    assert bs["verdict"] == "unsupported"
    assert len(bs["warnings"]) > 0


@pytest.mark.asyncio(loop_scope="function")
async def test_export_preflight_lowering_error_returns_unsupported():
    """Preflight with a LoweringError returns 200 with verdict='unsupported'."""
    from unittest.mock import patch

    from neurocnl.ir import LoweringError as _LoweringError

    with patch(
        "backend.app.routers.export.lower_to_ir",
        side_effect=_LoweringError("mock lowering failure"),
    ):
        resp = client.post(
            "/api/export/preflight",
            json={"spec": VALID_SPEC, "format": "nir"},
        )
    assert resp.status_code == 200
    data = resp.json()
    bs = data["backend_support"]
    assert bs["verdict"] == "unsupported"
    assert "mock lowering failure" in bs["warnings"][0]
