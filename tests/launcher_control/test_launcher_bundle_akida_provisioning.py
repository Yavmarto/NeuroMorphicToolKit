"""Launcher control service tests: TestLauncherBundleAkidaProvisioning."""

from pathlib import Path
import json
import nmtk.launcher_control.server as launcher_server
import nmtk.launcher_control.akida_host_service as akida_host_service
import nmtk.launcher_control.runtime_artifact as runtime_artifact
from unittest import mock
import os
import subprocess
import tempfile
import zipfile
import nmtk.launcher_control.provisioning_helpers as provisioning_helpers
import nmtk.launcher_control.module_environment as module_environment
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
        self.assertEqual(manifest["overlay"]["overlayVersion"], "2026.04")
        self.assertEqual(result["wheelName"], "neurochip-test.whl")
        self.assertTrue((bundle_dir / "install-pynq-agent.sh").exists())

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

    def test_akida_runtime_config_preserves_the_pinned_interpreter(self) -> None:
        """The manifest normalizer must not drop `standaloneCPython`.

        `_normalize_akida_runtime_config` rebuilds the block from a fixed set of
        keys, so anything not named there is silently discarded on load. That is
        exactly how the pin went missing: provisioning reported "no automatic
        download is configured" on a host that had one configured.
        """
        normalized = module_environment._normalize_akida_runtime_config(
            {
                "pythonRange": ">=3.10,<3.13",
                "requiredPackages": ["akida==2.19.2"],
                "standaloneCPython": {
                    "version": "3.12.13",
                    "architecture": "x86_64",
                    "url": "https://example.invalid/cpython.tar.gz",
                    "sha256": "deadbeef",
                },
            }
        )
        assert normalized is not None
        self.assertEqual(
            normalized["standaloneCPython"],
            {
                "version": "3.12.13",
                "architecture": "x86_64",
                "url": "https://example.invalid/cpython.tar.gz",
                "sha256": "deadbeef",
            },
        )

        # An unverifiable pin is refused rather than half-used: without a
        # checksum the download could not be validated.
        partial = module_environment._normalize_akida_runtime_config(
            {
                "standaloneCPython": {
                    "version": "3.12.13",
                    "url": "https://example.invalid/cpython.tar.gz",
                }
            }
        )
        assert partial is not None
        self.assertIsNone(partial["standaloneCPython"])

    def test_shipped_manifest_pins_an_interpreter_for_the_akida_runtime(self) -> None:
        """The real modules.json must survive the real normalizer.

        Guards the whole chain the mocked tests skip: shipped manifest ->
        _normalize_akida_runtime_config -> what provisioning actually receives.
        """
        manifest = json.loads(
            (
                Path(__file__).resolve().parents[2]
                / "nmtk"
                / "neuro_toolkit"
                / "assets"
                / "modules.json"
            ).read_text(encoding="utf-8")
        )
        neurochip = next(m for m in manifest if m.get("id") == "Neurochip")
        normalized = module_environment._normalize_akida_runtime_config(
            neurochip["akidaRuntime"]
        )
        assert normalized is not None
        pinned = normalized["standaloneCPython"]
        self.assertIsNotNone(pinned, "shipped manifest lost its pinned interpreter")
        assert pinned is not None
        self.assertTrue(pinned["url"].startswith("https://"))
        self.assertEqual(len(pinned["sha256"]), 64)
        # The pin has to sit inside the range the SDK actually supports.
        low, high = provisioning_helpers._parse_python_range(normalized["pythonRange"])
        major, minor = (int(part) for part in pinned["version"].split(".")[:2])
        self.assertTrue(low <= (major, minor) < high)

    def test_parse_python_range_reads_manifest_bounds(self) -> None:
        self.assertEqual(
            provisioning_helpers._parse_python_range(">=3.10,<3.13"),
            ((3, 10), (3, 13)),
        )
        self.assertEqual(
            provisioning_helpers._parse_python_range(">=3.11, <3.12"),
            ((3, 11), (3, 12)),
        )
        # A malformed manifest must not make provisioning impossible — it falls
        # back to the documented Akida range rather than raising.
        self.assertEqual(
            provisioning_helpers._parse_python_range("nonsense"),
            (
                provisioning_helpers.DEFAULT_AKIDA_PYTHON_MIN,
                provisioning_helpers.DEFAULT_AKIDA_PYTHON_MAX,
            ),
        )

    def test_akida_install_script_builds_venv_from_a_range_checked_python(
        self,
    ) -> None:
        """Both branches pick an interpreter the SDK actually has wheels for.

        BrainChip publishes `akida` for cp310-cp312 only and TensorFlow ships no
        cp313+ wheels at all, so a host whose `python3` is newer (Ubuntu 26.04
        ships 3.14) used to fail with a raw pip "no matching distribution"
        error part-way through provisioning.
        """
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

        # Neither branch may fall back to a bare `python3` for the venv.
        self.assertIn(
            'sudo_cmd -u "$SERVICE_USER" "$AKIDA_PYTHON" -m venv "$NEXT_VENV_PATH"',
            script,
        )
        self.assertIn('"$AKIDA_PYTHON" -m venv "$NEXT_VENV_PATH"', script)
        self.assertNotIn('python3 -m venv "$NEXT_VENV_PATH"', script)

        # The bounds are baked in and asked of the interpreter itself.
        self.assertIn("(3, 10) <= sys.version_info[:2] < (3, 13)", script)

        # A download is never trusted without its pinned checksum.
        self.assertIn("https://example.invalid/cpython-3.12.13.tar.gz", script)
        self.assertIn("deadbeef", script)
        self.assertIn('if [ "$py_sha" != "$STANDALONE_PYTHON_SHA256" ]', script)

        # Safety property: an already-suitable interpreter always wins, so a
        # host that provisions correctly today never reaches the network here.
        self.assertLess(
            script.index("if python_in_range python3; then"),
            script.index("\n  install_managed_python\n"),
        )

        # Regression: the user-space branch re-points INSTALL_ROOT at the
        # invoking user's home precisely because the original root is not
        # writable. The managed-Python paths are INSTALL_ROOT-relative and must
        # be re-derived with the others, or the download unpacks into the very
        # directory that was already refused.
        self.assertIn('  MANAGED_PYTHON_ROOT="$INSTALL_ROOT/python"', script)
        self.assertIn(
            '  MANAGED_PYTHON_BIN="$MANAGED_PYTHON_ROOT/bin/python3"', script
        )
        userspace = script[script.index('  INSTALL_ROOT="$CURRENT_HOME') :]
        self.assertLess(
            userspace.index('  MANAGED_PYTHON_ROOT="$INSTALL_ROOT/python"'),
            userspace.index('"$AKIDA_PYTHON" -m venv'),
        )

        syntax = subprocess.run(
            ["bash", "-n"], input=script, text=True, capture_output=True, check=False
        )
        self.assertEqual(syntax.returncode, 0, syntax.stderr)

    def test_akida_install_script_without_manifest_pin_still_generates(self) -> None:
        """An older manifest with no `standaloneCPython` must still install.

        It degrades to a clear, actionable message instead of a pip error.
        """
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
            wheel_name="neurochip-test.whl",
            artifact_version="0.6.0",
            artifact_sha256="abc123",
            required_packages=["akida==2.19.2"],
        )
        self.assertIn('STANDALONE_PYTHON_URL=""', script)
        self.assertIn("no automatic download is configured", script)
        syntax = subprocess.run(
            ["bash", "-n"], input=script, text=True, capture_output=True, check=False
        )
        self.assertEqual(syntax.returncode, 0, syntax.stderr)

    @staticmethod
    def _akida_script(**overrides: object) -> str:
        kwargs: dict[str, object] = {
            "install_root": "/opt/neurochip-akida-host",
            "service_user": "neurochip",
            "venv_path": "/opt/neurochip-akida-host/venv",
            "runtime_service_name": "neurochip",
            "control_service_name": "neurochip-akida-control",
            "runtime_port": 8002,
            "control_port": 8091,
            "token_path": "/opt/neurochip-akida-host/credentials/api-token",
            "install_status_path": "/opt/neurochip-akida-host/install-status.json",
            "wheel_name": "neurochip-test.whl",
            "artifact_version": "0.6.0",
            "artifact_sha256": "abc123",
            "required_packages": ["akida==2.19.2"],
        }
        kwargs.update(overrides)
        return provisioning_helpers._akida_install_script_text(**kwargs)

    @staticmethod
    def _run_install_akida_packages(
        script: str, workspace: Path, *, always_fail: bool = False
    ) -> subprocess.CompletedProcess[str]:
        """Execute the generated retry helper against a stub pip.

        Text assertions have passed here before while the generated script was
        broken, so this runs the real bash.
        """
        preamble = script[: script.index('\nINSTALL_MODE="systemd"')]
        venv_bin = workspace / "venv" / "bin"
        venv_bin.mkdir(parents=True)
        fail_clause = "exit 1" if always_fail else 'if [ -e "$PIP_STATE" ]; then\n  exit 0\nfi\n: > "$PIP_STATE"\nexit 1'
        (venv_bin / "pip").write_text(
            "#!/bin/sh\n"
            'printf "%s\\n" "$*" >> "$PIP_LOG"\n'
            'case "$1" in\n'
            "  cache) exit 0;;\n"
            "esac\n"
            f"{fail_clause}\n",
            encoding="utf-8",
        )
        (venv_bin / "pip").chmod(0o755)
        harness = (
            f"{preamble}\n"
            'USE_SUDO=""\n'
            f'NEXT_VENV_PATH="{workspace / "venv"}"\n'
            f'PIP_CACHE_DIR="{workspace / "cache"}"\n'
            "install_akida_packages\n"
        )
        return subprocess.run(
            ["bash"],
            input=harness,
            text=True,
            capture_output=True,
            check=False,
            env={**os.environ, "PIP_LOG": str(workspace / "pip.log"), "PIP_STATE": str(workspace / "pip.state")},
        )

    def test_akida_package_install_retries_once_without_the_download_cache(
        self,
    ) -> None:
        """A poisoned cache entry must not wedge the install forever.

        pip checks every download against the checksum the index publishes, so
        one damaged file replays the same failure on every attempt -- observed
        on the dev host as a TensorFlow wheel that never matched its hash. The
        cached attempt still goes first: it is what a healthy host uses.
        """
        script = self._akida_script()
        with tempfile.TemporaryDirectory() as raw:
            workspace = Path(raw)
            result = self._run_install_akida_packages(script, workspace)
            self.assertEqual(result.returncode, 0, result.stderr)
            attempts = (workspace / "pip.log").read_text(encoding="utf-8").splitlines()

        self.assertEqual(
            attempts,
            [
                f"install --cache-dir {workspace / 'cache'} akida==2.19.2",
                f"cache --cache-dir {workspace / 'cache'} purge",
                f"install --cache-dir {workspace / 'cache'} --no-cache-dir akida==2.19.2",
            ],
        )
        # --cache-dir must precede --no-cache-dir: pip applies these in order,
        # so a trailing one would switch the cache back on and undo the retry.
        retry = attempts[-1]
        self.assertLess(retry.index("--cache-dir"), retry.index("--no-cache-dir"))

    def test_akida_package_install_failure_explains_itself_in_plain_english(
        self,
    ) -> None:
        script = self._akida_script()
        with tempfile.TemporaryDirectory() as raw:
            workspace = Path(raw)
            result = self._run_install_akida_packages(
                script, workspace, always_fail=True
            )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not be downloaded onto this server", result.stderr)

    def test_akida_install_script_gives_the_service_user_its_own_pip_cache(
        self,
    ) -> None:
        """`sudo -u` does not hand the service account its own HOME.

        Without an explicit cache the service user writes wherever the invoking
        login points -- a directory it may not own, and one this installer can
        never clear when it goes bad.
        """
        script = self._akida_script()
        self.assertIn('PIP_CACHE_DIR="${INSTALL_ROOT}/cache/pip"', script)
        self.assertIn('"$RELEASES_DIR" "$PIP_CACHE_DIR"', script)

        # Same trap as MANAGED_PYTHON_ROOT: the user-space branch re-points
        # INSTALL_ROOT, so every path derived from it must be re-derived before
        # first use or it points back at the directory that was refused.
        userspace = script[script.index('  INSTALL_ROOT="$CURRENT_HOME') :]
        self.assertLess(
            userspace.index('  PIP_CACHE_DIR="$INSTALL_ROOT/cache/pip"'),
            userspace.index("  install_akida_packages"),
        )
        self.assertLess(
            userspace.index('  PIP_CACHE_DIR="$INSTALL_ROOT/cache/pip"'),
            userspace.index('  mkdir -p "$INSTALL_ROOT"'),
        )

    def test_akida_install_script_lets_the_service_user_read_the_kernel_log(
        self,
    ) -> None:
        """The doctor names a non-responding board from kernel messages.

        Optional by design: a host without that group still installs.
        """
        script = self._akida_script()
        self.assertIn(
            '  if getent group systemd-journal >/dev/null 2>&1; then', script
        )
        self.assertIn(
            '    sudo_cmd usermod -aG systemd-journal "$SERVICE_USER" || true',
            script,
        )

    @staticmethod
    def _remote_control_namespace() -> dict[str, object]:
        """Load the remote-control service the installer actually ships.

        It lives as source text inside provisioning_helpers, so importing it is
        the only way to test the diagnosis it produces rather than a copy that
        may have drifted.
        """
        namespace: dict[str, object] = {"__name__": "akida_remote_control_under_test"}
        exec(  # noqa: S102 - the subject under test is generated source
            compile(
                provisioning_helpers._remote_control_script_text(),
                "akida_remote_control_service.py",
                "exec",
            ),
            namespace,
        )
        return namespace

    def _device_message(
        self,
        *,
        runtime_target: str,
        kernel_log: str = "",
        link_errors: int | None = None,
        probe: dict[str, object] | None = None,
    ) -> str:
        namespace = self._remote_control_namespace()
        namespace["_kernel_log_text"] = lambda: kernel_log
        namespace["_correctable_link_errors"] = lambda _probe: link_errors
        device_message = namespace["_akida_device_message"]
        return device_message(
            probe
            if probe is not None
            else {
                "present": True,
                "bdf": "0000:03:00.0",
                "driver": "akida-pcie",
                "memorySpaceEnabled": True,
            },
            "",
            runtime_target,
        )

    def test_board_that_passes_every_static_check_but_runs_the_simulator_is_named(
        self,
    ) -> None:
        """The case that reported nothing useful for a whole afternoon.

        Board fitted, driver bound, PCI memory space enabled -- so none of the
        existing checks fire -- yet the SDK falls back to the simulator because
        transfers to the card time out. It used to surface as "Optional Akida
        capability is degraded."
        """
        message = self._device_message(runtime_target="akd1000_simulator")
        self.assertIn("fitted and its driver is loaded", message)
        self.assertIn("stops responding", message)
        self.assertIn("fully off and on again", message)

        # A working card must never be told it is broken.
        self.assertEqual(self._device_message(runtime_target="hardware"), "")

    def test_unresponsive_board_only_blames_power_saving_when_the_kernel_said_so(
        self,
    ) -> None:
        aspm = self._device_message(
            runtime_target="akd1000_simulator",
            kernel_log="akida-pcie 0000:03:00.0: can't disable ASPM; OS doesn't have ASPM control",
        )
        self.assertIn("PCIe power management (ASPM)", aspm)
        self.assertIn("BIOS", aspm)

        timeouts = self._device_message(
            runtime_target="software_fallback",
            kernel_log="akida-pcie 0000:03:00.0: DMA wait completion timed out",
        )
        self.assertIn("transfers to the board time out", timeouts)
        self.assertNotIn("ASPM", timeouts)

        # No kernel log (the service user may not read it) and no error counter:
        # say what was observed and nothing more.
        bare = self._device_message(runtime_target="akd1000_simulator")
        self.assertNotIn("ASPM", bare)
        self.assertNotIn("time out", bare)

        counted = self._device_message(
            runtime_target="akd1000_simulator", link_errors=16
        )
        self.assertIn("logged 16 errors", counted)
        self.assertIn("reseating", counted)

    def test_existing_board_verdicts_still_win_over_the_simulator_case(self) -> None:
        wedged = self._device_message(
            runtime_target="akd1000_simulator",
            probe={
                "present": True,
                "bdf": "0000:03:00.0",
                "driver": "akida-pcie",
                "memorySpaceEnabled": False,
            },
        )
        self.assertIn("has stopped responding", wedged)

        absent = self._device_message(
            runtime_target="akd1000_simulator",
            probe={"present": False, "bdf": "", "driver": "", "memorySpaceEnabled": None},
        )
        self.assertEqual(absent, "No Akida board was found in this host.")

        unbound = self._device_message(
            runtime_target="akd1000_simulator",
            probe={
                "present": True,
                "bdf": "0000:03:00.0",
                "driver": "",
                "memorySpaceEnabled": True,
            },
        )
        self.assertIn("PCIe driver is not loaded", unbound)

    def test_correctable_link_errors_reads_the_kernel_counter(self) -> None:
        namespace = self._remote_control_namespace()
        with tempfile.TemporaryDirectory() as raw:
            devices_root = Path(raw)
            device = devices_root / "0000:03:00.0"
            device.mkdir()
            (device / "aer_dev_correctable").write_text(
                "RxErr 14\nBadTLP 0\nBadDLLP 4\nTOTAL_ERR_COR 16\n", encoding="utf-8"
            )
            namespace["PCI_DEVICES_ROOT"] = devices_root
            read = namespace["_correctable_link_errors"]
            self.assertEqual(read({"bdf": "0000:03:00.0"}), 16)
            # Absent counter (older kernels) and no board must not raise.
            self.assertIsNone(read({"bdf": "0000:04:00.0"}))
            self.assertIsNone(read({"bdf": ""}))

    def test_akida_request_base_url_rewrites_only_when_same_host_as_backend(
        self,
    ) -> None:
        """HTTP to the runtime uses the gateway alias, preserving scheme/port/path.

        Once provisioned the Neurochip runtime is a *host-level* systemd service,
        which this container can only reach through the alias — measured: the
        host's LAN address behaves like a closed port for host services.
        """
        self.assertEqual(
            akida_host_service._akida_request_base_url(
                "http://192.168.2.90:8002", {"sameHostAsBackend": True}
            ),
            "http://host.docker.internal:8002",
        )
        # Untouched when the host is a genuinely separate machine.
        self.assertEqual(
            akida_host_service._akida_request_base_url(
                "http://192.168.2.90:8002", {"sameHostAsBackend": False}
            ),
            "http://192.168.2.90:8002",
        )
        self.assertEqual(
            akida_host_service._akida_request_base_url("", {"sameHostAsBackend": True}),
            "",
        )
        # A URL without an explicit port keeps having none.
        self.assertEqual(
            akida_host_service._akida_request_base_url(
                "http://192.168.2.90", {"sameHostAsBackend": True}
            ),
            "http://host.docker.internal",
        )

    def test_akida_ssh_connect_host_uses_docker_gateway_when_same_host_as_backend(
        self,
    ) -> None:
        """`sameHostAsBackend` routes SSH through the container's gateway alias.

        From inside this container the host's own LAN address reaches no
        host-level service — see
        `nmtk/launcher_control/akida_host_service.py::_akida_ssh_connect_host`.
        """
        self.assertEqual(
            akida_host_service._akida_ssh_connect_host(
                {"host": "192.168.2.90", "sameHostAsBackend": True}
            ),
            "host.docker.internal",
        )
        self.assertEqual(
            akida_host_service._akida_ssh_connect_host(
                {"host": "192.168.2.90", "sameHostAsBackend": False}
            ),
            "192.168.2.90",
        )
        self.assertEqual(
            akida_host_service._akida_ssh_connect_host({"host": "192.168.2.90"}),
            "192.168.2.90",
        )

    def test_run_akida_ssh_targets_docker_gateway_when_same_host_as_backend(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Self-paired Akida",
                "host": "192.168.2.90",
                "username": "moosebun2",
                "authMode": "ssh_key",
                "sshKeyPath": "/tmp/fake-akida-key",
                "sameHostAsBackend": True,
            }
        )

        class _FakeStream:
            def readline(self) -> str:
                return ""

            def close(self) -> None:
                pass

        class _FakeProcess:
            stdout = _FakeStream()
            stderr = _FakeStream()
            returncode = 0

            def wait(self) -> int:
                return 0

        with mock.patch.object(
            akida_host_service.subprocess,
            "Popen",
            return_value=_FakeProcess(),
        ) as popen:
            self.state._run_akida_ssh(
                self.state._get_akida_host(host["id"]), "python3 --version"
            )

        command = popen.call_args.args[0]
        self.assertIn("moosebun2@host.docker.internal", command)
        self.assertNotIn("moosebun2@192.168.2.90", command)

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
