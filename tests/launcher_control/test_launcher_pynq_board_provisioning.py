"""Launcher control service tests: PYNQ board provisioning (timeout resolution, preflight retry, runtime recheck)."""

import os
from unittest import mock

from base import LauncherControlServiceTestBase

import nmtk.launcher_control.server as launcher_server
from nmtk.launcher_control import (
    pynq_provisioning,
)


class TestLauncherPynqBoardProvisioning(LauncherControlServiceTestBase):
    def test_resolve_pynq_agent_health_timeout_respects_env_and_bounds(self) -> None:
        cases = {
            "": launcher_server.DEFAULT_PYNQ_AGENT_HEALTH_TIMEOUT_SECONDS,
            "45": 45.0,
            "2": launcher_server.PYNQ_AGENT_HEALTH_TIMEOUT_BOUNDS[0],
            "9999": launcher_server.PYNQ_AGENT_HEALTH_TIMEOUT_BOUNDS[1],
            "not-a-number": launcher_server.DEFAULT_PYNQ_AGENT_HEALTH_TIMEOUT_SECONDS,
        }
        for raw, expected in cases.items():
            with mock.patch.dict(
                os.environ,
                {"NEUROCHIP_PYNQ_HEALTH_TIMEOUT_SECONDS": raw},
                clear=False,
            ):
                self.assertEqual(
                    launcher_server._resolve_pynq_agent_health_timeout(), expected, raw
                )

    def test_resolve_pynq_preflight_timeout_respects_env_and_bounds(self) -> None:
        cases = {
            "": launcher_server.DEFAULT_PYNQ_PREFLIGHT_TIMEOUT_SECONDS,
            "60": 60.0,
            "1": launcher_server.PYNQ_PREFLIGHT_TIMEOUT_BOUNDS[0],
            "9999": launcher_server.PYNQ_PREFLIGHT_TIMEOUT_BOUNDS[1],
            "not-a-number": launcher_server.DEFAULT_PYNQ_PREFLIGHT_TIMEOUT_SECONDS,
        }
        for raw, expected in cases.items():
            with mock.patch.dict(
                os.environ,
                {"NEUROCHIP_PYNQ_PREFLIGHT_TIMEOUT_SECONDS": raw},
                clear=False,
            ):
                self.assertEqual(
                    launcher_server._resolve_pynq_preflight_timeout(),
                    expected,
                    raw,
                )

    def test_provision_pynq_board_retries_preflight_timeout(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "198.51.100.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(self.state, "_build_local_pynq_bundle"),
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                side_effect=[
                    launcher_server.RuntimeRequestError(
                        "Runtime request timed out for GET http://198.51.100.50:8002/hardware/pynq/preflight after 45s",
                        kind="timeout",
                        url="http://198.51.100.50:8002/hardware/pynq/preflight",
                    ),
                    {"board": {"state": "ready"}},
                ],
            ) as fetch_preflight,
            mock.patch.object(pynq_provisioning.time, "sleep", return_value=None),
        ):
            result = self.state.provision_pynq_board(board["id"])

        self.assertEqual(result["board"]["state"], "ready")
        self.assertEqual(fetch_preflight.call_count, 2)

    def test_restart_pynq_runtime_rechecks_health_when_preflight_is_unreachable(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "198.51.100.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(self.state, "_run_ssh"),
            mock.patch.object(
                self.state,
                "_wait_for_board_agent_health",
            ) as wait_for_health,
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                side_effect=[
                    launcher_server.RuntimeRequestError(
                        "Runtime request failed for GET http://198.51.100.50:8002/hardware/pynq/preflight: could not be reached: connection refused",
                        kind="unreachable",
                        url="http://198.51.100.50:8002/hardware/pynq/preflight",
                    ),
                    {"board": {"state": "ready"}},
                ],
            ) as fetch_preflight,
            mock.patch.object(pynq_provisioning.time, "sleep", return_value=None),
        ):
            result = self.state.restart_pynq_runtime(board["id"])

        self.assertEqual(result["board"]["state"], "ready")
        self.assertEqual(wait_for_health.call_count, 2)
        self.assertEqual(fetch_preflight.call_count, 2)

    def test_fetch_pynq_board_preflight_marks_overlay_missing_when_assets_are_missing(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "198.51.100.50",
                "username": "xilinx",
            }
        )

        with mock.patch.object(
            self.state,
            "_runtime_json_request",
            return_value={
                "preflight_status": "failed",
                "preflight_message": "Install Overlay next.",
                "runtime_mode": "hardware",
                "overlay_assets": {"ready_for_hardware": False},
            },
        ):
            result = self.state.fetch_pynq_board_preflight(board["id"])

        self.assertEqual(result["board"]["state"], "overlay_missing")

    def test_fetch_pynq_board_preflight_marks_ready_asset_failures_as_preflight_failed(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "198.51.100.50",
                "username": "xilinx",
            }
        )

        with mock.patch.object(
            self.state,
            "_runtime_json_request",
            return_value={
                "preflight_status": "failed",
                "preflight_message": (
                    "Runtime probe failed: No Devices Found. Checked bitstream path: "
                    "/home/xilinx/.local/share/neurochip-pynq-agent/overlays/snn_overlay.bit."
                ),
                "runtime_mode": "hardware",
                "overlay_assets": {"ready_for_hardware": True},
            },
        ):
            result = self.state.fetch_pynq_board_preflight(board["id"])

        self.assertEqual(result["board"]["state"], "preflight_failed")
        self.assertIn(
            "/home/xilinx/.local/share/neurochip-pynq-agent/overlays/snn_overlay.bit",
            result["board"]["lastPreflightMessage"],
        )
