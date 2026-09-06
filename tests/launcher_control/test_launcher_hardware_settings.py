"""Launcher control service tests: hardware settings CRUD (akida hosts, pynq boards, normalization, selection round trips)."""

import json
from unittest import mock

from base import LauncherControlServiceTestBase

import nmtk.launcher_control.server as launcher_server


class TestLauncherHardwareSettings(LauncherControlServiceTestBase):
    def test_legacy_akida_control_url_migrates_off_suite_launcher_port(self) -> None:
        created = self.state.create_akida_host(
            {
                "displayName": "Legacy Akida",
                "host": "192.168.2.90",
                "runtimeApiUrl": "http://192.168.2.90:8002",
                "controlApiUrl": "http://192.168.2.90:8090",
            }
        )

        self.assertEqual(created["runtimeApiUrl"], "http://192.168.2.90:8002")
        self.assertEqual(created["controlApiUrl"], "http://192.168.2.90:8091")

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
