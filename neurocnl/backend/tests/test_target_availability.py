"""Tests for GET /api/neurocnl/notebook/target-availability."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient

from backend.app.main import app
from neurocnl.target_sdk import TARGET_AVAILABILITY_KEYS, probe_target_availability

client = TestClient(app)

_STUDIO_DEPLOY_TARGET_IDS = (
    "lava_sim",
    "snntorch_sim",
    "sc_neurocore_sim",
    "brian2",
    "sinabs",
    "rockpool",
    "pynn",
    "nengo",
    "akida",
    "lava",
    "sc_neurocore_fpga",
)


def test_target_availability_keys_cover_studio_deploy_targets() -> None:
    availability_keys = set(TARGET_AVAILABILITY_KEYS)
    for target_id in _STUDIO_DEPLOY_TARGET_IDS:
        assert target_id in availability_keys, (
            f"deploy target {target_id!r} missing from TARGET_AVAILABILITY_KEYS"
        )


def test_lava_available_via_worker_when_import_missing() -> None:
    with (
        patch("neurocnl.target_sdk.module_importable", return_value=False),
        patch(
            "neurocnl.target_sdk.lava_worker_reachable",
            return_value=True,
        ),
    ):
        availability = probe_target_availability()
    assert availability["lava_sim"] is True
    assert availability["lava"] is True


def test_lava_unavailable_without_import_or_worker() -> None:
    with (
        patch("neurocnl.target_sdk.module_importable", return_value=False),
        patch(
            "neurocnl.target_sdk.lava_worker_reachable",
            return_value=False,
        ),
    ):
        availability = probe_target_availability()
    assert availability["lava_sim"] is False
    assert availability["lava"] is False


def test_framework_targets_follow_import_probes() -> None:
    def _fake_importable(module_name: str) -> bool:
        return module_name in {"brian2", "pyNN", "akida"}

    with (
        patch("neurocnl.target_sdk.module_importable", side_effect=_fake_importable),
        patch("neurocnl.target_sdk.lava_available", return_value=False),
    ):
        availability = probe_target_availability()
    assert availability["brian2"] is True
    assert availability["pynn"] is True
    assert availability["akida"] is True
    assert availability["sinabs"] is False


def test_target_availability_endpoint_uses_probe_helper() -> None:
    mocked = dict.fromkeys(TARGET_AVAILABILITY_KEYS, True)
    mocked["lava_sim"] = True
    mocked["lava"] = True
    with patch(
        "neurocnl.target_sdk.probe_target_availability",
        return_value=mocked,
    ):
        response = client.get("/api/notebook/target-availability")
    assert response.status_code == 200
    assert response.json() == mocked


def test_lava_worker_reachable_honors_health_payload() -> None:
    from neurocnl import target_sdk

    response = MagicMock()
    response.status_code = 200
    response.json.return_value = {"status": "ok", "lava_importable": False}

    with (
        patch.dict("os.environ", {"NEUROCNL_LAVA_WORKER_URL": "http://lava:8012"}, clear=False),
        patch("httpx.get", return_value=response),
    ):
        assert target_sdk.lava_worker_reachable() is False

    response.json.return_value = {"status": "ok", "lava_importable": True}
    with (
        patch.dict("os.environ", {"NEUROCNL_LAVA_WORKER_URL": "http://lava:8012"}, clear=False),
        patch("httpx.get", return_value=response),
    ):
        assert target_sdk.lava_worker_reachable() is True
