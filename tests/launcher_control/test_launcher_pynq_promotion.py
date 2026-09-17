"""Launcher control service tests: PYNQ privileged promotion (user-space to root service, rollback, systemd restart)."""

from typing import Any
from unittest import mock

from base import LauncherControlServiceTestBase

import nmtk.launcher_control.server as launcher_server


class TestLauncherPynqPromotion(LauncherControlServiceTestBase):
    def _password_board(self) -> dict[str, Any]:
        return self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "198.51.100.50",
                "username": "xilinx",
                "authMode": "password",
                "password": "board-secret",
            }
        )

    def test_provisioning_promotes_a_user_space_install_to_a_root_service(self) -> None:
        board = self._password_board()
        # Read once after the install script, once after the promotion.
        statuses = [
            {"installMode": "user-space", "effectivePynqPython": "/usr/bin/python3"},
            {"installMode": "systemd", "effectivePynqPython": "/usr/bin/python3"},
        ]

        with (
            mock.patch.object(self.state, "_build_local_pynq_bundle"),
            mock.patch.object(self.state, "_run_ssh", return_value="") as run_ssh,
            mock.patch.object(self.state, "_run_scp"),
            mock.patch.object(self.state, "_run_ssh_sudo", return_value="") as run_sudo,
            mock.patch.object(self.state, "_wait_for_board_agent_health"),
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                side_effect=statuses,
            ),
            mock.patch.object(
                self.state,
                "fetch_pynq_board_preflight",
                return_value={
                    "board": launcher_server._serialize_pynq_board(
                        self.state._get_pynq_board(board["id"])
                    )
                },
            ),
        ):
            result = self.state.provision_pynq_board(board["id"])

        sudo_commands = [call.args[1] for call in run_sudo.call_args_list]
        self.assertIn("true", sudo_commands)
        self.assertIn(
            "mv /tmp/neurochip-pynq-agent.service "
            "/etc/systemd/system/neurochip-pynq-agent.service",
            sudo_commands,
        )
        self.assertIn("systemctl daemon-reload", sudo_commands)
        self.assertIn("systemctl enable neurochip-pynq-agent.service", sudo_commands)
        self.assertIn("systemctl restart neurochip-pynq-agent.service", sudo_commands)
        # The user-space agent has to stop before the service claims its port.
        stop_index = next(
            index
            for index, call in enumerate(run_ssh.call_args_list)
            if "pkill" in call.args[1]
        )
        stage_index = next(
            index
            for index, call in enumerate(run_ssh.call_args_list)
            if "systemd/neurochip-pynq-agent.service" in call.args[1]
        )
        self.assertLess(stage_index, stop_index)
        self.assertEqual(result["installStatus"]["installMode"], "systemd")

    def test_promotion_is_skipped_without_a_password_and_leaves_the_agent_running(
        self,
    ) -> None:
        """No stored password means no root — but also no half-finished switch."""
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "198.51.100.50",
                "username": "xilinx",
            }
        )

        def ssh(_board: Any, command: str) -> str:
            if command.startswith("sudo -n"):
                raise RuntimeError("sudo: a terminal is required to read the password")
            return ""

        with (
            mock.patch.object(self.state, "_run_ssh", side_effect=ssh) as run_ssh,
            mock.patch.object(self.state, "_run_ssh_sudo") as run_sudo,
        ):
            status = self.state._promote_pynq_install_to_systemd(
                self.state._get_pynq_board(board["id"]),
                "/tmp/bundle",
                {"installMode": "user-space"},
            )

        self.assertEqual(status["installMode"], "user-space")
        # No password, so the password helper is never reached.
        run_sudo.assert_not_called()
        self.assertFalse(
            [call for call in run_ssh.call_args_list if "pkill" in call.args[1]]
        )

    def test_promotion_leaves_the_user_space_agent_running_when_sudo_is_refused(
        self,
    ) -> None:
        board = self._password_board()

        with (
            mock.patch.object(self.state, "_run_ssh", return_value="") as run_ssh,
            mock.patch.object(
                self.state,
                "_run_ssh_sudo",
                side_effect=RuntimeError("sudo: a password is required"),
            ),
        ):
            status = self.state._promote_pynq_install_to_systemd(
                self.state._get_pynq_board(board["id"]),
                "/tmp/bundle",
                {"installMode": "user-space"},
            )

        self.assertEqual(status["installMode"], "user-space")
        # Sudo is probed before anything is torn down, so the working runtime
        # survives a board that will not give us root.
        self.assertFalse(
            [call for call in run_ssh.call_args_list if "pkill" in call.args[1]]
        )

    def test_a_failed_promotion_restores_the_user_space_runtime(self) -> None:
        board = self._password_board()

        def sudo(_board: Any, command: str, **_kwargs: Any) -> str:
            if command.startswith("systemctl enable"):
                raise RuntimeError("Failed to enable unit")
            return ""

        with (
            mock.patch.object(self.state, "_run_ssh", return_value=""),
            mock.patch.object(self.state, "_run_ssh_sudo", side_effect=sudo),
            mock.patch.object(
                self.state, "_restart_user_space_agent"
            ) as restart_user_space,
            mock.patch.object(self.state, "_wait_for_board_agent_health"),
        ):
            status = self.state._promote_pynq_install_to_systemd(
                self.state._get_pynq_board(board["id"]),
                "/tmp/bundle",
                {"installMode": "user-space"},
            )

        restart_user_space.assert_called_once()
        self.assertEqual(status["installMode"], "user-space")

    def test_promotion_rewrites_the_install_mode_the_board_reports(self) -> None:
        """Preflight and every restart path branch on this file, not on us."""
        board = self._password_board()

        with mock.patch.object(self.state, "_run_ssh", return_value="") as run_ssh:
            self.state._write_remote_pynq_install_mode(
                self.state._get_pynq_board(board["id"]),
                "systemd",
                "Runtime installed as a privileged systemd service.",
            )

        command = run_ssh.call_args.args[1]
        self.assertIn("python3 -c", command)
        self.assertIn("install-status.json", command)
        self.assertIn("systemd", command)

    def test_systemd_restart_uses_the_stored_password(self) -> None:
        """The stock PYNQ image has no passwordless sudo, so `sudo` alone hangs."""
        board = self._password_board()

        with (
            mock.patch.object(
                self.state,
                "_read_remote_pynq_install_status",
                return_value={"installMode": "systemd"},
            ),
            mock.patch.object(self.state, "_run_ssh") as run_ssh,
            mock.patch.object(self.state, "_run_ssh_sudo", return_value="") as run_sudo,
            mock.patch.object(self.state, "_wait_for_board_agent_health"),
            mock.patch.object(
                self.state,
                "_refresh_pynq_board_preflight",
                return_value={"board": {"state": "ready"}},
            ),
        ):
            self.state.restart_pynq_runtime(board["id"])

        self.assertEqual(
            [call.args[1] for call in run_sudo.call_args_list],
            ["systemctl restart neurochip-pynq-agent.service"],
        )
        self.assertFalse(
            [call for call in run_ssh.call_args_list if "sudo" in call.args[1]]
        )
