import io
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import nmtk.launcher_control.server as launcher_server

PROJECT_ROOT = Path(__file__).resolve().parents[1]


class LauncherControlServiceTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tempdir = tempfile.TemporaryDirectory()
        self.repo_root = Path(self._tempdir.name) / "repo"
        assets_dir = self.repo_root / "nmtk" / "neuro_toolkit" / "assets"
        assets_dir.mkdir(parents=True, exist_ok=True)
        (self.repo_root / "dummy_module").mkdir(parents=True, exist_ok=True)

        (assets_dir / "modules.json").write_text(
            json.dumps(
                [
                    {
                        "id": "dummy",
                        "name": "Dummy Module",
                        "description": "Used for launcher control tests",
                        "icon": "extension",
                        "port": 8123,
                        "installPath": "dummy_module",
                        "sourcePath": ".",
                        "runPath": ".",
                        "uvicornTarget": "app.main:app",
                        "hasFrontend": True,
                        "frontendStatus": "Yes",
                        "requiresMuJoCo": False,
                        "version": "1.0.0",
                    }
                ]
            ),
            encoding="utf-8",
        )
        (assets_dir / "remote_modules.json").write_text(
            json.dumps([{"id": "dummy", "version": "1.1.0"}]),
            encoding="utf-8",
        )

        self._patches = [
            mock.patch.object(launcher_server, "REPO_ROOT", self.repo_root),
            mock.patch.object(
                launcher_server,
                "MODULES_MANIFEST",
                assets_dir / "modules.json",
            ),
            mock.patch.object(
                launcher_server,
                "REMOTE_MANIFEST",
                assets_dir / "remote_modules.json",
            ),
            mock.patch.object(
                launcher_server,
                "STATE_FILE",
                self.repo_root / "nmtk" / "neuro_toolkit" / "module_states.json",
            ),
            mock.patch.object(
                launcher_server,
                "SETTINGS_FILE",
                self.repo_root / "nmtk" / "neuro_toolkit" / "launcher_settings.json",
            ),
        ]
        for patcher in self._patches:
            patcher.start()
            self.addCleanup(patcher.stop)

        self.state = launcher_server.LauncherControlState()
        self._fake_venv_python = self._create_fake_venv_python()

    def tearDown(self) -> None:
        self.state.shutdown()
        self._tempdir.cleanup()

    def _create_fake_venv_python(self) -> Path:
        python_path = self.repo_root / "dummy_module" / "venv" / "bin" / "python"
        python_path.parent.mkdir(parents=True, exist_ok=True)
        python_path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        python_path.chmod(0o755)
        return python_path

    def test_modules_endpoint_returns_manifest_data(self) -> None:
        payload = self.state.serialize_modules()

        self.assertIsInstance(payload, list)
        self.assertEqual(payload[0]["id"], "dummy")
        self.assertEqual(payload[0]["remoteVersion"], "1.1.0")
        self.assertEqual(
            payload[0]["status"],
            launcher_server.STATUS_INDEX["notInstalled"],
        )

    def test_module_settings_round_trip_updates_state_file(self) -> None:
        updated = self.state.update_module_settings(
            "dummy",
            {"customPort": 9001, "isEnabled": False, "versionPinned": True},
        )

        self.assertEqual(updated["customPort"], 9001)
        self.assertFalse(updated["isEnabled"])
        self.assertTrue(updated["versionPinned"])

        persisted = json.loads(
            (
                self.repo_root
                / "nmtk"
                / "neuro_toolkit"
                / "module_states.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(persisted["dummy"]["customPort"], 9001)
        self.assertFalse(persisted["dummy"]["isEnabled"])
        self.assertTrue(persisted["dummy"]["versionPinned"])

    def test_wrapper_runs_without_external_pythonpath(self) -> None:
        env = os.environ.copy()
        env.pop("PYTHONPATH", None)

        result = subprocess.run(
            [
                sys.executable,
                str(PROJECT_ROOT / "scripts" / "launcher_control_service.py"),
                "--help",
            ],
            cwd=self._tempdir.name,
            capture_output=True,
            text=True,
            env=env,
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
        self.assertIn("Launcher control service", result.stdout)

    def test_run_dev_script_passes_bash_syntax_check(self) -> None:
        result = subprocess.run(
            ["bash", "-n", str(PROJECT_ROOT / "scripts" / "run_dev.sh")],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)

    def test_start_module_uses_runtime_uvicorn_host_env(self) -> None:
        module_id = "dummy"

        class _FakeProcess:
            stdout = None
            stderr = None
            returncode = 0

            def poll(self) -> None:
                return None

            def wait(self, timeout=None) -> int:
                return 0

            def terminate(self) -> None:
                return None

            def kill(self) -> None:
                return None

        with (
            mock.patch.dict(os.environ, {"NMTK_UVICORN_HOST": "0.0.0.0"}, clear=False),
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_OK,
                    environment_fingerprint="fingerprint-1",
                ),
            ),
            mock.patch.object(self.state, "_kill_process_on_port"),
            mock.patch.object(self.state, "_stream_logs"),
            mock.patch.object(self.state, "_watch_process_exit"),
            mock.patch.object(self.state, "_probe_health", return_value=(True, 200, "ok")),
            mock.patch.object(launcher_server.subprocess, "Popen", return_value=_FakeProcess()) as popen,
        ):
            self.state._start_sync(module_id)

        command = popen.call_args.args[0]
        self.assertIn("--host", command)
        self.assertEqual(command[command.index("--host") + 1], "0.0.0.0")

    def test_start_module_fails_closed_on_preflight_failure(self) -> None:
        with (
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_FAILED,
                    message="Missing required dependency: fastapi (needed by app.main)",
                    environment_fingerprint="fingerprint-2",
                ),
            ),
            mock.patch.object(launcher_server.subprocess, "Popen") as popen,
        ):
            with self.assertRaises(RuntimeError):
                self.state._start_sync("dummy")

        popen.assert_not_called()
        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["error"])
        self.assertEqual(payload["preflightStatus"], launcher_server.PREFLIGHT_FAILED)
        self.assertIn("fastapi", payload["preflightMessage"])

    def test_start_module_preserves_optional_capability_warnings(self) -> None:
        class _FakeProcess:
            stdout = None
            stderr = None
            returncode = 0

            def poll(self) -> None:
                return None

            def wait(self, timeout=None) -> int:
                return 0

            def terminate(self) -> None:
                return None

            def kill(self) -> None:
                return None

        with (
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_DEGRADED,
                    message="Optional capability unavailable: lava.magma.core.run_conditions",
                    capability_warnings=[
                        "Optional capability unavailable: lava.magma.core.run_conditions"
                    ],
                    environment_fingerprint="fingerprint-3",
                ),
            ),
            mock.patch.object(self.state, "_kill_process_on_port"),
            mock.patch.object(self.state, "_stream_logs"),
            mock.patch.object(self.state, "_watch_process_exit"),
            mock.patch.object(self.state, "_probe_health", return_value=(True, 200, "ok")),
            mock.patch.object(launcher_server.subprocess, "Popen", return_value=_FakeProcess()),
        ):
            self.state._start_sync("dummy")

        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["degraded"])
        self.assertEqual(payload["preflightStatus"], launcher_server.PREFLIGHT_DEGRADED)
        self.assertEqual(
            payload["capabilityWarnings"],
            ["Optional capability unavailable: lava.magma.core.run_conditions"],
        )

    def test_preflight_repairs_stale_environment_once(self) -> None:
        module = self.state._get_module("dummy")
        module["environmentFingerprint"] = "stale-fingerprint"

        with (
            mock.patch.object(
                launcher_server,
                "_module_venv_python",
                return_value=self._fake_venv_python,
            ),
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                side_effect=["new-fingerprint", "repaired-fingerprint"],
            ),
            mock.patch.object(
                self.state,
                "_run_import_probe",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_OK,
                ),
            ),
            mock.patch.object(self.state, "_install_sync") as install_sync,
        ):
            result = self.state._preflight_module(module, allow_repair=True)

        install_sync.assert_called_once_with("dummy")
        self.assertEqual(result.status, launcher_server.PREFLIGHT_OK)
        self.assertEqual(result.environment_fingerprint, "repaired-fingerprint")

    def test_preflight_reinstalls_broken_env_once_then_returns_failure(self) -> None:
        module = self.state._get_module("dummy")

        with (
            mock.patch.object(
                launcher_server,
                "_module_venv_python",
                return_value=self._fake_venv_python,
            ),
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                return_value="fingerprint-4",
            ),
            mock.patch.object(
                self.state,
                "_run_import_probe",
                side_effect=[
                    launcher_server.PreflightResult(
                        status=launcher_server.PREFLIGHT_FAILED,
                        message="Missing required dependency: fastapi (needed by app.main)",
                    ),
                    launcher_server.PreflightResult(
                        status=launcher_server.PREFLIGHT_FAILED,
                        message="Missing required dependency: fastapi (needed by app.main)",
                    ),
                ],
            ),
            mock.patch.object(self.state, "_install_sync") as install_sync,
        ):
            result = self.state._preflight_module(module, allow_repair=True)

        install_sync.assert_called_once_with("dummy")
        self.assertEqual(result.status, launcher_server.PREFLIGHT_FAILED)
        self.assertIn("fastapi", result.message)

    def test_stream_logs_echoes_stdout_and_stderr_to_terminal(self) -> None:
        module_id = "dummy"

        class _FakeProcess:
            def __init__(self) -> None:
                self.stdout = io.StringIO("ready\n")
                self.stderr = io.StringIO("boom\n")

        managed = launcher_server.ManagedProcess(
            process=_FakeProcess(),
            logs=self.state._logs[module_id],
        )

        with self.state._lock:
            self.state._processes[module_id] = managed

        stdout = io.StringIO()
        stderr = io.StringIO()
        with (
            mock.patch.object(sys, "stdout", stdout),
            mock.patch.object(sys, "stderr", stderr),
        ):
            self.state._stream_logs(module_id, managed)
            deadline = time.time() + 2.0
            while time.time() < deadline:
                logs = list(self.state.get_logs(module_id)["lines"])
                if "[stderr] boom" in logs and "ready" in logs:
                    break
                time.sleep(0.01)

        self.assertIn("ready", self.state.get_logs(module_id)["lines"])
        self.assertIn("[stderr] boom", self.state.get_logs(module_id)["lines"])
        self.assertIn("[dummy] ready", stdout.getvalue())
        self.assertIn("[dummy] boom", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
