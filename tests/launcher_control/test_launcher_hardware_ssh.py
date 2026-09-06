"""Launcher control service tests: hardware SSH/SCP transport (askpass, known-host warnings, user-space agent restart)."""

import re
import subprocess
from pathlib import Path
from typing import Any
from unittest import mock

from base import LauncherControlServiceTestBase

import nmtk.launcher_control.server as launcher_server
from nmtk.launcher_control import provisioning_helpers


class TestLauncherHardwareSsh(LauncherControlServiceTestBase):
    def test_run_ssh_password_auth_uses_askpass_without_sshpass(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "sshPort": 22,
                "username": "xilinx",
                "authMode": "password",
                "password": "secret",
            }
        )
        with mock.patch.object(launcher_server.shutil, "which", return_value=None):
            command, env, cleanup = self.state._prepare_ssh_invocation(
                self.state._get_pynq_board(board["id"]),
            )

        self.assertNotIn("sshpass", command)
        self.assertIsNotNone(env)
        assert env is not None
        self.assertEqual(env["NMTK_PYNQ_PASSWORD"], "secret")
        self.assertIn("SSH_ASKPASS", env)
        askpass_path = Path(env["SSH_ASKPASS"])
        self.assertTrue(askpass_path.exists())
        self.assertIsNotNone(cleanup)
        assert cleanup is not None
        cleanup()
        self.assertFalse(askpass_path.exists())

    def test_run_ssh_ignores_benign_known_host_warning_as_primary_failure_reason(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "sshPort": 22,
                "username": "xilinx",
                "authMode": "ssh_key",
                "sshKeyPath": "/Users/test/.ssh/pynq",
            }
        )

        class _FakeStream:
            def __init__(self, lines: list[str]) -> None:
                self._lines = [f"{line}\n" for line in lines]
                self._index = 0

            def readline(self) -> str:
                if self._index >= len(self._lines):
                    return ""
                line = self._lines[self._index]
                self._index += 1
                return line

            def close(self) -> None:
                return None

        class _FakeProcess:
            def __init__(self) -> None:
                self.stdout = _FakeStream(["install script failed on remote host"])
                self.stderr = _FakeStream(
                    [
                        "Warning: Permanently added '192.168.1.50' (ED25519) to the list of known hosts."
                    ]
                )

            def wait(self, timeout: float | None = None) -> int:
                del timeout
                return 255

            def kill(self) -> None:
                return None

        with (
            mock.patch.object(
                launcher_server.subprocess,
                "Popen",
                return_value=_FakeProcess(),
            ),
            self.assertRaisesRegex(
                RuntimeError, "install script failed on remote host"
            ),
        ):
            self.state._run_ssh(
                self.state._get_pynq_board(board["id"]),
                "bash /tmp/install.sh",
            )

    def test_run_scp_password_auth_uses_askpass_without_sshpass(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "sshPort": 22,
                "username": "xilinx",
                "authMode": "password",
                "password": "secret",
            }
        )
        local_file = self.repo_root / "bundle.txt"
        local_file.write_text("bundle", encoding="utf-8")
        with (
            mock.patch.object(launcher_server.shutil, "which", return_value=None),
            mock.patch.object(
                launcher_server.subprocess,
                "run",
                return_value=subprocess.CompletedProcess(["scp"], 0, "", ""),
            ) as run_mock,
        ):
            self.state._run_scp(
                self.state._get_pynq_board(board["id"]),
                local_file,
                "/tmp/bundle.txt",
            )
            run_mock.assert_called_once()
            _, kwargs = run_mock.call_args
            self.assertIn("NMTK_PYNQ_PASSWORD", kwargs.get("env", {}))

    def test_run_ssh_detached_ignores_benign_known_host_warning(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "authMode": "ssh_key",
                "sshKeyPath": "/Users/test/.ssh/pynq",
            }
        )

        with mock.patch.object(
            launcher_server.subprocess,
            "run",
            return_value=subprocess.CompletedProcess(
                ["ssh"],
                255,
                "",
                "Warning: Permanently added '192.168.1.50' (ED25519) to the list of known hosts.\n",
            ),
        ):
            self.state._run_ssh_detached(
                self.state._get_pynq_board(board["id"]),
                "true",
            )

    def test_restart_user_space_agent_uses_shared_neurochip_launch_command(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )
        install_status = {
            "agentVenvPath": "/home/xilinx/.local/share/neurochip-pynq-agent/venv",
            "pynqVenvPath": "/home/xilinx/.local/share/neurochip-pynq-agent/pynq-venv",
            "runtimeLogPath": "/home/xilinx/.local/share/neurochip-pynq-agent/runtime.log",
        }

        with (
            mock.patch.object(
                self.state, "_run_ssh", return_value="running"
            ) as run_ssh,
            mock.patch.object(self.state, "_run_ssh_detached") as run_ssh_detached,
            mock.patch.object(self.state, "_wait_for_board_agent_health"),
        ):
            self.state._restart_user_space_agent(
                self.state._get_pynq_board(board["id"]),
                install_status,
            )

        remote_command = run_ssh_detached.call_args.args[1]
        self.assertIn("command -v setsid >/dev/null 2>&1", remote_command)
        self.assertIn("setsid sh -c", remote_command)
        self.assertIn("nohup sh -c", remote_command)
        self.assertNotIn("nohup env", remote_command)
        # Stop and start must not ride in one command: `pkill -f` matches whole
        # command lines, so a combined string kills the shell that was about to
        # run the start half and the agent never comes back.
        self.assertNotIn("pkill", remote_command)
        stop_command = run_ssh.call_args_list[0].args[1]
        self.assertIn("pkill -f", stop_command)
        self.assertNotIn("setsid", stop_command)

    def test_restart_user_space_agent_stop_pattern_cannot_match_its_own_shell(
        self,
    ) -> None:
        """The bug, stated directly: the pattern must not match the text carrying it."""
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(
                self.state, "_run_ssh", return_value="running"
            ) as run_ssh,
            mock.patch.object(self.state, "_run_ssh_detached"),
            mock.patch.object(self.state, "_wait_for_board_agent_health"),
        ):
            self.state._restart_user_space_agent(
                self.state._get_pynq_board(board["id"]),
                {"agentVenvPath": "/opt/agent"},
            )

        stop_command = run_ssh.call_args_list[0].args[1]
        pattern = re.search(r"pkill -f '([^']+)'", stop_command)
        self.assertIsNotNone(pattern)
        self.assertIsNone(re.search(pattern.group(1), stop_command))
        # …while still matching a real agent command line.
        self.assertIsNotNone(
            re.search(pattern.group(1), "/opt/agent/bin/neurochip-pynq-agent")
        )

    def test_restart_user_space_agent_uses_the_interpreter_the_install_chose(
        self,
    ) -> None:
        """The isolated pynq-venv only exists when the canonical one is missing.

        Restarting with it regardless points a working board at a python that is
        not there, and the agent comes back reporting simulator instead of
        hardware.
        """
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(self.state, "_run_ssh", return_value="running"),
            mock.patch.object(self.state, "_run_ssh_detached") as run_ssh_detached,
            mock.patch.object(self.state, "_wait_for_board_agent_health"),
        ):
            self.state._restart_user_space_agent(
                self.state._get_pynq_board(board["id"]),
                {"effectivePynqPython": "/usr/local/share/pynq-venv/bin/python"},
            )

        launch_command = run_ssh_detached.call_args.args[1]
        self.assertIn(
            "NEUROCHIP_PYNQ_PYTHON=/usr/local/share/pynq-venv/bin/python",
            launch_command,
        )
        self.assertNotIn(
            str(self.state._get_pynq_board(board["id"])["remotePynqVenvPath"]),
            launch_command,
        )

    def test_user_space_launch_carries_the_xrt_environment(self) -> None:
        """The stock image sets XRT in /etc/profile.d, which `setsid sh -c` skips.

        Without it pynq warns "No devices found, is the XRT environment sourced?"
        and enumerates nothing, so a user-space agent can never see its own board.
        The systemd unit has always injected these; the user-space launch did not.
        """
        command = provisioning_helpers.build_pynq_user_space_agent_launch_command(
            agent_executable="/opt/agent/bin/neurochip-pynq-agent",
            pynq_python_path="/usr/local/share/pynq-venv/bin/python",
            install_status_path="/tmp/install-status.json",
            overlay_dir="/srv/overlay",
            runtime_log_path="/tmp/runtime.log",
        )

        self.assertIn("XILINX_XRT=/usr", command)
        self.assertIn("LD_LIBRARY_PATH=/usr/lib:", command)
        self.assertIn("BOARD=Pynq-Z2", command)

    def test_restart_grants_device_group_access_before_launching(self) -> None:
        """`/dev/dri/*` is root:video / root:render 0660; the agent user needs both."""
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "password": "board-secret",
            }
        )
        order: list[str] = []

        def fake_run_ssh(board_record: dict[str, Any], command: str) -> str:
            if command == "id -nG":
                return "xilinx adm sudo"
            return "running"

        def fake_sudo(board_record: dict[str, Any], command: str) -> str:
            order.append(f"sudo:{command}")
            return ""

        def fake_detached(board_record: dict[str, Any], command: str) -> None:
            order.append("launch")

        with (
            mock.patch.object(self.state, "_run_ssh", side_effect=fake_run_ssh),
            mock.patch.object(self.state, "_run_ssh_sudo", side_effect=fake_sudo),
            mock.patch.object(
                self.state, "_run_ssh_detached", side_effect=fake_detached
            ),
            mock.patch.object(self.state, "_wait_for_board_agent_health"),
        ):
            self.state._restart_user_space_agent(
                self.state._get_pynq_board(board["id"]),
                {},
            )

        # Membership only reaches new login sessions, so the grant must precede
        # the launch that opens one.
        self.assertEqual(order, ["sudo:usermod -aG video,render xilinx", "launch"])

    def test_restart_skips_the_grant_when_the_user_is_already_in_both_groups(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "password": "board-secret",
            }
        )

        def fake_run_ssh(board_record: dict[str, Any], command: str) -> str:
            if command == "id -nG":
                return "xilinx adm sudo video render"
            return "running"

        with (
            mock.patch.object(self.state, "_run_ssh", side_effect=fake_run_ssh),
            mock.patch.object(self.state, "_run_ssh_sudo") as run_ssh_sudo,
            mock.patch.object(self.state, "_run_ssh_detached"),
            mock.patch.object(self.state, "_wait_for_board_agent_health"),
        ):
            self.state._restart_user_space_agent(
                self.state._get_pynq_board(board["id"]),
                {},
            )

        run_ssh_sudo.assert_not_called()

    def test_failed_device_grant_does_not_block_the_restart(self) -> None:
        """A board that refuses sudo should still get its agent back, with a reason."""
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "password": "board-secret",
            }
        )

        def fake_run_ssh(board_record: dict[str, Any], command: str) -> str:
            if command == "id -nG":
                return "xilinx"
            return "running"

        with (
            mock.patch.object(self.state, "_run_ssh", side_effect=fake_run_ssh),
            mock.patch.object(
                self.state,
                "_run_ssh_sudo",
                side_effect=RuntimeError("sudo: a password is required"),
            ),
            mock.patch.object(self.state, "_run_ssh_detached") as run_ssh_detached,
            mock.patch.object(self.state, "_wait_for_board_agent_health"),
        ):
            self.state._restart_user_space_agent(
                self.state._get_pynq_board(board["id"]),
                {},
            )

        run_ssh_detached.assert_called_once()

    def test_sudo_password_travels_on_stdin_not_in_the_command(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "password": "board-secret",
            }
        )

        completed = subprocess.CompletedProcess(
            args=["ssh"], returncode=0, stdout="", stderr=""
        )
        with mock.patch.object(
            subprocess, "run", return_value=completed
        ) as subprocess_run:
            self.state._run_ssh_sudo(
                self.state._get_pynq_board(board["id"]),
                "usermod -aG video,render xilinx",
            )

        kwargs = subprocess_run.call_args.kwargs
        self.assertEqual(kwargs["input"], "board-secret\n")
        remote_command = subprocess_run.call_args.args[0][-1]
        self.assertEqual(
            remote_command, "sudo -S -p '' usermod -aG video,render xilinx"
        )
        self.assertNotIn("board-secret", remote_command)

    def test_restart_user_space_agent_reports_a_start_that_never_happened(
        self,
    ) -> None:
        """A dead start must not be reported as a slow board 120s later."""
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
            }
        )

        with (
            mock.patch.object(self.state, "_run_ssh", return_value="missing"),
            mock.patch.object(self.state, "_run_ssh_detached"),
            mock.patch.object(
                self.state, "_wait_for_board_agent_health"
            ) as wait_for_health,
            self.assertRaises(RuntimeError) as raised,
        ):
            self.state._restart_user_space_agent(
                self.state._get_pynq_board(board["id"]),
                {},
            )

        self.assertIn("did not start", str(raised.exception))
        wait_for_health.assert_not_called()
