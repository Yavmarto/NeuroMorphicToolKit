"""Tests for the `/hardware/pynq/*` FastAPI router and its hardware-probe cache.

All tests run without the ``pynq`` library — the backend falls back to
`PynqSimulator` automatically.
"""

import json
from typing import Any
from unittest.mock import patch

import pytest
from pynq_backend_fixtures import ONE_TO_ONE_LAYER, ONE_TO_TWO_LAYER, client

from neurochip.app.services.pynq_errors import (
    ConfigurationError,
    DmaTransferError,
    MmioWriteError,
    OverlayLoadError,
    PynqRuntimeError,
)
from neurochip.contracts.pynq_runtime_artifact_contract import (
    DEFAULT_REGISTER_MAP,
    PynqOverlayManifestContract,
)


class TestPynqRouter:
    def test_deploy_endpoint(self):
        response = client.post(
            "/hardware/pynq/deploy",
            json={"weights": [0.1, 0.2], "config": {}},
            headers={"X-API-Key": "test_key"},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "success"
        assert body["runtime_mode"] == "simulator"
        assert body["preflight_status"] == "degraded"

    def test_deploy_endpoint_rejects_simulator_when_hardware_required(self):
        response = client.post(
            "/hardware/pynq/deploy",
            json={"weights": [0.1], "config": {}, "require_hardware": True},
            headers={"X-API-Key": "test_key"},
        )

        assert response.status_code == 503
        assert response.json()["detail"]["error"] == "hardware_required"
        assert response.json()["detail"]["runtime_mode"] == "simulator"

    def test_run_endpoint(self):
        # Deploy first
        client.post(
            "/hardware/pynq/deploy",
            json={
                "weights": [2.0, 0.5],
                "layers": [ONE_TO_TWO_LAYER],
                "config": {},
            },
            headers={"X-API-Key": "test_key"},
        )
        response = client.post(
            "/hardware/pynq/run",
            json={"input_spikes": [0], "timesteps": 1},
            headers={"X-API-Key": "test_key"},
        )
        assert response.status_code == 200
        body = response.json()
        assert body["status"] == "success"
        assert "output_spikes" in body
        assert body["timesteps"] == 1

    def test_run_without_deploy(self):
        with patch("neurochip.app.routers.pynq.backend_instance", None):
            response = client.post(
                "/hardware/pynq/run",
                json={"input_spikes": [1, 2, 3]},
                headers={"X-API-Key": "test_key"},
            )
            assert response.status_code == 400
            assert "Overlay not deployed" in response.json()["detail"]

    def test_run_empty_spikes_returns_error(self):
        client.post(
            "/hardware/pynq/deploy",
            json={"weights": [1.0], "config": {}},
            headers={"X-API-Key": "test_key"},
        )
        response = client.post(
            "/hardware/pynq/run",
            json={"input_spikes": []},
            headers={"X-API-Key": "test_key"},
        )
        assert response.status_code == 502
        body = response.json()["detail"]
        assert body["error_code"] == "DMA_EMPTY_BUFFER"

    @pytest.mark.parametrize(
        ("exc", "expected_status"),
        [
            (
                OverlayLoadError(
                    "No board detected",
                    error_code="PYNQ_DEVICE_NOT_FOUND",
                ),
                503,
            ),
            (
                OverlayLoadError(
                    "Runtime missing",
                    error_code="PYNQ_RUNTIME_UNAVAILABLE",
                ),
                503,
            ),
            (
                ConfigurationError(
                    "Register map mismatch",
                    error_code="OVERLAY_REGISTER_MAP_MISMATCH",
                ),
                422,
            ),
            (
                ConfigurationError(
                    "Version mismatch",
                    error_code="OVERLAY_VERSION_MISMATCH",
                ),
                422,
            ),
            (
                MmioWriteError(
                    "Too many weights",
                    error_code="MMIO_WEIGHT_OVERFLOW",
                ),
                413,
            ),
            (
                DmaTransferError(
                    "DMA failed",
                    error_code="DMA_TRANSFER_FAILED",
                ),
                502,
            ),
        ],
    )
    def test_pynq_error_taxonomy(self, exc: PynqRuntimeError, expected_status: int) -> None:
        from neurochip.app.services.pynq_router_support import (
            HardwareProbeCache,
            pynq_error_to_http,
        )

        error = pynq_error_to_http(exc, probe_cache=HardwareProbeCache())
        assert error.status_code == expected_status
        assert isinstance(error.detail, dict)
        assert error.detail["error_code"] == exc.error_code

    def test_status_endpoint_not_initialised(self):
        with patch("neurochip.app.routers.pynq.backend_instance", None):
            response = client.get(
                "/hardware/pynq/status",
                headers={"X-API-Key": "test_key"},
            )
            assert response.status_code == 200
            assert response.json()["state"] == "not_initialised"
            assert response.json()["runtime_mode"] == "simulator"
            assert response.json()["overlay_assets"]["ready_for_hardware"] is False

    def test_status_endpoint_after_deploy(self):
        client.post(
            "/hardware/pynq/deploy",
            json={"weights": [1.0], "config": {}},
            headers={"X-API-Key": "test_key"},
        )
        response = client.get(
            "/hardware/pynq/status",
            headers={"X-API-Key": "test_key"},
        )
        assert response.status_code == 200
        assert response.json()["state"] == "configured"
        assert response.json()["runtime_mode"] == "simulator"
        assert response.json()["overlay_assets"]["bitstream_path"].endswith(
            "/overlays/snn_overlay.bit"
        )

    def test_deploy_with_register_map(self):
        response = client.post(
            "/hardware/pynq/deploy",
            json={
                "weights": [1.0],
                "config": {},
                "register_map": {"weight_base_offset": 131072},
            },
            headers={"X-API-Key": "test_key"},
        )
        assert response.status_code == 200

    def test_deploy_rejects_stale_register_map_against_installed_manifest(self):
        stale_map = dict(DEFAULT_REGISTER_MAP)
        stale_map["weight_base_offset"] = 0x10000
        with patch(
            "neurochip.app.services.pynq_router_support.installed_overlay_manifest",
            return_value=PynqOverlayManifestContract(),
        ):
            response = client.post(
                "/hardware/pynq/deploy",
                json={
                    "weights": [1.0],
                    "config": {},
                    "register_map": stale_map,
                },
                headers={"X-API-Key": "test_key"},
            )

        assert response.status_code == 422
        assert response.json()["detail"]["error_code"] == "OVERLAY_REGISTER_MAP_MISMATCH"

    def test_deploy_rejects_incomplete_register_map_against_installed_manifest(self):
        with patch(
            "neurochip.app.services.pynq_router_support.installed_overlay_manifest",
            return_value=PynqOverlayManifestContract(),
        ):
            response = client.post(
                "/hardware/pynq/deploy",
                json={
                    "weights": [1.0],
                    "config": {},
                    "register_map": {"weight_base_offset": 0x1000},
                },
                headers={"X-API-Key": "test_key"},
            )

        assert response.status_code == 422
        assert response.json()["detail"]["error_code"] == "OVERLAY_REGISTER_MAP_MISMATCH"

    def test_run_with_timesteps(self):
        client.post(
            "/hardware/pynq/deploy",
            json={
                "weights": [2.0],
                "layers": [ONE_TO_ONE_LAYER],
                "config": {},
            },
            headers={"X-API-Key": "test_key"},
        )
        response = client.post(
            "/hardware/pynq/run",
            # One input word per neuron per timestep.
            json={"input_spikes": [1, 0, 1, 0, 1], "timesteps": 5},
            headers={"X-API-Key": "test_key"},
        )
        assert response.status_code == 200
        assert response.json()["timesteps"] == 5

    def test_preflight_endpoint_reports_simulator_degraded(self):
        with patch("neurochip.app.routers.pynq.backend_instance", None):
            response = client.get(
                "/hardware/pynq/preflight",
                headers={"X-API-Key": "test_key"},
            )
        assert response.status_code == 200
        body = response.json()
        assert body["preflight_status"] == "degraded"
        assert body["runtime_mode"] == "simulator"
        assert body["overlay_assets"]["ready_for_hardware"] is False
        assert body["resolved_paths"]["bitstream_path"].endswith("/overlays/snn_overlay.bit")
        assert "runtime_details" in body

    def test_preflight_endpoint_reports_hardware_failure_when_assets_missing(self):
        with (
            patch("neurochip.app.routers.pynq.default_runtime_mode", return_value="hardware"),
            patch("neurochip.app.routers.pynq.backend_instance", None),
        ):
            response = client.get(
                "/hardware/pynq/preflight",
                headers={"X-API-Key": "test_key"},
            )
        assert response.status_code == 200
        body = response.json()
        assert body["preflight_status"] == "failed"
        assert body["runtime_mode"] == "hardware"
        assert body["overlay_assets"]["ready_for_hardware"] is False
        assert "Install Overlay" in body["preflight_message"]
        assert "snn_overlay.bit" in body["preflight_message"]
        assert body["resolved_paths"]["bitstream_path"].endswith("/overlays/snn_overlay.bit")

    def test_preflight_endpoint_reports_a_working_user_space_install_as_ok(self, tmp_path):
        from neurochip.app.routers import pynq as pynq_router

        status_path = tmp_path / "install-status.json"
        status_path.write_text(
            json.dumps(
                {
                    "installMode": "user-space",
                    "effectivePynqPython": "/usr/local/share/pynq-venv/bin/python",
                    "pynqRuntimeSource": "canonical",
                    "agentPackageVersion": "0.6.0",
                    "agentWheelName": "neurochip-0.6.0-py3-none-any.whl",
                }
            ),
            encoding="utf-8",
        )
        with (
            patch.dict(
                "os.environ",
                {"NEUROCHIP_PYNQ_INSTALL_STATUS_PATH": str(status_path)},
                clear=False,
            ),
            patch("neurochip.app.routers.pynq.default_runtime_mode", return_value="hardware"),
            patch(
                "neurochip.app.services.pynq_router_support.inspect_overlay_assets"
            ) as inspect_assets,
            patch("neurochip.app.routers.pynq.backend_instance", None),
            patch.object(pynq_router._hardware_probe_cache, "probe"),
        ):
            inspect_assets.return_value.to_dict.return_value = {
                "requested_bitstream_path": "snn_overlay.bit",
                "bitstream_path": "/tmp/snn_overlay.bit",
                "hwh_path": "/tmp/snn_overlay.hwh",
                "manifest_path": "/tmp/overlay_manifest.json",
                "bitstream_exists": True,
                "hwh_exists": True,
                "manifest_exists": True,
                "manifest_valid": True,
                "overlay_id": "snn_overlay_v1",
                "overlay_version": "1.0.1",
                "ready_for_hardware": True,
                "issues": [],
            }
            response = client.get(
                "/hardware/pynq/preflight",
                headers={"X-API-Key": "test_key"},
            )

        assert response.status_code == 200
        body = response.json()
        # The probe passed, so the board can run a network. Reporting "degraded"
        # here blocked Deploy behind a launcher state that only "ok" clears, and
        # the app's advice for it — restart the runtime — can never change the
        # install mode.
        assert body["preflight_status"] == "ok"
        assert "will not start again by itself after a board reboot" in body["preflight_message"]
        assert body["install_mode"] == "user-space"
        assert (
            body["runtime_details"]["effectivePynqPython"]
            == "/usr/local/share/pynq-venv/bin/python"
        )
        assert body["runtime_details"]["agentPackageVersion"] == "0.6.0"
        assert body["runtime_details"]["agentWheelName"] == "neurochip-0.6.0-py3-none-any.whl"

    def test_preflight_endpoint_reports_hardware_failure_when_device_open_fails(self):
        from neurochip.app.routers import pynq as pynq_router

        with (
            patch("neurochip.app.routers.pynq.default_runtime_mode", return_value="hardware"),
            patch(
                "neurochip.app.services.pynq_router_support.inspect_overlay_assets"
            ) as inspect_assets,
            patch("neurochip.app.routers.pynq.backend_instance", None),
            patch.object(
                pynq_router._hardware_probe_cache,
                "probe",
                side_effect=OverlayLoadError(
                    "Overlay loading failed: No Devices Found",
                    error_code="OVERLAY_LOAD_FAILED",
                ),
            ),
        ):
            inspect_assets.return_value.to_dict.return_value = {
                "requested_bitstream_path": "snn_overlay.bit",
                "bitstream_path": "/tmp/snn_overlay.bit",
                "hwh_path": "/tmp/snn_overlay.hwh",
                "manifest_path": "/tmp/overlay_manifest.json",
                "bitstream_exists": True,
                "hwh_exists": True,
                "manifest_exists": True,
                "manifest_valid": True,
                "overlay_id": "snn_overlay_v1",
                "overlay_version": "1.0.1",
                "ready_for_hardware": True,
                "issues": [],
            }
            response = client.get(
                "/hardware/pynq/preflight",
                headers={"X-API-Key": "test_key"},
            )

        assert response.status_code == 200
        body = response.json()
        assert body["preflight_status"] == "failed"
        assert body["runtime_mode"] == "hardware"
        assert body["overlay_assets"]["ready_for_hardware"] is True
        assert "No Devices Found" in body["preflight_message"]
        assert "/tmp/snn_overlay.bit" in body["preflight_message"]
        assert body["resolved_paths"]["bitstream_path"] == "/tmp/snn_overlay.bit"

    def test_preflight_endpoint_reports_bounded_probe_timeout_actionably(self):
        from neurochip.app.routers import pynq as pynq_router

        with (
            patch("neurochip.app.routers.pynq.default_runtime_mode", return_value="hardware"),
            patch(
                "neurochip.app.services.pynq_router_support.inspect_overlay_assets"
            ) as inspect_assets,
            patch("neurochip.app.routers.pynq.backend_instance", None),
            patch.object(
                pynq_router._hardware_probe_cache,
                "probe",
                side_effect=OverlayLoadError(
                    "PYNQ probe device timed out after 20s",
                    error_code="PYNQ_DEVICE_PROBE_TIMEOUT",
                ),
            ),
        ):
            inspect_assets.return_value.to_dict.return_value = {
                "requested_bitstream_path": "snn_overlay.bit",
                "bitstream_path": "/tmp/snn_overlay.bit",
                "hwh_path": "/tmp/snn_overlay.hwh",
                "manifest_path": "/tmp/overlay_manifest.json",
                "bitstream_exists": True,
                "hwh_exists": True,
                "manifest_exists": True,
                "manifest_valid": True,
                "overlay_id": "snn_overlay_v1",
                "overlay_version": "1.0.1",
                "ready_for_hardware": True,
                "issues": [],
            }
            response = client.get(
                "/hardware/pynq/preflight",
                headers={"X-API-Key": "test_key"},
            )

        assert response.status_code == 200
        body = response.json()
        assert body["preflight_status"] == "failed"
        assert "bounded device probe" in body["preflight_message"]
        assert "timed out" in body["preflight_message"]
        assert "/tmp/snn_overlay.bit" in body["preflight_message"]


class TestPynqHardwareProbeCache:
    """A passing probe is reused briefly.

    Importing `pynq` in a fresh interpreter on a Zynq-7020 takes ~20s, and the
    app asks for readiness every time the Deploy step is opened — twice, on two
    code paths. That charged the user 20s per visit for an answer that cannot
    change in between, and left the pane spinning with Deploy greyed out.
    """

    def _ready_assets(self) -> dict[str, Any]:
        return {
            "requested_bitstream_path": "snn_overlay.bit",
            "bitstream_path": "/tmp/snn_overlay.bit",
            "hwh_path": "/tmp/snn_overlay.hwh",
            "manifest_path": "/tmp/overlay_manifest.json",
            "bitstream_exists": True,
            "hwh_exists": True,
            "manifest_exists": True,
            "manifest_valid": True,
            "overlay_id": "snn_overlay_v2",
            "overlay_version": "2.0.0",
            "ready_for_hardware": True,
            "issues": [],
        }

    def test_two_preflights_probe_the_device_once(self):
        from neurochip.app.routers import pynq as pynq_router

        pynq_router._hardware_probe_cache.invalidate()
        with (
            patch("neurochip.app.routers.pynq.default_runtime_mode", return_value="hardware"),
            patch(
                "neurochip.app.services.pynq_router_support.inspect_overlay_assets"
            ) as inspect_assets,
            patch("neurochip.app.routers.pynq.backend_instance", None),
            patch("neurochip.app.services.pynq_backend.probe_real_pynq_device_access") as probe,
        ):
            inspect_assets.return_value.to_dict.return_value = self._ready_assets()
            first = client.get("/hardware/pynq/preflight", headers={"X-API-Key": "test_key"})
            second = client.get("/hardware/pynq/preflight", headers={"X-API-Key": "test_key"})

        assert first.json()["preflight_status"] == "ok"
        assert second.json()["preflight_status"] == "ok"
        assert probe.call_count == 1
        pynq_router._hardware_probe_cache.invalidate()

    def test_a_failing_probe_is_not_cached(self):
        """The user is retrying while they fix the board; do not answer from memory."""
        from neurochip.app.routers import pynq as pynq_router

        pynq_router._hardware_probe_cache.invalidate()
        with (
            patch("neurochip.app.routers.pynq.default_runtime_mode", return_value="hardware"),
            patch(
                "neurochip.app.services.pynq_router_support.inspect_overlay_assets"
            ) as inspect_assets,
            patch("neurochip.app.routers.pynq.backend_instance", None),
            patch(
                "neurochip.app.services.pynq_backend.probe_real_pynq_device_access",
                side_effect=OverlayLoadError(
                    "Overlay loading failed: No Devices Found",
                    error_code="OVERLAY_LOAD_FAILED",
                ),
            ) as probe,
        ):
            inspect_assets.return_value.to_dict.return_value = self._ready_assets()
            client.get("/hardware/pynq/preflight", headers={"X-API-Key": "test_key"})
            client.get("/hardware/pynq/preflight", headers={"X-API-Key": "test_key"})

        assert probe.call_count == 2

    def test_a_device_level_failure_drops_the_cached_pass(self):
        from neurochip.app.routers import pynq as pynq_router
        from neurochip.app.services.pynq_errors import ConfigurationError

        pynq_router._hardware_probe_cache.invalidate()
        with (
            patch("neurochip.app.routers.pynq.default_runtime_mode", return_value="hardware"),
            patch(
                "neurochip.app.services.pynq_router_support.inspect_overlay_assets"
            ) as inspect_assets,
            patch("neurochip.app.routers.pynq.backend_instance", None),
            patch("neurochip.app.services.pynq_backend.probe_real_pynq_device_access") as probe,
        ):
            inspect_assets.return_value.to_dict.return_value = self._ready_assets()
            client.get("/hardware/pynq/preflight", headers={"X-API-Key": "test_key"})
            # A real operation could not reach the device; that outranks the
            # cached "the probe passed" from a moment ago.
            pynq_router.pynq_error_to_http(
                ConfigurationError("gone", error_code="PYNQ_DEVICE_NOT_FOUND"),
                probe_cache=pynq_router._hardware_probe_cache,
            )
            client.get("/hardware/pynq/preflight", headers={"X-API-Key": "test_key"})

        assert probe.call_count == 2
        pynq_router._hardware_probe_cache.invalidate()
