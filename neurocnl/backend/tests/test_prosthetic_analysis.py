from pathlib import Path

from backend.tests.conftest import REFLEX_ARC_SPEC


def test_fault_injection_analysis_success(client):
    response = client.post(
        "/api/prosthetic/fault-injection",
        json={"spec": REFLEX_ARC_SPEC, "error_rate": 0.2},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["error_rate"] == 0.2
    assert 0.0 <= data["degraded_accuracy"] <= data["baseline_accuracy"] <= 1.0
    assert 0.0 <= data["resilience_score"] <= 1.0
    assert isinstance(data["failed_nodes"], list)


def test_fault_injection_analysis_parse_error(client):
    response = client.post(
        "/api/prosthetic/fault-injection",
        json={"spec": "not valid cnl", "error_rate": 0.1},
    )

    assert response.status_code == 422
    assert "Parse failed" in response.json()["detail"]


def test_prepare_neurosense_replay_success(client):
    artifact_path = (
        Path(__file__).resolve().parents[3]
        / "Neurosense"
        / "neurosense"
        / "tests"
        / "fixtures"
        / "canonical_emg_session.hdf5"
    )

    response = client.post(
        "/api/prosthetic/neurosense/replay",
        json={"artifact_path": str(artifact_path), "preview_frames": 3},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["artifact_schema_version"] == "1.0"
    assert data["channels"] == 2
    assert data["frame_count"] > 0
    assert len(data["preview_frames"]) == 3
    assert data["spike_event_count"] > 0
