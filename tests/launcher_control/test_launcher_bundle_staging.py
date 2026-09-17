"""Launcher control service tests: bundle staging (pynq/akida launch commands, rendered templates, local bundle builds)."""

import hashlib
import json
import os
import subprocess
import zipfile
from pathlib import Path
from unittest import mock

from base import LauncherControlServiceTestBase

import nmtk.launcher_control.server as launcher_server
from nmtk.launcher_control import (
    provisioning_helpers,
    runtime_artifact,
)
from nmtk.launcher_control.provisioning_templates import (
    ProvisioningTemplateError,
    render_provisioning_template,
)


class TestLauncherBundleStaging(LauncherControlServiceTestBase):
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
            pynq_python_path="/opt/pynq/bin/python",
            install_status_path="/tmp/install-status.json",
            overlay_dir="/srv/overlay",
            runtime_log_path="/tmp/runtime.log",
            agent_executable_name="custom-agent",
        )

        self.assertIn("NEUROCHIP_PYNQ_OVERLAY_DIR=/srv/overlay", command)
        self.assertIn("/tmp/runtime.log", command)
        self.assertNotIn("Neurochip/neurochip/provisioning", command)

    def test_pynq_v1_templates_preserve_the_existing_rendered_artifacts(
        self,
    ) -> None:
        unit = provisioning_helpers._pynq_systemd_unit_text(
            service_name="neurochip-pynq-agent",
            install_root="/opt/neurochip-pynq-agent",
            agent_venv_path="/opt/neurochip-pynq-agent/venv",
            agent_executable_name="neurochip-pynq-agent",
            pynq_python_path="/opt/neurochip-pynq-agent/pynq-venv/bin/python",
            install_status_path="/opt/neurochip-pynq-agent/install-status.json",
            overlay_dir="/opt/neurochip-pynq-agent/overlays",
        )
        install_script = provisioning_helpers._pynq_install_script_text(
            install_root="/opt/neurochip-pynq-agent",
            agent_venv_path="/opt/neurochip-pynq-agent/venv",
            pynq_venv_path="/opt/neurochip-pynq-agent/pynq-venv",
            overlay_dir="/opt/neurochip-pynq-agent/overlays",
            service_name="neurochip-pynq-agent",
            agent_executable_name="neurochip-pynq-agent",
            install_status_path="/opt/neurochip-pynq-agent/install-status.json",
            runtime_log_path="/opt/neurochip-pynq-agent/runtime.log",
            wheel_name="neurochip-0.1.0-py3-none-any.whl",
        )

        self.assertEqual(
            hashlib.sha256(unit.encode()).hexdigest(),
            "9222c4fdc85145150445fda18f81b9f7f006035314156764e614d84f478f9ed7",
        )
        self.assertEqual(
            hashlib.sha256(install_script.encode()).hexdigest(),
            "400f5c89bcffeb6b313697c046e9ccc0a0c6c597dc20356c0b731033e5371459",
        )

    def test_akida_embedded_scripts_preserve_the_existing_rendered_artifacts(
        self,
    ) -> None:
        """Golden byte-for-byte guard, written before templating Akida's embedded
        install script/systemd units/remote-control script (mirroring the PYNQ
        v1 template extraction) — these run with sudo on real Akida hosts, so
        this must fail loudly on any accidental behavior change.
        """
        runtime_unit = provisioning_helpers._akida_runtime_unit_text(
            install_root="/opt/neurochip-akida-host",
            venv_path="/opt/neurochip-akida-host/current",
            service_user="neurochip",
            runtime_service_name="neurochip",
            runtime_port=8002,
        )
        control_unit = provisioning_helpers._akida_control_unit_text(
            install_root="/opt/neurochip-akida-host",
            venv_path="/opt/neurochip-akida-host/current",
            service_user="neurochip",
            control_service_name="neurochip-akida-control",
        )
        remote_control_script = provisioning_helpers._remote_control_script_text()
        install_script_no_standalone = provisioning_helpers._akida_install_script_text(
            install_root="/opt/neurochip-akida-host",
            service_user="neurochip",
            venv_path="/opt/neurochip-akida-host/venv",
            runtime_service_name="neurochip",
            control_service_name="neurochip-akida-control",
            runtime_port=8002,
            control_port=8091,
            token_path="/opt/neurochip-akida-host/credentials/api-token",
            install_status_path="/opt/neurochip-akida-host/install-status.json",
            wheel_name="neurochip-test.whl",
            artifact_version="0.6.0",
            artifact_sha256="abc123",
            required_packages=["akida==2.19.2"],
        )
        install_script_with_standalone = (
            provisioning_helpers._akida_install_script_text(
                install_root="/opt/neurochip-akida-host",
                service_user="neurochip",
                venv_path="/opt/neurochip-akida-host/venv",
                runtime_service_name="neurochip",
                control_service_name="neurochip-akida-control",
                runtime_port=8002,
                control_port=8091,
                token_path="/opt/neurochip-akida-host/credentials/api-token",
                install_status_path="/opt/neurochip-akida-host/install-status.json",
                wheel_name="neurochip-test.whl",
                artifact_version="0.6.0",
                artifact_sha256="abc123",
                required_packages=["akida==2.19.2"],
                python_range=">=3.10,<3.13",
                standalone_python={
                    "version": "3.12.13",
                    "architecture": "x86_64",
                    "url": "https://example.invalid/cpython-3.12.13.tar.gz",
                    "sha256": "deadbeef",
                },
            )
        )

        self.assertEqual(
            hashlib.sha256(runtime_unit.encode()).hexdigest(),
            "b1e50c95b54e0b450bf3dbe72b01207069e047335a8c2812f7b1c306e47909e5",
        )
        self.assertEqual(
            hashlib.sha256(control_unit.encode()).hexdigest(),
            "420310d5fc0ba793428702203ec32da009c302dc859a668f5b44dfb0e9efcc3e",
        )
        self.assertEqual(
            hashlib.sha256(remote_control_script.encode()).hexdigest(),
            "6a5e15509e15813a8a478b5a086385f4e12b598ff538356da14e6ac93735b919",
        )
        self.assertEqual(
            hashlib.sha256(install_script_no_standalone.encode()).hexdigest(),
            "2f80eee700f72878545d21a27b71c50f048cdd1fdbebe7f0371f4eace01bbb8d",
        )
        self.assertEqual(
            hashlib.sha256(install_script_with_standalone.encode()).hexdigest(),
            "d0e031a1bbdedd0cb100a8cb52564e112849252efb9572a8eb5a536d6428e8cb",
        )

        install_script_no_packages = provisioning_helpers._akida_install_script_text(
            install_root="/opt/neurochip-akida-host",
            service_user="neurochip",
            venv_path="/opt/neurochip-akida-host/venv",
            runtime_service_name="neurochip",
            control_service_name="neurochip-akida-control",
            runtime_port=8002,
            control_port=8091,
            token_path="/opt/neurochip-akida-host/credentials/api-token",
            install_status_path="/opt/neurochip-akida-host/install-status.json",
            wheel_name="neurochip-test.whl",
            artifact_version="0.6.0",
            artifact_sha256="abc123",
            required_packages=[],
        )
        self.assertEqual(
            hashlib.sha256(install_script_no_packages.encode()).hexdigest(),
            "6e641377ffa5c2b760b46d1dd1b360b4f1dcfc6f3d73c953d30114b193fe4e62",
        )

    def test_provisioning_template_renderer_rejects_value_drift(self) -> None:
        with self.assertRaisesRegex(
            ProvisioningTemplateError,
            "missing values: BOARD_NAME",
        ):
            render_provisioning_template(
                "pynq/v1/neurochip-pynq-agent.service.tmpl",
                {
                    "INSTALL_ROOT": "/opt/agent",
                    "AGENT_VENV_PATH": "/opt/agent/venv",
                    "AGENT_EXECUTABLE_NAME": "agent",
                    "PYNQ_PYTHON_PATH": "/opt/pynq/bin/python",
                    "INSTALL_STATUS_PATH": "/opt/agent/status.json",
                    "OVERLAY_DIR": "/opt/agent/overlays",
                    "XILINX_XRT_PATH": "/usr",
                },
            )

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
                pynq_python_path="/opt/pynq/bin/python",
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

        with (
            mock.patch.dict(
                os.environ,
                {"NMTK_NEUROCHIP_ARTIFACT_DIR": ""},
            ),
            mock.patch.object(
                provisioning_helpers,
                "ensure_agent_wheel",
                return_value=wheel_path,
            ),
        ):
            result = self.state._build_local_pynq_bundle(board, bundle_dir)

        manifest = json.loads(
            (bundle_dir / "bundle-manifest.json").read_text(encoding="utf-8")
        )
        install_script = (bundle_dir / "install-pynq-agent.sh").read_text(
            encoding="utf-8"
        )
        self.assertEqual(manifest["overlay"]["overlayVersion"], "2026.04")
        self.assertEqual(result["wheelName"], "neurochip-test.whl")
        self.assertTrue((bundle_dir / "install-pynq-agent.sh").exists())
        self.assertIn(
            '"$AGENT_VENV_PATH/bin/pip" install --force-reinstall '
            '"$BUNDLE_DIR/wheels/$WHEEL_NAME"',
            install_script,
        )
        self.assertNotIn(
            '"$AGENT_VENV_PATH/bin/pip" install --force-reinstall --no-deps '
            '"$BUNDLE_DIR/wheels/$WHEEL_NAME"',
            install_script,
        )
        self.assertIn("started_at = time.monotonic()", install_script)
        self.assertIn("deadline = started_at + 120.0", install_script)
        self.assertIn("Still waiting for runtime health", install_script)
        # The script stops the agent through the shared helper, so the launcher and
        # the install path can never drift on how the agent is stopped.
        self.assertIn(
            'pkill -f "$AGENT_VENV_PATH/bin/$AGENT_EXECUTABLE_NAME" >/dev/null 2>&1 || true',
            install_script,
        )
        # User-space installs are restartable from the launcher; only surviving a
        # board reboot needs privileges.
        self.assertNotIn("launcher restart require privileged setup", install_script)

    def test_build_local_pynq_bundle_uses_bundled_runtime_artifact(self) -> None:
        board = self.state.create_pynq_board(
            {
                "displayName": "Packaged PYNQ",
                "host": "192.168.1.50",
                "username": "xilinx",
                "overlayVersion": "2026.04",
            }
        )
        bundle_dir = self.repo_root / "tmp-pynq-bundle"
        bundle_dir.mkdir(parents=True, exist_ok=True)
        artifact_dir = self.repo_root / "artifacts" / "neurochip"
        wheel_path = artifact_dir / "neurochip-packaged.whl"
        self._write_test_neurochip_wheel(wheel_path)
        runtime_artifact.write_neurochip_runtime_artifact_manifest(artifact_dir)

        with (
            mock.patch.dict(
                os.environ,
                {"NMTK_NEUROCHIP_ARTIFACT_DIR": str(artifact_dir)},
            ),
            mock.patch.object(
                provisioning_helpers,
                "ensure_agent_wheel",
                side_effect=AssertionError("source build must not run"),
            ),
        ):
            result = self.state._build_local_pynq_bundle(board, bundle_dir)

        self.assertEqual(result["wheelName"], "neurochip-packaged.whl")
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
            mock.patch.dict(
                os.environ,
                {"NMTK_NEUROCHIP_ARTIFACT_DIR": ""},
            ),
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
            'akida_pip install --force-reinstall "$BUNDLE_DIR/wheels/$WHEEL_NAME"',
            install_script,
        )
        self.assertNotIn(
            'akida_pip install --force-reinstall --no-deps "$BUNDLE_DIR/wheels/$WHEEL_NAME"',
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
