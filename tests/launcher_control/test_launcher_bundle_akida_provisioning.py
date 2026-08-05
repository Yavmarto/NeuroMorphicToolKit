"""Launcher control service tests: TestLauncherBundleAkidaProvisioning."""

from pathlib import Path
import json
import nmtk.launcher_control.server as launcher_server
from unittest import mock
import os
import subprocess
import zipfile
import nmtk.launcher_control.provisioning_helpers as provisioning_helpers
from base import LauncherControlServiceTestBase


class TestLauncherBundleAkidaProvisioning(LauncherControlServiceTestBase):
    @staticmethod
    def _write_test_neurochip_wheel(path: Path, version: str = "1.2.3") -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path, "w") as wheel:
            wheel.writestr(
                f"neurochip-{version}.dist-info/METADATA",
                f"Metadata-Version: 2.1\nName: neurochip\nVersion: {version}\n",
            )

    def test_build_remote_pynq_user_space_launch_command_is_launcher_owned(
        self,
    ) -> None:
        command = self.state._build_remote_pynq_user_space_launch_command(
            agent_venv_path="/opt/agent",
            pynq_venv_path="/opt/pynq",
            install_status_path="/tmp/install-status.json",
            overlay_dir="/srv/overlay",
            runtime_log_path="/tmp/runtime.log",
            agent_executable_name="custom-agent",
        )

        self.assertIn("NEUROCHIP_PYNQ_OVERLAY_DIR=/srv/overlay", command)
        self.assertIn("/tmp/runtime.log", command)
        self.assertNotIn("Neurochip/neurochip/provisioning", command)

    def test_build_remote_pynq_user_space_launch_command_does_not_depend_on_neurochip_files(
        self,
    ) -> None:
        original_exists = Path.exists

        def fake_exists(path: Path) -> bool:
            if "Neurochip/neurochip/provisioning" in str(path):
                return False
            return original_exists(path)

        with mock.patch.object(Path, "exists", autospec=True, side_effect=fake_exists):
            command = self.state._build_remote_pynq_user_space_launch_command(
                agent_venv_path="/opt/agent",
                pynq_venv_path="/opt/pynq",
                install_status_path="/tmp/install-status.json",
                overlay_dir="/srv/overlay",
                runtime_log_path="/tmp/runtime.log",
                agent_executable_name="custom-agent",
            )

        self.assertIn("NEUROCHIP_PYNQ_OVERLAY_DIR=/srv/overlay", command)

    def test_build_local_pynq_bundle_is_launcher_owned(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "overlayVersion": "2026.04",
            }
        )
        bundle_dir = self.repo_root / "tmp-pynq-bundle"
        bundle_dir.mkdir(parents=True, exist_ok=True)
        wheel_path = self.repo_root / "Neurochip" / "dist" / "neurochip-test.whl"
        self._write_test_neurochip_wheel(wheel_path)

        with mock.patch.object(
            provisioning_helpers,
            "ensure_agent_wheel",
            return_value=wheel_path,
        ):
            result = self.state._build_local_pynq_bundle(board, bundle_dir)

        manifest = json.loads(
            (bundle_dir / "bundle-manifest.json").read_text(encoding="utf-8")
        )
        self.assertEqual(manifest["overlay"]["overlayVersion"], "2026.04")
        self.assertEqual(result["wheelName"], "neurochip-test.whl")
        self.assertTrue((bundle_dir / "install-pynq-agent.sh").exists())

    def test_build_local_pynq_bundle_does_not_depend_on_neurochip_provisioning_tree(
        self,
    ) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "overlayVersion": "2026.04",
            }
        )
        bundle_dir = self.repo_root / "tmp-pynq-bundle"
        bundle_dir.mkdir(parents=True, exist_ok=True)
        wheel_path = self.repo_root / "Neurochip" / "dist" / "neurochip-test.whl"
        self._write_test_neurochip_wheel(wheel_path)
        original_exists = Path.exists

        def fake_exists(path: Path) -> bool:
            if "Neurochip/neurochip/provisioning" in str(path):
                return False
            return original_exists(path)

        with (
            mock.patch.object(
                provisioning_helpers,
                "ensure_agent_wheel",
                return_value=wheel_path,
            ),
            mock.patch.object(Path, "exists", autospec=True, side_effect=fake_exists),
        ):
            result = self.state._build_local_pynq_bundle(board, bundle_dir)

        self.assertEqual(result["wheelName"], "neurochip-test.whl")

    def test_build_local_akida_bundle_is_launcher_owned(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )
        bundle_dir = self.repo_root / "tmp-akida-bundle"
        bundle_dir.mkdir(parents=True, exist_ok=True)
        wheel_path = self.repo_root / "Neurochip" / "dist" / "neurochip-test.whl"
        self._write_test_neurochip_wheel(wheel_path)

        with (
            mock.patch.object(
                provisioning_helpers,
                "ensure_agent_wheel",
                return_value=wheel_path,
            ),
            mock.patch.object(
                self.state,
                "_get_module",
                return_value={
                    "akidaRuntime": {
                        "requiredPackages": [
                            "tensorflow==2.19.*",
                            "akida==2.19.1",
                            "cnn2snn==2.19.1",
                            "quantizeml==1.2.4",
                            "onnx>=1.17,<2",
                            "akida-models==1.13.1",
                        ]
                    }
                },
            ),
        ):
            result = self.state._build_local_akida_bundle(host, bundle_dir)

        self.assertEqual(
            result["requiredPackages"],
            [
                "tensorflow==2.19.*",
                "akida==2.19.1",
                "cnn2snn==2.19.1",
                "quantizeml==1.2.4",
                "onnx>=1.17,<2",
                "akida-models==1.13.1",
            ],
        )
        # Control port should come from the typed contract, not a raw constant.
        self.assertEqual(
            result["controlPort"],
            launcher_server.AkidaLauncherRuntimeContract().control_port,
        )
        self.assertIn(
            "tensorflow==2.19.*",
            (bundle_dir / "bundle-manifest.json").read_text(encoding="utf-8"),
        )
        install_script = (bundle_dir / "install-akida-host.sh").read_text(
            encoding="utf-8"
        )
        self.assertIn("sudo_available()", install_script)
        self.assertIn("write_sudo_file()", install_script)
        self.assertIn("NMTK_AKIDA_SUDO_PASSWORD", install_script)
        self.assertIn("sudo_cmd apt-get update", install_script)
        self.assertIn('if [ ! -s "$TOKEN_PATH" ]; then', install_script)
        self.assertIn('token_tmp="$(mktemp)"', install_script)
        self.assertIn(
            'sudo_cmd install -D -m 0600 -o "$SERVICE_USER" -g "$SERVICE_USER" "$token_tmp" "$TOKEN_PATH"',
            install_script,
        )
        self.assertIn('if [ -z "$TOKEN_VALUE" ]; then', install_script)
        self.assertIn(
            'INSTALL_STATUS_PAYLOAD="$(sudo_cmd cat "$INSTALL_STATUS_PATH")"',
            install_script,
        )
        self.assertIn('if [ -z "$INSTALL_STATUS_PAYLOAD" ]; then', install_script)
        self.assertIn(
            'pip" install --force-reinstall "$BUNDLE_DIR/wheels/$WHEEL_NAME"',
            install_script,
        )
        self.assertNotIn(
            'pip" install --force-reinstall --no-deps "$BUNDLE_DIR/wheels/$WHEEL_NAME"',
            install_script,
        )
        self.assertIn("trap rollback_on_error EXIT", install_script)
        self.assertIn('ACTIVATION_PENDING="1"', install_script)
        self.assertIn("rollback_release || true", install_script)
        self.assertIn('ACTIVATION_PENDING="0"', install_script)
        self.assertNotIn("| sudo_cmd tee", install_script)
        self.assertNotIn("sudo -n apt-get update", install_script)
        syntax = subprocess.run(
            ["bash", "-n"],
            input=install_script,
            text=True,
            capture_output=True,
            check=False,
        )
        self.assertEqual(syntax.returncode, 0, syntax.stderr)
        self.assertTrue((bundle_dir / "wheels" / "neurochip-test.whl").exists())

    def test_build_local_akida_bundle_does_not_depend_on_neurochip_provisioning_tree(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )
        bundle_dir = self.repo_root / "tmp-akida-bundle"
        bundle_dir.mkdir(parents=True, exist_ok=True)
        wheel_path = self.repo_root / "Neurochip" / "dist" / "neurochip-test.whl"
        self._write_test_neurochip_wheel(wheel_path)
        original_exists = Path.exists

        def fake_exists(path: Path) -> bool:
            if "Neurochip/neurochip/provisioning" in str(path):
                return False
            return original_exists(path)

        with (
            mock.patch.object(
                provisioning_helpers,
                "ensure_agent_wheel",
                return_value=wheel_path,
            ),
            mock.patch.object(
                self.state,
                "_get_module",
                return_value={
                    "akidaRuntime": {
                        "requiredPackages": [
                            "tensorflow==2.19.*",
                            "akida==2.19.1",
                            "cnn2snn==2.19.1",
                            "quantizeml==1.2.4",
                            "onnx>=1.17,<2",
                            "akida-models==1.13.1",
                        ]
                    }
                },
            ),
            mock.patch.object(Path, "exists", autospec=True, side_effect=fake_exists),
        ):
            result = self.state._build_local_akida_bundle(host, bundle_dir)

        self.assertEqual(result["requiredPackages"][0], "tensorflow==2.19.*")
        self.assertTrue((bundle_dir / "wheels" / "neurochip-test.whl").exists())

    def test_pynq_ssh_invocation_uses_contract_ssh_port_as_fallback(self) -> None:
        """SSH command uses the manifest-owned pynq.sshPort when none is stored."""
        manifest_path = (
            self.repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest.append(
            {
                "id": "Neurochip",
                "name": "NeuroChip",
                "installPath": "Neurochip",
                "launcherRuntime": {
                    "pynq": {"sshPort": 2300},
                },
            }
        )
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        # Board dict with no sshPort key — simulates absent or pre-normalization state.
        board = {"authMode": "ssh_key", "sshKeyPath": "/tmp/fake-pynq-key"}
        command, _env, _cleanup = self.state._prepare_ssh_invocation(board)

        # SSH non-copy-mode uses "-p" followed by the port argument.
        port_index = command.index("-p") + 1
        self.assertEqual(command[port_index], "2300")

    def test_akida_ssh_invocation_uses_contract_ssh_port_as_fallback(self) -> None:
        """SSH command uses the manifest-owned akida.sshPort when none is stored."""
        manifest_path = (
            self.repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest.append(
            {
                "id": "Neurochip",
                "name": "NeuroChip",
                "installPath": "Neurochip",
                "launcherRuntime": {
                    "akida": {"sshPort": 2400},
                },
            }
        )
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        host = {"authMode": "ssh_key", "sshKeyPath": "/tmp/fake-akida-key"}
        command, _env, _cleanup = self.state._prepare_akida_ssh_invocation(host)

        port_index = command.index("-p") + 1
        self.assertEqual(command[port_index], "2400")

    def test_akida_ssh_password_auth_requires_stored_password(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "192.168.1.60",
                "username": "operator",
                "authMode": "password",
            }
        )

        with self.assertRaisesRegex(
            RuntimeError,
            "No SSH password is configured for this Akida host",
        ):
            self.state._prepare_akida_ssh_invocation(
                self.state._get_akida_host(host["id"])
            )

    def test_akida_ssh_requires_supported_credential_mode(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "192.168.1.60",
                "username": "operator",
                "authMode": "none",
            }
        )

        with self.assertRaisesRegex(
            RuntimeError,
            "Akida host SSH operations require password or SSH-key authentication",
        ):
            self.state._prepare_akida_ssh_invocation(
                self.state._get_akida_host(host["id"])
            )

    def test_akida_ssh_password_auth_uses_askpass_without_sshpass(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "192.168.1.60",
                "username": "operator",
                "authMode": "password",
                "password": "secret",
            }
        )

        with mock.patch.object(launcher_server.shutil, "which", return_value=None):
            command, env, cleanup = self.state._prepare_akida_ssh_invocation(
                self.state._get_akida_host(host["id"])
            )

        self.assertNotIn("sshpass", command)
        self.assertIsNotNone(env)
        assert env is not None
        self.assertEqual(env["NMTK_AKIDA_PASSWORD"], "secret")
        self.assertIn("SSH_ASKPASS", env)
        askpass_path = Path(env["SSH_ASKPASS"])
        self.assertTrue(askpass_path.exists())
        self.assertIsNotNone(cleanup)
        assert cleanup is not None
        cleanup()
        self.assertFalse(askpass_path.exists())

    def test_build_local_akida_bundle_uses_contract_ports_as_fallback(self) -> None:
        """Bundle assembly uses manifest-owned akida runtime/control ports when absent."""
        manifest_path = (
            self.repo_root / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
        )
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        manifest.append(
            {
                "id": "Neurochip",
                "name": "NeuroChip",
                "installPath": "Neurochip",
                "launcherRuntime": {
                    "akida": {"runtimePort": 9200, "controlPort": 9290},
                },
            }
        )
        manifest_path.write_text(json.dumps(manifest), encoding="utf-8")

        # Host dict without port/controlPort — forces the contract fallback path.
        host = {
            "id": "test-akida",
            "remoteInstallRoot": "/opt/neurochip-akida-host",
            "serviceUser": "neurochip",
            "remoteVenvPath": "/opt/neurochip-akida-host/venv",
            "runtimeServiceName": "neurochip",
            "controlServiceName": "neurochip-akida-control",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
        }
        bundle_dir = self.repo_root / "tmp-contract-akida-bundle"
        bundle_dir.mkdir(parents=True, exist_ok=True)
        wheel_path = (
            self.repo_root / "Neurochip" / "dist" / "neurochip-contract-test.whl"
        )
        self._write_test_neurochip_wheel(wheel_path)

        with (
            mock.patch.object(
                provisioning_helpers,
                "ensure_agent_wheel",
                return_value=wheel_path,
            ),
            mock.patch.object(
                self.state,
                "_get_module",
                return_value={
                    "akidaRuntime": {
                        "requiredPackages": ["akida==2.19.1"],
                    }
                },
            ),
        ):
            result = self.state._build_local_akida_bundle(host, bundle_dir)

        self.assertEqual(result["runtimePort"], 9200)
        self.assertEqual(result["controlPort"], 9290)

    def test_apply_preflight_to_akida_host_marks_user_space_install_degraded(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
            }
        )

        updated = self.state._apply_preflight_to_akida_host(
            host["id"],
            {
                "preflight_status": launcher_server.PREFLIGHT_OK,
                "preflight_message": "Akida hardware runtime is ready.",
                "runtime_target": "hardware",
                "sdk_status": "deployable",
            },
            install_status={"installMode": "user-space"},
        )

        self.assertEqual(updated["state"], "degraded_optional_capability")
        self.assertIn(
            "Runtime is installed in user space.", updated["lastPreflightMessage"]
        )
        self.assertIn(
            "Enable passwordless sudo for 'operator'", updated["lastPreflightMessage"]
        )

    def test_restart_akida_host_services_returns_warning_for_user_space_install(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
            }
        )

        with mock.patch.object(
            self.state,
            "_read_remote_akida_install_status",
            return_value={"installMode": "user-space"},
        ):
            result = self.state.restart_akida_host_services(host["id"])

        self.assertEqual(result["host"]["state"], "degraded_optional_capability")
        self.assertIn("user space", result["warning"])
        self.assertIn("Enable passwordless sudo for 'operator'", result["warning"])
        self.assertIn("re-run Provision Runtime", result["warning"])

    def test_provision_akida_host_updates_paths_from_user_space_install_status(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
            }
        )
        install_status = {
            "installMode": "user-space",
            "message": "Akida host installed in user space; auto-start requires privileged setup.",
            "runtimeApiUrl": "http://akida-box.local:8002",
            "controlApiUrl": "http://akida-box.local:8091",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "operator",
            "venvPath": "/home/operator/.local/share/neurochip-akida-host/venv",
            "installRoot": "/home/operator/.local/share/neurochip-akida-host",
            "tokenPath": "/home/operator/.local/share/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/home/operator/.local/share/neurochip-akida-host/install-status.json",
            "autoStartSupported": False,
        }
        install_output = (
            "[install-akida-host] done\n"
            f"INSTALL_STATUS_JSON={json.dumps(install_status, sort_keys=True)}\n"
        )

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ),
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(
                self.state, "_read_remote_akida_token", return_value="token-123"
            ),
            mock.patch.object(
                self.state,
                "fetch_akida_host_preflight",
                return_value={"host": {"state": "degraded_optional_capability"}},
            ),
        ):
            result = self.state.provision_akida_host(host["id"])

        updated = self.state.get_akida_host(host["id"])
        self.assertEqual(result["installStatus"]["installMode"], "user-space")
        self.assertEqual(
            updated["remoteInstallRoot"],
            "/home/operator/.local/share/neurochip-akida-host",
        )
        self.assertEqual(updated["serviceUser"], "operator")
        self.assertEqual(
            updated["tokenPath"],
            "/home/operator/.local/share/neurochip-akida-host/credentials/api-token",
        )
        self.assertEqual(
            updated["installStatusPath"],
            "/home/operator/.local/share/neurochip-akida-host/install-status.json",
        )
        self.assertEqual(updated["credentialRef"], "token-123")
        self.assertEqual(updated["runtimeApiUrl"], "http://akida-box.local:8002")
        self.assertEqual(updated["controlApiUrl"], "http://akida-box.local:8091")

    def test_provision_akida_host_falls_back_to_remote_status_when_sentinel_blank(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
            }
        )
        install_status = {
            "installMode": "systemd",
            "message": "Akida host installation completed.",
            "runtimeApiUrl": "http://akida-box.local:8002",
            "controlApiUrl": "http://akida-box.local:8091",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "neurochip",
            "venvPath": "/opt/neurochip-akida-host/venv",
            "installRoot": "/opt/neurochip-akida-host",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
            "autoStartSupported": True,
        }
        install_output = "[install-akida-host] done\nINSTALL_STATUS_JSON=\n"

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ),
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(
                self.state,
                "_read_remote_akida_install_status",
                return_value=install_status,
            ) as read_status,
            mock.patch.object(
                self.state, "_read_remote_akida_token", return_value="token-123"
            ),
            mock.patch.object(
                self.state,
                "fetch_akida_host_preflight",
                return_value={"host": {"state": "ready"}},
            ),
        ):
            result = self.state.provision_akida_host(host["id"])

        self.assertEqual(result["installStatus"]["installMode"], "systemd")
        read_status.assert_called_once()

    def test_provision_akida_host_parses_multiline_install_status_sentinel(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
            }
        )
        install_status = {
            "installMode": "systemd",
            "message": "Akida host installation completed.",
            "runtimeApiUrl": "http://akida-box.local:8002",
            "controlApiUrl": "http://akida-box.local:8091",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "neurochip",
            "venvPath": "/opt/neurochip-akida-host/venv",
            "installRoot": "/opt/neurochip-akida-host",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
            "autoStartSupported": True,
            "state": "ready",
        }
        install_output = (
            "INSTALL_STATUS_JSON={\n"
            '  "autoStartSupported": true,\n'
            '  "controlApiUrl": "http://akida-box.local:8091",\n'
            '  "hostOs": "linux",\n'
            '  "installMode": "systemd",\n'
            '  "installRoot": "/opt/neurochip-akida-host",\n'
            '  "installStatusPath": "/opt/neurochip-akida-host/install-status.json",\n'
            '  "message": "Akida host installation completed.",\n'
            '  "pythonVersion": "3.11.8",\n'
            '  "runtimeApiUrl": "http://akida-box.local:8002",\n'
            '  "serviceUser": "neurochip",\n'
            '  "state": "ready",\n'
            '  "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",\n'
            '  "venvPath": "/opt/neurochip-akida-host/venv"\n'
            "}\n"
            "[install-akida-host] Install script completed successfully\n"
        )

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ),
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(
                self.state, "_read_remote_akida_token", return_value="token-123"
            ),
            mock.patch.object(
                self.state,
                "fetch_akida_host_preflight",
                return_value={"host": {"state": "ready"}},
            ),
        ):
            result = self.state.provision_akida_host(host["id"])

        self.assertEqual(result["installStatus"], install_status)
        updated = self.state.get_akida_host(host["id"])
        self.assertEqual(updated["runtimeApiUrl"], "http://akida-box.local:8002")
        self.assertEqual(updated["controlApiUrl"], "http://akida-box.local:8091")

    def test_provision_akida_host_passes_sudo_password_without_logging_it(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "password",
                "password": "secret",
            }
        )
        install_status = {
            "installMode": "systemd",
            "message": "Akida host installation completed.",
            "runtimeApiUrl": "http://akida-box.local:8002",
            "controlApiUrl": "http://akida-box.local:8091",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "neurochip",
            "venvPath": "/opt/neurochip-akida-host/venv",
            "installRoot": "/opt/neurochip-akida-host",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
            "autoStartSupported": True,
        }
        install_output = (
            "[install-akida-host] done\n"
            f"INSTALL_STATUS_JSON={json.dumps(install_status, sort_keys=True)}\n"
        )

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ) as run_ssh,
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(
                self.state, "_read_remote_akida_token", return_value="token-123"
            ),
            mock.patch.object(
                self.state,
                "fetch_akida_host_preflight",
                return_value={"host": {"state": "ready"}},
            ),
        ):
            self.state.provision_akida_host(host["id"])

        install_call = run_ssh.call_args_list[1]
        remote_command = install_call.args[1]
        display_command = install_call.kwargs["display_command"]
        self.assertIn("NMTK_AKIDA_SUDO_PASSWORD=secret", remote_command)
        self.assertIn("NMTK_AKIDA_SUDO_PASSWORD=<redacted>", display_command)
        self.assertNotIn("secret", display_command)

    def test_read_remote_akida_token_uses_sudo_password_without_logging_it(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "password",
                "password": "secret",
            }
        )

        with mock.patch.object(
            self.state,
            "_run_akida_ssh",
            return_value="token-123\n",
        ) as run_ssh:
            token = self.state._read_remote_akida_token(
                self.state._get_akida_host(host["id"]),
                install_status={"installMode": "systemd"},
            )

        self.assertEqual(token, "token-123")
        remote_command = run_ssh.call_args.args[1]
        display_command = run_ssh.call_args.kwargs["display_command"]
        self.assertIn("printf '%s\\n' secret | sudo -S -p '' cat", remote_command)
        self.assertIn("sudo -S -p '' cat", remote_command)
        self.assertIn("printf '%s\\n' <redacted> | sudo -S -p '' cat", display_command)
        self.assertNotIn("NMTK_AKIDA_SUDO_PASSWORD", remote_command)
        self.assertNotIn("secret", display_command)

    def test_provision_akida_host_fails_when_remote_token_is_empty(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
            }
        )
        install_status = {
            "installMode": "systemd",
            "message": "Akida host installation completed.",
            "runtimeApiUrl": "http://unresolvable-hostname:8002",
            "controlApiUrl": "http://unresolvable-hostname:8091",
            "hostOs": "linux",
            "pythonVersion": "3.11.8",
            "serviceUser": "neurochip",
            "venvPath": "/opt/neurochip-akida-host/venv",
            "installRoot": "/opt/neurochip-akida-host",
            "tokenPath": "/opt/neurochip-akida-host/credentials/api-token",
            "installStatusPath": "/opt/neurochip-akida-host/install-status.json",
            "autoStartSupported": True,
        }
        install_output = (
            "[install-akida-host] done\n"
            f"INSTALL_STATUS_JSON={json.dumps(install_status, sort_keys=True)}\n"
        )

        with (
            mock.patch.object(self.state, "_build_local_akida_bundle"),
            mock.patch.object(
                self.state,
                "_run_akida_ssh",
                side_effect=["", install_output],
            ),
            mock.patch.object(self.state, "_run_akida_scp"),
            mock.patch.object(self.state, "_read_remote_akida_token", return_value=""),
        ):
            result = self.state.provision_akida_host(host["id"])

        self.assertIn("empty value", result["error"])

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
                "host": "192.168.1.50",
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
                        "Runtime request timed out for GET http://192.168.1.50:8002/hardware/pynq/preflight after 45s",
                        kind="timeout",
                        url="http://192.168.1.50:8002/hardware/pynq/preflight",
                    ),
                    {"board": {"state": "ready"}},
                ],
            ) as fetch_preflight,
            mock.patch("nmtk.launcher_control.server.time.sleep", return_value=None),
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
                "host": "192.168.1.50",
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
                        "Runtime request failed for GET http://192.168.1.50:8002/hardware/pynq/preflight: could not be reached: connection refused",
                        kind="unreachable",
                        url="http://192.168.1.50:8002/hardware/pynq/preflight",
                    ),
                    {"board": {"state": "ready"}},
                ],
            ) as fetch_preflight,
            mock.patch("nmtk.launcher_control.server.time.sleep", return_value=None),
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
                "host": "192.168.1.50",
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
                "host": "192.168.1.50",
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
