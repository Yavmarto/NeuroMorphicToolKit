"""Launcher control service tests: TestLauncherHardwareSettings."""

from typing import Any
from pathlib import Path
import io
import json
import nmtk.launcher_control.server as launcher_server
from unittest import mock
import nmtk.launcher_control.provisioning_helpers as provisioning_helpers
import subprocess
import sys
from base import LauncherControlServiceTestBase


class TestLauncherHardwareSettings(LauncherControlServiceTestBase):
    def test_legacy_akida_control_url_migrates_off_suite_launcher_port(self) -> None:
        created = self.state.create_akida_host(
            {
                "displayName": "Legacy Akida",
                "host": "192.168.68.53",
                "runtimeApiUrl": "http://192.168.68.53:8002",
                "controlApiUrl": "http://192.168.68.53:8090",
            }
        )

        self.assertEqual(created["runtimeApiUrl"], "http://192.168.68.53:8002")
        self.assertEqual(created["controlApiUrl"], "http://192.168.68.53:8091")

    def test_akida_host_round_trip_updates_settings_file(self) -> None:
        created = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "akida-box.local:8002",
                "credentialRef": "launcher-secret",
            }
        )

        self.assertEqual(created["displayName"], "Lab Akida")
        self.assertEqual(created["host"], "akida-box.local")
        self.assertEqual(created["port"], 8002)
        self.assertEqual(created["baseUrl"], "http://akida-box.local:8002")
        self.assertEqual(created["state"], "unknown")
        self.assertEqual(self.state.get_akida_host(created["id"])["id"], created["id"])
        self.assertEqual(len(self.state.list_akida_hosts()), 1)

        persisted = json.loads(
            (
                self.repo_root / "nmtk" / "neuro_toolkit" / "launcher_settings.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(len(persisted["akidaHosts"]), 1)
        self.assertEqual(
            persisted["akidaHosts"][0]["baseUrl"], "http://akida-box.local:8002"
        )
        self.assertEqual(
            persisted["akidaHosts"][0]["credentialRef"],
            "launcher-secret",
        )

    def test_akida_host_update_rewrites_host_from_base_url(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        updated = self.state.update_akida_host(
            host["id"],
            {
                "baseUrl": "https://gpu-node.internal:9443",
            },
        )

        self.assertEqual(updated["host"], "gpu-node.internal")
        self.assertEqual(updated["port"], 9443)
        self.assertEqual(updated["baseUrl"], "https://gpu-node.internal:9443")

    def test_akida_host_update_keeps_stored_password_when_omitted(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "password",
                "password": "secret",
            }
        )

        updated = self.state.update_akida_host(
            host["id"],
            {
                "username": "operator-updated",
            },
        )

        self.assertEqual(updated["username"], "operator-updated")
        self.assertTrue(updated["hasPassword"])
        self.assertEqual(
            self.state._get_akida_host(host["id"])["password"],
            "secret",
        )

    def test_akida_host_update_keeps_password_when_omitted_and_coerces_ssh_auth(
        self,
    ) -> None:
        # An *absent* password key keeps the stored one, because the merge starts
        # from the existing host. This is what a client sends when the user leaves
        # the masked password field untouched.
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "none",
                "password": "secret",
            }
        )

        updated = self.state.update_akida_host(
            host["id"],
            {"username": "operator"},
        )

        self.assertEqual(updated["authMode"], "password")
        self.assertTrue(updated["hasPassword"])
        stored = self.state._get_akida_host(host["id"])
        self.assertEqual(stored["password"], "secret")
        self.assertEqual(stored["authMode"], "password")

    def test_akida_host_update_clears_password_when_explicitly_blank(self) -> None:
        # An explicitly empty password clears it. Conflating this with "omitted"
        # meant a saved password could be set but never removed, and forced the
        # client to overload "" as "unchanged" — which is how a typed password
        # could go missing.
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "password",
                "password": "secret",
            }
        )

        updated = self.state.update_akida_host(
            host["id"],
            {"password": ""},
        )

        self.assertFalse(updated["hasPassword"])
        self.assertEqual(self.state._get_akida_host(host["id"])["password"], "")

    def test_internal_host_field_updates_never_touch_the_password(self) -> None:
        # Every internal caller of _update_akida_host_fields omits the key, so
        # state/message churn must not disturb the stored credential.
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "password",
                "password": "secret",
            }
        )

        self.state._update_akida_host_fields(
            host["id"],
            state="reachable",
            lastReadinessMessage="SSH reachable",
        )

        self.assertEqual(self.state._get_akida_host(host["id"])["password"], "secret")

    def test_delete_akida_host_removes_entry_from_settings_file(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        self.state.delete_akida_host(host["id"])

        persisted = json.loads(
            (
                self.repo_root / "nmtk" / "neuro_toolkit" / "launcher_settings.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(persisted["akidaHosts"], [])

    def test_pynq_board_round_trip_updates_settings_file(self) -> None:
        created = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "sshPort": 22,
                "username": "xilinx",
                "authMode": "password",
                "password": "secret",
            }
        )

        self.assertEqual(created["displayName"], "Desk PYNQ")
        self.assertEqual(created["state"], "unpaired")
        self.assertTrue(created["hasPassword"])
        self.assertEqual(
            created["remoteInstallRoot"],
            "/home/xilinx/.local/share/neurochip-pynq-agent",
        )

        persisted = json.loads(
            (
                self.repo_root / "nmtk" / "neuro_toolkit" / "launcher_settings.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(len(persisted["pynqBoards"]), 1)
        self.assertEqual(persisted["pynqBoards"][0]["host"], "192.168.1.50")
        self.assertEqual(persisted["pynqBoards"][0]["password"], "secret")
        self.assertEqual(
            persisted["pynqBoards"][0]["remoteInstallRoot"],
            "/home/xilinx/.local/share/neurochip-pynq-agent",
        )

    def test_pynq_board_defaults_can_come_from_neurochip_manifest_contract(
        self,
    ) -> None:
        manifest_path = (
            self.repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest.append(
            {
                "id": "Neurochip",
                "name": "NeuroChip",
                "description": "Hardware runtime",
                "installPath": "Neurochip",
                "launcherRuntime": {
                    "pynq": {
                        "runtimePort": 9102,
                        "sshPort": 2222,
                        "defaultUsername": "operator",
                        "defaultState": "reachable",
                        "defaultAuthMode": "ssh_key",
                        "legacyInstallRoot": "/opt/legacy-agent",
                        "installRootTemplate": "/srv/pynq/{username}",
                        "agentVenvDirName": "agent-env",
                        "runtimeVenvDirName": "runtime-env",
                        "overlayDirName": "bitfiles",
                        "serviceName": "custom-pynq-service",
                        "agentExecutableName": "custom-pynq-agent",
                        "installStatusFilename": "status.json",
                        "runtimeLogFilename": "agent.log",
                    }
                },
            }
        )
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.state.shutdown()
        self.state = launcher_server.LauncherControlState(
            remote_version_resolver=self._resolve_remote_version
        )

        created = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
            }
        )

        self.assertEqual(created["sshPort"], 2222)
        self.assertEqual(created["username"], "operator")
        self.assertEqual(created["authMode"], "ssh_key")
        self.assertEqual(created["state"], "reachable")
        self.assertEqual(created["runtimeApiUrl"], "http://192.168.1.50:9102")
        self.assertEqual(created["remoteInstallRoot"], "/srv/pynq/operator")
        self.assertEqual(created["remoteVenvPath"], "/srv/pynq/operator/agent-env")
        self.assertEqual(
            created["remotePynqVenvPath"], "/srv/pynq/operator/runtime-env"
        )
        self.assertEqual(created["remoteOverlayDir"], "/srv/pynq/operator/bitfiles")
        self.assertEqual(
            created["remoteInstallStatusPath"], "/srv/pynq/operator/status.json"
        )
        self.assertEqual(
            created["remoteRuntimeLogPath"], "/srv/pynq/operator/agent.log"
        )
        self.assertEqual(created["remoteServiceName"], "custom-pynq-service")
        self.assertEqual(created["agentExecutableName"], "custom-pynq-agent")

    def test_akida_host_with_capabilities_round_trip_updates_settings_file(
        self,
    ) -> None:
        created = self.state.create_akida_host(
            {
                "displayName": "Linux Akida Host",
                "runtimeApiUrl": "http://192.168.1.60:8002",
                "authMode": "bearer_token",
                "credentialRef": "akida-token",
                "hostOs": "linux",
                "pythonVersion": "3.11.8",
                "runtimeMode": "remote_sdk",
                "state": "ready",
                "lastReadinessMessage": "Remote SDK ready",
                "capabilitySnapshot": {
                    "hostSupported": True,
                    "pythonSupported": True,
                    "tensorflowAvailable": True,
                    "cnn2snnAvailable": True,
                    "akidaModelsAvailable": True,
                    "recommendedRuntime": "remote_sdk",
                },
            }
        )

        self.assertEqual(created["displayName"], "Linux Akida Host")
        self.assertEqual(created["state"], "ready")
        self.assertEqual(created["runtimeMode"], "remote_sdk")
        self.assertEqual(
            created["capabilitySnapshot"]["recommendedRuntime"], "remote_sdk"
        )

        persisted = json.loads(
            (
                self.repo_root / "nmtk" / "neuro_toolkit" / "launcher_settings.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(len(persisted["akidaHosts"]), 1)
        self.assertEqual(
            persisted["akidaHosts"][0]["runtimeApiUrl"],
            "http://192.168.1.60:8002",
        )
        self.assertEqual(persisted["selectedAkidaHostId"], created["id"])

        reloaded = launcher_server.LauncherControlState()
        self.addCleanup(reloaded.shutdown)

        settings = reloaded.get_settings()
        self.assertEqual(settings["selectedAkidaHostId"], created["id"])
        self.assertEqual(settings["akidaHosts"][0]["hostOs"], "linux")
        self.assertEqual(settings["akidaHosts"][0]["pythonVersion"], "3.11.8")

    def test_akida_host_defaults_can_come_from_neurochip_manifest_contract(
        self,
    ) -> None:
        manifest_path = (
            self.repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest.append(
            {
                "id": "Neurochip",
                "name": "NeuroChip",
                "description": "Hardware runtime",
                "installPath": "Neurochip",
                "launcherRuntime": {
                    "akida": {
                        "runtimePort": 9102,
                        "controlPort": 9190,
                        "sshPort": 2200,
                        "defaultState": "pending",
                        "defaultAuthMode": "ssh_key",
                        "installRoot": "/srv/akida-host",
                        "serviceUser": "runtime-user",
                        "venvDirName": "akida-venv",
                        "runtimeServiceName": "akida-runtime",
                        "controlServiceName": "akida-control",
                        "tokenRelativePath": "secrets/token.txt",
                        "installStatusRelativePath": "state/install.json",
                    }
                },
            }
        )
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
        self.state.shutdown()
        self.state = launcher_server.LauncherControlState(
            remote_version_resolver=self._resolve_remote_version
        )

        created = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
            }
        )

        self.assertEqual(created["port"], 9102)
        self.assertEqual(created["controlPort"], 9190)
        self.assertEqual(created["sshPort"], 2200)
        self.assertEqual(created["authMode"], "ssh_key")
        self.assertEqual(created["state"], "pending")
        self.assertEqual(created["baseUrl"], "http://akida-box.local:9102")
        self.assertEqual(created["runtimeApiUrl"], "http://akida-box.local:9102")
        self.assertEqual(created["controlApiUrl"], "http://akida-box.local:9190")
        self.assertEqual(created["remoteInstallRoot"], "/srv/akida-host")
        self.assertEqual(created["remoteVenvPath"], "/srv/akida-host/akida-venv")
        self.assertEqual(created["serviceUser"], "runtime-user")
        self.assertEqual(created["runtimeServiceName"], "akida-runtime")
        self.assertEqual(created["controlServiceName"], "akida-control")
        self.assertEqual(created["tokenPath"], "/srv/akida-host/secrets/token.txt")
        self.assertEqual(
            created["installStatusPath"], "/srv/akida-host/state/install.json"
        )

    def test_akida_host_update_delete_and_selection_round_trip(self) -> None:
        primary = self.state.create_akida_host(
            {
                "displayName": "Primary Host",
                "runtimeApiUrl": "http://192.168.1.60:8002",
            }
        )
        secondary = self.state.create_akida_host(
            {
                "displayName": "Secondary Host",
                "runtimeApiUrl": "http://192.168.1.61:8002",
                "state": "pending",
            }
        )

        settings = self.state.update_settings({"selectedAkidaHostId": secondary["id"]})
        self.assertEqual(settings["selectedAkidaHostId"], secondary["id"])

        updated = self.state.update_akida_host(
            secondary["id"],
            {
                "state": "simulator_only",
                "runtimeMode": "simulator_only",
                "hostOs": "macos",
                "pythonVersion": "3.12.1",
            },
        )
        self.assertEqual(updated["state"], "simulator_only")
        self.assertEqual(updated["runtimeMode"], "simulator_only")
        self.assertEqual(updated["hostOs"], "macos")
        self.assertEqual(updated["pythonVersion"], "3.12.1")

        self.state.delete_akida_host(secondary["id"])
        remaining = self.state.get_settings()
        self.assertEqual(len(remaining["akidaHosts"]), 1)
        self.assertEqual(remaining["akidaHosts"][0]["id"], primary["id"])
        self.assertEqual(remaining["selectedAkidaHostId"], primary["id"])

    def test_pynq_board_normalization_migrates_legacy_opt_paths(self) -> None:
        created = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "remoteInstallRoot": "/opt/neurochip-pynq-agent",
                "remoteVenvPath": "/opt/neurochip-pynq-agent/venv",
                "remoteOverlayDir": "/opt/neurochip-pynq-agent/overlays",
            }
        )

        self.assertEqual(
            created["remoteInstallRoot"],
            "/home/xilinx/.local/share/neurochip-pynq-agent",
        )
        self.assertEqual(
            created["remoteVenvPath"],
            "/home/xilinx/.local/share/neurochip-pynq-agent/venv",
        )
        self.assertEqual(
            created["remotePynqVenvPath"],
            "/home/xilinx/.local/share/neurochip-pynq-agent/pynq-venv",
        )
        self.assertEqual(
            created["remoteOverlayDir"],
            "/home/xilinx/.local/share/neurochip-pynq-agent/overlays",
        )

    def test_pynq_board_normalization_clears_legacy_runtime_url_when_it_matches_default(
        self,
    ) -> None:
        created = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "runtimeApiUrl": "http://192.168.1.50:8002",
            }
        )

        self.assertEqual(created["runtimeApiUrl"], "http://192.168.1.50:8002")
        self.assertEqual(created["runtimeApiUrlOverride"], "")

    def test_pynq_board_normalization_preserves_custom_legacy_runtime_url_as_override(
        self,
    ) -> None:
        created = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "runtimeApiUrl": "http://192.168.1.99:8002",
            }
        )

        self.assertEqual(created["runtimeApiUrl"], "http://192.168.1.99:8002")
        self.assertEqual(
            created["runtimeApiUrlOverride"],
            "http://192.168.1.99:8002",
        )

    def test_pynq_board_host_update_recomputes_effective_runtime_url_without_override(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.2.50",
            }
        )

        updated = self.state.update_pynq_board(
            board["id"],
            {
                "host": "192.168.2.53",
            },
        )

        self.assertEqual(updated["runtimeApiUrl"], "http://192.168.2.53:8002")
        self.assertEqual(updated["runtimeApiUrlOverride"], "")

    def test_pynq_board_update_clearing_override_resets_effective_runtime_url(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.2.50",
                "runtimeApiUrlOverride": "http://192.168.2.99:8002",
            }
        )

        updated = self.state.update_pynq_board(
            board["id"],
            {
                "host": "192.168.2.53",
                "runtimeApiUrlOverride": "",
            },
        )

        self.assertEqual(updated["runtimeApiUrl"], "http://192.168.2.53:8002")
        self.assertEqual(updated["runtimeApiUrlOverride"], "")

    def test_pynq_board_connectivity_updates_board_state(self) -> None:
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

        with mock.patch.object(self.state, "_run_ssh") as run_ssh:
            updated = self.state.test_pynq_board_connection(board["id"])

        run_ssh.assert_called_once()
        self.assertEqual(updated["state"], "reachable")

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

            def wait(self) -> int:
                return 255

        with mock.patch.object(
            launcher_server.subprocess,
            "Popen",
            return_value=_FakeProcess(),
        ):
            with self.assertRaisesRegex(
                RuntimeError, "install script failed on remote host"
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

    def test_akida_host_connectivity_marks_host_reachable(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={"status": "ok"},
        ) as request:
            updated = self.state.test_akida_host_connection(host["id"])

        self.assertEqual(updated["state"], "reachable")
        self.assertEqual(updated["lastPreflightMessage"], "Health reachable: ok")
        request.assert_called_once()

    def test_akida_host_preflight_reports_degraded_optional_capability(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={
                "sdk_available": False,
                "sdk_status": "sdk_unavailable",
                "sdk_issues": ["sdk_not_available", "unsupported_os"],
                "sdk_issue_detail": "BrainChip SDK missing on remote host",
                "runtime_target": "local_sdk",
                "environment_checks": {
                    "host_supported": False,
                    "python_supported": True,
                    "tensorflow_available": False,
                    "cnn2snn_available": False,
                    "akida_models_available": False,
                    "recommended_runtime": "local_sdk",
                },
            },
        ):
            result = self.state.fetch_akida_host_preflight(host["id"])

        self.assertEqual(
            result["host"]["state"],
            "degraded_optional_capability",
        )
        self.assertEqual(
            result["preflight"]["preflight_status"],
            launcher_server.PREFLIGHT_DEGRADED,
        )
        self.assertEqual(
            result["preflight"]["preflight_message"],
            "BrainChip SDK missing on remote host",
        )
        self.assertEqual(result["host"]["lastSdkStatus"], "sdk_unavailable")

    def _akida_probe_verdict(self, probe: dict[str, Any], usb: str = "") -> str:
        """Run the generated remote doctor's classifier on one probe result.

        The classifier ships inside the remote script text, so exec'ing the
        generated source is what actually proves the shipped copy behaves —
        importing a parallel implementation would not.
        """
        namespace: dict[str, Any] = {}
        exec(  # noqa: S102
            provisioning_helpers._remote_control_script_text().split(
                "def _local_json"
            )[0],
            namespace,
        )
        return str(namespace["_akida_device_message"](probe, usb))

    def test_remote_doctor_names_the_hardware_fault_it_finds(self) -> None:
        absent = self._akida_probe_verdict({"present": False})
        unbound = self._akida_probe_verdict({"present": True, "driver": ""})
        wedged = self._akida_probe_verdict(
            {"present": True, "driver": "akida-pcie", "memorySpaceEnabled": False}
        )
        healthy = self._akida_probe_verdict(
            {"present": True, "driver": "akida-pcie", "memorySpaceEnabled": True}
        )

        self.assertIn("No Akida board", absent)
        self.assertIn("PCIe driver is not loaded", unbound)
        # The probe is PCI-only, so a USB Akida is absent from it. Claiming
        # "no board" there would be a confident lie; keep the SDK's own words.
        self.assertEqual(
            self._akida_probe_verdict(
                {"present": False},
                "Bus 002 Device 004: ID 1e7c:1000 BrainChip Akida USB",
            ),
            "",
        )
        self.assertIn("stopped responding", wedged)
        self.assertIn("off and on again", wedged)
        # Empty means "not a hardware fault", so a genuine SDK problem keeps
        # its own detail instead of being masked by a board verdict.
        self.assertEqual(healthy, "")

    def test_raw_device_errno_never_reaches_the_readiness_message(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )
        raw = "Error reading at 0xf0000010 len 4: err(110) Connection timed out"

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={
                "sdk_available": True,
                "sdk_status": "unknown",
                "sdk_issues": ["device_mapping_failure"],
                "sdk_issue_detail": raw,
                "runtime_target": "unknown",
            },
        ):
            result = self.state.fetch_akida_host_preflight(host["id"])

        readiness = result["host"]["lastReadinessMessage"]
        self.assertNotIn("0xf0000010", readiness)
        self.assertNotIn("err(110)", readiness)
        self.assertIn("off and on again", readiness)
        # The raw text is the developer's copy and must survive untouched; no
        # Akida client model reads lastPreflightMessage.
        self.assertEqual(result["host"]["lastPreflightMessage"], raw)

    def test_plain_language_preflight_messages_are_left_alone(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )
        message = "An Akida board is fitted but its PCIe driver is not loaded."

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={
                "sdk_available": True,
                "sdk_status": "unknown",
                "sdk_issues": ["device_mapping_failure"],
                "sdk_issue_detail": message,
                "runtime_target": "unknown",
            },
        ):
            result = self.state.fetch_akida_host_preflight(host["id"])

        self.assertEqual(result["host"]["lastReadinessMessage"], message)

    def test_akida_host_preflight_reports_failed_when_runtime_request_errors(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            side_effect=RuntimeError("remote verify exploded"),
        ):
            result = self.state.fetch_akida_host_preflight(host["id"])

        self.assertEqual(result["host"]["state"], "preflight_failed")
        self.assertEqual(
            result["preflight"]["preflight_status"],
            launcher_server.PREFLIGHT_FAILED,
        )
        self.assertIn(
            "remote verify exploded", result["preflight"]["preflight_message"]
        )

    def test_akida_remote_control_doctor_accepts_visible_hardware_before_model_mapping(
        self,
    ) -> None:
        namespace: dict[str, Any] = {}
        exec(provisioning_helpers._remote_control_script_text(), namespace)

        def fake_local_json(path: str) -> tuple[int, dict[str, Any]]:
            if path == "/health":
                return 200, {"status": "healthy"}
            if path == "/api/neurochip/akida/status":
                return 200, {
                    "sdk_available": True,
                    "sdk_status": "unknown",
                    "sdk_issues": [],
                    "sdk_issue_detail": None,
                    "runtime_target": "hardware",
                    "device_info": "<akida.core.HardwareDevice object>",
                    "environment_checks": {
                        "host_supported": True,
                        "python_supported": True,
                        "tensorflow_available": True,
                        "cnn2snn_available": True,
                        "akida_models_available": True,
                        "recommended_runtime": "local_sdk",
                    },
                }
            raise AssertionError(f"unexpected path: {path}")

        namespace["_local_json"] = fake_local_json
        namespace["_run_probe"] = lambda _command: ""
        namespace["_load_install_status"] = lambda: {"installMode": "systemd"}

        payload = namespace["_doctor_payload"]()

        self.assertEqual(
            payload["preflight"]["preflight_status"], launcher_server.PREFLIGHT_OK
        )
        self.assertEqual(
            payload["preflight"]["preflight_message"],
            "Akida hardware runtime is ready.",
        )
        self.assertTrue(payload["preflight"]["physicalHardwareReady"])

    def test_akida_install_script_force_reinstalls_bundled_neurochip_wheel(
        self,
    ) -> None:
        script = provisioning_helpers._akida_install_script_text(
            install_root="/opt/neurochip-akida-host",
            service_user="neurochip",
            venv_path="/opt/neurochip-akida-host/venv",
            runtime_service_name="neurochip",
            control_service_name="neurochip-akida-control",
            runtime_port=8002,
            control_port=8091,
            token_path="/opt/neurochip-akida-host/credentials/api-token",
            install_status_path="/opt/neurochip-akida-host/install-status.json",
            wheel_name="neurochip-0.6.0-py3-none-any.whl",
            artifact_version="0.6.0",
            artifact_sha256="a" * 64,
            required_packages=[],
        )

        self.assertIn("akida_pip install --force-reinstall", script)
        self.assertNotIn("akida_pip install --force-reinstall --no-deps", script)

    def test_akida_preflight_promotes_stale_remote_doctor_when_hardware_is_ready(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
            }
        )
        runtime_status = {
            "sdk_available": True,
            "sdk_status": "unknown",
            "sdk_issues": [],
            "runtime_target": "hardware",
        }

        updated = self.state._apply_preflight_to_akida_host(
            host["id"],
            {
                "preflight_status": launcher_server.PREFLIGHT_DEGRADED,
                "preflight_message": "Optional Akida capability is degraded.",
                "runtime_target": "hardware",
                "sdk_status": "unknown",
            },
            runtime_status=runtime_status,
            install_status={"installMode": "systemd"},
        )

        self.assertEqual(updated["state"], "ready")
        self.assertEqual(updated["lastPreflightStatus"], launcher_server.PREFLIGHT_OK)
        self.assertEqual(
            updated["lastPreflightMessage"], "Akida hardware runtime is ready."
        )

    def test_akida_host_preflight_fallback_logs_single_high_level_message(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "controlApiUrl": "http://akida-box.local:8091",
            }
        )

        stderr = io.StringIO()
        fallback_calls: list[tuple[str, str]] = []

        def _record_runtime_status(
            _host: dict[str, Any], method: str, path: str
        ) -> dict[str, Any]:
            fallback_calls.append((method, path))
            return {
                "sdk_available": False,
                "sdk_status": "sdk_unavailable",
                "sdk_issues": ["sdk_not_available"],
                "sdk_issue_detail": "BrainChip SDK missing on remote host",
                "runtime_target": "local_sdk",
                "environment_checks": {
                    "host_supported": False,
                    "python_supported": True,
                    "tensorflow_available": False,
                    "cnn2snn_available": False,
                    "akida_models_available": False,
                    "recommended_runtime": "local_sdk",
                },
            }

        with (
            mock.patch.object(
                self.state,
                "_akida_control_json_request",
                side_effect=RuntimeError(
                    "Control request failed for GET http://akida-box.local:8090/api/remote-akida/doctor: offline"
                ),
            ),
            mock.patch.object(
                self.state,
                "_akida_json_request",
                side_effect=_record_runtime_status,
            ),
            mock.patch.object(sys, "stderr", stderr),
        ):
            self.state.fetch_akida_host_preflight(host["id"])

        log_output = stderr.getvalue()
        self.assertEqual(fallback_calls, [("GET", "/api/neurochip/akida/status")])
        self.assertIn("remote control API unavailable during preflight", log_output)
        self.assertIn("falling back to runtime status", log_output)
        self.assertNotIn("control request failed:", log_output)

    def test_akida_host_status_fallback_logs_single_high_level_message(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "controlApiUrl": "http://akida-box.local:8091",
                "lastPreflightStatus": launcher_server.PREFLIGHT_OK,
            }
        )

        stderr = io.StringIO()
        with (
            mock.patch.object(
                self.state,
                "_akida_control_json_request",
                side_effect=RuntimeError(
                    "Control request failed for GET http://akida-box.local:8090/api/remote-akida/doctor: offline"
                ),
            ),
            mock.patch.object(
                self.state,
                "_akida_json_request",
                return_value={"state": "mapped", "device_info": "AKD1000"},
            ),
            mock.patch.object(sys, "stderr", stderr),
        ):
            result = self.state.fetch_akida_host_status(host["id"])

        self.assertEqual(result["host"]["state"], "ready")
        log_output = stderr.getvalue()
        self.assertIn("remote control API unavailable during status poll", log_output)
        self.assertNotIn("control request failed:", log_output)

    def test_akida_host_status_marks_mapped_host_ready(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "lastPreflightStatus": launcher_server.PREFLIGHT_OK,
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={"state": "mapped", "device_info": "AKD1000"},
        ):
            result = self.state.fetch_akida_host_status(host["id"])

        self.assertEqual(result["host"]["state"], "ready")
        self.assertEqual(result["status"]["state"], "mapped")

    def test_akida_host_status_marks_failed_host_error(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={"state": "failed"},
        ):
            result = self.state.fetch_akida_host_status(host["id"])

        self.assertEqual(result["host"]["state"], "error")
        self.assertEqual(result["status"]["state"], "failed")

    def test_doctor_report_includes_akida_hosts(self) -> None:
        self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "state": "degraded_optional_capability",
                "lastPreflightStatus": launcher_server.PREFLIGHT_DEGRADED,
                "lastPreflightMessage": "BrainChip SDK missing on remote host",
            }
        )

        with mock.patch.object(
            self.state,
            "_preflight_module",
            return_value=launcher_server.PreflightResult(
                status=launcher_server.PREFLIGHT_OK,
                message="ok",
                environment_fingerprint="fingerprint-4",
            ),
        ):
            report = self.state.doctor_report()

        self.assertIn("akidaHosts", report)
        self.assertEqual(
            report["akidaHosts"][0]["state"],
            "degraded_optional_capability",
        )
        self.assertGreaterEqual(report["degradedCount"], 1)

    def test_doctor_report_includes_pynq_boards(self) -> None:
        self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "state": "ready",
                "lastPreflightStatus": "ok",
            }
        )

        with mock.patch.object(
            self.state,
            "_preflight_module",
            return_value=launcher_server.PreflightResult(
                status=launcher_server.PREFLIGHT_OK,
                message="ok",
                environment_fingerprint="fingerprint-3",
            ),
        ):
            report = self.state.doctor_report()

        self.assertIn("pynqBoards", report)
        self.assertEqual(report["pynqBoards"][0]["state"], "ready")

    def test_doctor_report_includes_ready_remote_sdk_akida_hosts(self) -> None:
        self.state.create_akida_host(
            {
                "displayName": "Linux Akida Host",
                "runtimeApiUrl": "http://192.168.1.60:8002",
                "runtimeMode": "remote_sdk",
                "state": "ready",
            }
        )

        with mock.patch.object(
            self.state,
            "_preflight_module",
            return_value=launcher_server.PreflightResult(
                status=launcher_server.PREFLIGHT_OK,
                message="ok",
                environment_fingerprint="fingerprint-3",
            ),
        ):
            report = self.state.doctor_report()

        self.assertIn("akidaHosts", report)
        self.assertEqual(report["akidaHosts"][0]["runtimeMode"], "remote_sdk")
        self.assertEqual(report["akidaHosts"][0]["state"], "ready")
