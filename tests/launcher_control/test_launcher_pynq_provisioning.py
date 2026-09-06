"""Launcher control service tests: PYNQ runtime status and preflight."""

import json
from typing import Any
from unittest import mock

from base import LauncherControlServiceTestBase

import nmtk.launcher_control.server as launcher_server


class TestLauncherPynqProvisioning(LauncherControlServiceTestBase):
    def test_runtime_status_response_preserves_wire_and_persisted_fields(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "password": "board-secret",
            }
        )
        status = {
            "runtime_mode": " hardware ",
            "loaded_overlay": "snn_overlay_v2",
        }

        with mock.patch.object(
            self.state,
            "_runtime_json_request",
            return_value=status,
        ):
            result = self.state.fetch_pynq_board_status(board["id"])

        self.assertEqual(result["status"], status)
        self.assertEqual(result["board"]["lastStatus"], status)
        self.assertEqual(result["board"]["lastRuntimeMode"], "hardware")
        self.assertTrue(result["board"]["hasPassword"])
        self.assertNotIn("password", result["board"])

    def test_read_remote_pynq_install_status_decodes_machine_readable_result(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with mock.patch.object(
            self.state,
            "_run_ssh",
            return_value=json.dumps(
                {"installMode": "user-space", "message": "fallback"}
            ),
        ):
            status = self.state._read_remote_pynq_install_status(
                self.state._get_pynq_board(board["id"])
            )

        self.assertEqual(status["installMode"], "user-space")

    def test_restart_pynq_runtime_restarts_user_space_agent_and_refreshes_preflight(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        refreshed = {
            "board": {
                "state": "overlay_missing",
                "lastPreflightMessage": "Install overlay next.",
            }
        }
        with (
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "user-space"},
            ),
            mock.patch.object(self.state, "_restart_user_space_agent") as restart,
            mock.patch.object(
                self.state,
                "_refresh_pynq_board_preflight",
                return_value=refreshed,
            ) as refresh,
        ):
            result = self.state.restart_pynq_runtime(board["id"])

        restart.assert_called_once()
        refresh.assert_called_once_with(board["id"], stage="user-space runtime restart")
        self.assertEqual(result["board"]["state"], "overlay_missing")
        self.assertEqual(result["installStatus"]["installMode"], "user-space")

    def test_preflight_with_missing_overlay_stays_actionable_when_degraded(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        updated = self.state._apply_preflight_to_board(
            board["id"],
            {
                "preflight_status": "degraded",
                "preflight_message": "Simulator fallback active.",
                "overlay_assets": {"ready_for_hardware": False},
            },
        )

        self.assertEqual(updated["state"], "overlay_missing")

    def test_preflight_records_the_overlay_version_the_board_reports(self) -> None:
        """Otherwise the app says "Overlay: Not installed" for a loaded overlay."""
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        updated = self.state._apply_preflight_to_board(
            board["id"],
            {
                "preflight_status": "ok",
                "preflight_message": "Hardware runtime and canonical overlay assets are ready.",
                "overlay_assets": {
                    "ready_for_hardware": True,
                    "overlay_id": "snn_overlay_v2",
                    "overlay_version": "2.0.0",
                },
            },
        )

        self.assertEqual(updated["state"], "ready")
        self.assertEqual(updated["overlayVersion"], "2.0.0")

    def test_preflight_without_an_overlay_version_keeps_the_stored_one(self) -> None:
        """A preflight that could not read the manifest is not a removal."""
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        self.state._update_pynq_board_fields(board["id"], overlayVersion="2.0.0")

        updated = self.state._apply_preflight_to_board(
            board["id"],
            {
                "preflight_status": "failed",
                "preflight_message": "Runtime probe failed.",
                "overlay_assets": {"ready_for_hardware": True},
            },
        )

        self.assertEqual(updated["overlayVersion"], "2.0.0")

    def test_restart_pynq_runtime_waits_for_health_before_preflight_when_systemd_managed(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        events: list[str] = []

        def record_run_ssh(*_args: Any, **_kwargs: Any) -> str:
            events.append("ssh")
            return ""

        def record_wait(*_args: Any, **_kwargs: Any) -> None:
            events.append("wait")

        def record_preflight(*_args: Any, **_kwargs: Any) -> dict[str, Any]:
            events.append("preflight")
            return {"board": {"state": "ready"}}

        with (
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(self.state, "_run_ssh", side_effect=record_run_ssh),
            mock.patch.object(
                self.state,
                "_wait_for_board_agent_health",
                side_effect=record_wait,
            ) as wait_for_health,
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                side_effect=record_preflight,
            ) as fetch_preflight,
        ):
            result = self.state.restart_pynq_runtime(board["id"])

        wait_for_health.assert_called_once()
        fetch_preflight.assert_called_once_with(
            board["id"],
            request_timeout=launcher_server.DEFAULT_PYNQ_PREFLIGHT_TIMEOUT_SECONDS,
        )
        self.assertEqual(events, ["ssh", "wait", "preflight"])
        self.assertEqual(result["board"]["state"], "ready")

    def test_describe_pynq_preflight_reports_overlay_missing_actionably(self) -> None:
        description = launcher_server._describe_pynq_preflight(
            {
                "preflight_status": "failed",
                "preflight_message": "Install Overlay next. Checked bitstream path: /tmp/snn_overlay.bit.",
                "overlay_assets": {"ready_for_hardware": False},
            }
        )

        self.assertIn("overlay assets missing", description)
        self.assertIn("/tmp/snn_overlay.bit", description)

    def test_describe_pynq_preflight_surfaces_runtime_probe_context(self) -> None:
        description = launcher_server._describe_pynq_preflight(
            {
                "preflight_status": "failed",
                "preflight_message": (
                    "Hardware runtime assets are present, but the board cannot open a usable "
                    "PYNQ device yet. Runtime probe failed: Bitstream not found: "
                    "snn_overlay.bit. Checked bitstream path: "
                    "/home/xilinx/.local/share/neurochip-pynq-agent/overlays/snn_overlay.bit."
                ),
                "overlay_assets": {"ready_for_hardware": True},
            }
        )

        self.assertIn("Bitstream not found", description)
        self.assertIn(
            "/home/xilinx/.local/share/neurochip-pynq-agent/overlays/snn_overlay.bit",
            description,
        )

    def test_provision_pynq_board_reports_install_status(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        def apply_overlay_missing_preflight(
            *_args: Any, **_kwargs: Any
        ) -> dict[str, Any]:
            updated = self.state._update_pynq_board_fields(
                board["id"],
                state="overlay_missing",
                lastPreflightStatus="failed",
                lastPreflightMessage="Install overlay next.",
            )
            return {"board": launcher_server._serialize_pynq_board(updated)}

        def ssh(_board: Any, command: str) -> str:
            # This board grants no administrator access, so provisioning cannot
            # promote the runtime to a privileged service and the user-space
            # install is what the user is told about.
            if command.startswith("sudo -n"):
                raise RuntimeError("sudo: a terminal is required to read the password")
            return ""

        with (
            mock.patch.object(self.state, "_build_local_pynq_bundle"),
            mock.patch.object(self.state, "_run_ssh", side_effect=ssh),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "user-space"},
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                side_effect=apply_overlay_missing_preflight,
            ),
        ):
            result = self.state.provision_pynq_board(board["id"])

        self.assertEqual(result["installStatus"]["installMode"], "user-space")
        self.assertEqual(result["board"]["state"], "overlay_missing")
        self.assertIn(
            "Install the overlay now",
            result["board"]["lastPreflightMessage"],
        )
        self.assertIn(
            "after a board reboot",
            result["board"]["lastPreflightMessage"],
        )

    def test_provision_pynq_board_tails_runtime_log_when_install_script_fails(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(self.state, "_build_local_pynq_bundle"),
            mock.patch.object(
                self.state,
                "_run_ssh",
                # mkdir, then the device-group check, then the install script.
                side_effect=[
                    "",
                    "xilinx video render",
                    RuntimeError("install script failed on remote host"),
                ],
            ),
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(
                self.state, "_emit_runtime_log_tail"
            ) as emit_runtime_log_tail,
        ):
            result = self.state.provision_pynq_board(board["id"])

        emit_runtime_log_tail.assert_called_once()
        self.assertEqual(emit_runtime_log_tail.call_args.args[1], {})
        self.assertEqual(result["error"], "install script failed on remote host")
        self.assertEqual(result["board"]["state"], "provision_failed")
        self.assertEqual(
            result["board"]["lastPreflightMessage"],
            "install script failed on remote host",
        )
