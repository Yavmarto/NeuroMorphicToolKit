"""End-to-end pipeline tests through the FastAPI backend.

Tests the full parse → validate → generate → export flow via TestClient
and the direct NIR-native compile path.  Proves that the backend exercises
real parser/validator/compiler code — not mocked core logic.
"""

from __future__ import annotations

from pathlib import Path

import pytest

REFLEX_ARC_SPEC = (
    Path(__file__).resolve().parent.parent / "app" / "templates" / "reflex_arc.cnl"
).read_text()


# ---------------------------------------------------------------------------
# API-level E2E: parse → validate → export
# ---------------------------------------------------------------------------


@pytest.mark.e2e
def test_e2e_parse_validate_export_reflex_arc(client):
    """Sequential POST to /api/parse → /api/validate → /api/export."""
    # -- Parse --
    parse_resp = client.post("/api/parse", json={"spec": REFLEX_ARC_SPEC})
    assert parse_resp.status_code == 200
    parse_data = parse_resp.json()
    assert "sentences" in parse_data
    assert len(parse_data["sentences"]) > 0
    assert all(r["parsed"] is not None for r in parse_data["sentences"])

    # -- Validate --
    validate_resp = client.post("/api/validate", json={"spec": REFLEX_ARC_SPEC})
    assert validate_resp.status_code == 200
    validate_data = validate_resp.json()
    assert validate_data["overall"] is True
    assert validate_data["layer1"]["overall"] is True
    assert validate_data["layer2"]["overall"] is True

    # -- Export (cnl) — returns the spec text verbatim --
    export_resp = client.post(
        "/api/export",
        json={"spec": REFLEX_ARC_SPEC, "format": "cnl"},
    )
    assert export_resp.status_code == 200
    assert len(export_resp.text) > 0
    # NIR-native cnl export is the spec itself (no MUST/MUST NOT keywords)
    assert "Define a network named reflex_arc" in export_resp.text


# ---------------------------------------------------------------------------
# API-level E2E: generate topology
# ---------------------------------------------------------------------------


@pytest.mark.e2e
def test_e2e_generate_reflex_arc(client):
    """POST to /api/generate returns a topology and roundtrip CNL."""
    resp = client.post("/api/generate", json={"spec": REFLEX_ARC_SPEC})
    assert resp.status_code == 200
    data = resp.json()
    assert len(data["network"]["nodes"]) > 0
    assert len(data["network"]["edges"]) > 0
    # cnl_document is valid NIR-native CNL
    assert data["cnl_document"].strip().startswith("Define")
    # nir_code is JSON
    assert '"type"' in data["nir_code"]


# ---------------------------------------------------------------------------
# Direct NIR-native compile → validate pipeline
# ---------------------------------------------------------------------------


@pytest.mark.e2e
def test_e2e_direct_compile_and_validate():
    """compile_to_nir() + validate_spec bridge — no mocks, no biological grammar."""
    from backend.app.services.neurocnl_bridge import validate_spec
    from neurocnl.compile import compile_to_nir

    # 1. Compile
    graph = compile_to_nir(REFLEX_ARC_SPEC)
    assert graph is not None
    assert len(graph.nodes) > 0

    # 2. Validate via bridge
    result = validate_spec(REFLEX_ARC_SPEC, {}, backend="nir")
    assert result["overall"] is True
    assert result["layer1"]["overall"] is True
    assert result["layer2"]["overall"] is True
    assert result["planner"] is not None
    assert len(result["layer2"]["neurons_found"]) > 0


# ---------------------------------------------------------------------------
# Direct NIR-native compile → export NIR artifact
# ---------------------------------------------------------------------------


@pytest.mark.e2e
def test_e2e_direct_compile_then_nir_export(client):
    """POST /api/export with format='nir' compiles the spec and returns an HDF5 artifact."""
    resp = client.post("/api/export", json={"spec": REFLEX_ARC_SPEC, "format": "nir"})
    assert resp.status_code == 200
    assert "application/octet-stream" in resp.headers["Content-Type"]
    assert 'filename="network.nir"' in resp.headers["Content-Disposition"]
    # The returned bytes must be a valid HDF5 magic number.
    assert resp.content[:4] == b"\x89HDF"
    # NIR-native export sets faithful verdict and absent advisory semantics.
    assert resp.headers["X-NeuroCNL-Backend-Verdict"] == "faithful"
    assert resp.headers["X-NeuroCNL-NIR-Advisory-Semantics"] == "absent"
