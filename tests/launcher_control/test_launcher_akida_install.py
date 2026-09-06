"""Launcher control service tests: Akida runtime install (ssh invocation, runtime config, python range, install scripts)."""

import json
import os
import subprocess
import tempfile
from pathlib import Path

from base import LauncherControlServiceTestBase

from nmtk.launcher_control import (
    module_environment,
    provisioning_helpers,
)


class TestLauncherAkidaInstall(LauncherControlServiceTestBase):
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
        self.assertIn('  MANAGED_PYTHON_BIN="$MANAGED_PYTHON_ROOT/bin/python3"', script)
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
        fail_clause = (
            "exit 1"
            if always_fail
            else 'if [ -e "$PIP_STATE" ]; then\n  exit 0\nfi\n: > "$PIP_STATE"\nexit 1'
        )
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
            env={
                **os.environ,
                "PIP_LOG": str(workspace / "pip.log"),
                "PIP_STATE": str(workspace / "pip.state"),
            },
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
        self.assertIn("  if getent group systemd-journal >/dev/null 2>&1; then", script)
        self.assertIn(
            '    sudo_cmd usermod -aG systemd-journal "$SERVICE_USER" || true',
            script,
        )
