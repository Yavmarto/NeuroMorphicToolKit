import io
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from typing import Any
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

    def _create_fake_poetry_python(self) -> Path:
        python_path = (
            self.repo_root
            / ".poetry-envs"
            / "dummy"
            / "bin"
            / "python"
        )
        python_path.parent.mkdir(parents=True, exist_ok=True)
        python_path.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        python_path.chmod(0o755)
        return python_path

    def _write_poetry_pyproject(self) -> None:
        pyproject = self.repo_root / "dummy_module" / "pyproject.toml"
        pyproject.write_text(
            "\n".join(
                [
                    "[tool.poetry]",
                    'name = "dummy"',
                    'version = "0.1.0"',
                    "",
                    "[build-system]",
                    'requires = ["poetry-core>=1.0.0"]',
                    'build-backend = "poetry.core.masonry.api"',
                ]
            ),
            encoding="utf-8",
        )

    def _create_fake_inproject_poetry_python_symlink(self) -> tuple[Path, Path]:
        python_path = self.repo_root / "dummy_module" / ".venv" / "bin" / "python"
        base_python = self.repo_root / "python-base" / "bin" / "python"
        python_path.parent.mkdir(parents=True, exist_ok=True)
        base_python.parent.mkdir(parents=True, exist_ok=True)
        base_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        base_python.chmod(0o755)
        python_path.symlink_to(base_python)
        return python_path, base_python

    def test_modules_endpoint_returns_manifest_data(self) -> None:
        payload = self.state.serialize_modules()

        self.assertIsInstance(payload, list)
        self.assertEqual(payload[0]["id"], "dummy")
        self.assertEqual(payload[0]["remoteVersion"], "1.1.0")
        self.assertEqual(
            payload[0]["status"],
            launcher_server.STATUS_INDEX["notInstalled"],
        )

    def test_missing_environment_normalizes_stale_installed_state(self) -> None:
        state_file = self.repo_root / "nmtk" / "neuro_toolkit" / "module_states.json"
        state_file.write_text(
            json.dumps(
                {
                    "dummy": {
                        "id": "dummy",
                        "status": launcher_server.STATUS_INDEX["installed"],
                        "installProgress": 1.0,
                        "environmentFingerprint": None,
                    }
                }
            ),
            encoding="utf-8",
        )
        self._fake_venv_python.unlink()

        reloaded = launcher_server.LauncherControlState()
        self.addCleanup(reloaded.shutdown)

        payload = reloaded.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["notInstalled"])
        self.assertEqual(payload["installProgress"], 0.0)

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
                self.repo_root
                / "nmtk"
                / "neuro_toolkit"
                / "launcher_settings.json"
            ).read_text(encoding="utf-8")
        )
        self.assertEqual(len(persisted["pynqBoards"]), 1)
        self.assertEqual(persisted["pynqBoards"][0]["host"], "192.168.1.50")
        self.assertEqual(persisted["pynqBoards"][0]["password"], "secret")
        self.assertEqual(
            persisted["pynqBoards"][0]["remoteInstallRoot"],
            "/home/xilinx/.local/share/neurochip-pynq-agent",
        )

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
            created["remoteOverlayDir"],
            "/home/xilinx/.local/share/neurochip-pynq-agent/overlays",
        )

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

    def test_run_ssh_password_auth_falls_back_to_askpass_without_sshpass(self) -> None:
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
        observed: dict[str, Any] = {}

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
            def __init__(self, command: list[str], env: dict[str, str]) -> None:
                self.command = command
                self.env = env
                self.stdout = _FakeStream(["Python 3.10.0"])
                self.stderr = _FakeStream([])

            def wait(self) -> int:
                return 0

        def _fake_popen(*args: Any, **kwargs: Any) -> _FakeProcess:
            command = args[0]
            env = kwargs.get("env")
            self.assertNotIn("sshpass", command)
            self.assertIn("PreferredAuthentications=password", command)
            self.assertIsInstance(env, dict)
            askpass_path = env["SSH_ASKPASS"]
            self.assertTrue(Path(askpass_path).exists())
            self.assertEqual(env["NMTK_PYNQ_PASSWORD"], "secret")
            observed["askpass_path"] = askpass_path
            return _FakeProcess(command, env)

        with (
            mock.patch.object(launcher_server.shutil, "which", return_value=None),
            mock.patch.object(launcher_server.subprocess, "Popen", side_effect=_fake_popen),
        ):
            self.state._run_ssh(self.state._get_pynq_board(board["id"]), "python3 --version")

        self.assertFalse(Path(observed["askpass_path"]).exists())

    def test_run_scp_password_auth_falls_back_to_askpass_without_sshpass(self) -> None:
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
        observed: dict[str, Any] = {}

        def _fake_run(*args: Any, **kwargs: Any) -> subprocess.CompletedProcess[str]:
            command = args[0]
            env = kwargs.get("env")
            self.assertEqual(command[0], "scp")
            self.assertIn("PreferredAuthentications=password", command)
            self.assertIsInstance(env, dict)
            askpass_path = env["SSH_ASKPASS"]
            self.assertTrue(Path(askpass_path).exists())
            observed["askpass_path"] = askpass_path
            return subprocess.CompletedProcess(command, 0, "", "")

        with (
            mock.patch.object(launcher_server.shutil, "which", return_value=None),
            mock.patch.object(launcher_server.subprocess, "run", side_effect=_fake_run),
        ):
            self.state._run_scp(
                self.state._get_pynq_board(board["id"]),
                local_file,
                "/tmp/bundle.txt",
            )

        self.assertFalse(Path(observed["askpass_path"]).exists())

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

    def test_doctor_report_skips_not_installed_module_preflight(self) -> None:
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["notInstalled"]

        with mock.patch.object(self.state, "_preflight_module") as preflight:
            report = self.state.doctor_report()

        preflight.assert_not_called()
        self.assertEqual(report["modules"][0]["preflightMessage"], "Module not installed")

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

    def test_module_python_path_preserves_poetry_shim_path(self) -> None:
        self._write_poetry_pyproject()
        poetry_python, base_python = self._create_fake_inproject_poetry_python_symlink()
        module = self.state._get_module("dummy")

        python_path = launcher_server._module_python_path(module)
        expected_poetry_python = (
            (self.repo_root / "dummy_module").resolve() / ".venv" / "bin" / "python"
        )

        self.assertEqual(python_path, expected_poetry_python)
        self.assertTrue(python_path.samefile(poetry_python))
        self.assertNotEqual(python_path, base_python.resolve())

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

    def test_doctor_report_marks_fatal_preflight_as_blocking(self) -> None:
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["installed"]
        with (
            mock.patch.object(launcher_server, "_global_preflight_checks", return_value=[]),
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_FAILED,
                    message="Missing required dependency: fastapi (needed by app.main)",
                    environment_fingerprint="fingerprint-fatal",
                ),
            ),
        ):
            report = self.state.doctor_report()

        self.assertEqual(report["status"], "error")
        self.assertEqual(report["fatalCount"], 1)
        self.assertEqual(report["degradedCount"], 0)
        self.assertEqual(report["okCount"], 0)
        self.assertEqual(report["modules"][0]["preflightStatus"], launcher_server.PREFLIGHT_FAILED)
        self.assertIn("fastapi", report["modules"][0]["preflightMessage"])

    def test_doctor_report_keeps_optional_capability_degradation_nonfatal(self) -> None:
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["installed"]
        with (
            mock.patch.object(launcher_server, "_global_preflight_checks", return_value=[]),
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_DEGRADED,
                    message="Optional capability unavailable: lava.magma.core.run_conditions",
                    capability_warnings=[
                        "Optional capability unavailable: lava.magma.core.run_conditions"
                    ],
                    environment_fingerprint="fingerprint-degraded",
                ),
            ),
        ):
            report = self.state.doctor_report()

        self.assertEqual(report["status"], "ok")
        self.assertEqual(report["fatalCount"], 0)
        self.assertEqual(report["degradedCount"], 1)
        self.assertEqual(report["okCount"], 0)
        self.assertEqual(
            report["modules"][0]["preflightStatus"],
            launcher_server.PREFLIGHT_DEGRADED,
        )
        self.assertEqual(
            report["modules"][0]["capabilityWarnings"],
            ["Optional capability unavailable: lava.magma.core.run_conditions"],
        )

    def test_render_doctor_report_uses_explicit_policy_terms(self) -> None:
        report = {
            "status": "error",
            "fatalCount": 1,
            "degradedCount": 1,
            "okCount": 1,
            "globalChecks": [
                {
                    "id": "flutter-sdk",
                    "preflightStatus": launcher_server.PREFLIGHT_FAILED,
                    "preflightMessage": "Flutter SDK cache is not writable: /tmp/flutter/bin/cache",
                    "capabilityWarnings": [],
                }
            ],
            "modules": [
                {
                    "id": "fatal-module",
                    "preflightStatus": launcher_server.PREFLIGHT_FAILED,
                    "preflightMessage": "Missing required dependency: fastapi",
                    "capabilityWarnings": [],
                },
                {
                    "id": "degraded-module",
                    "preflightStatus": launcher_server.PREFLIGHT_DEGRADED,
                    "preflightMessage": "Optional capability unavailable: lava",
                    "capabilityWarnings": ["Optional capability unavailable: lava"],
                },
            ],
        }

        rendered = launcher_server._render_doctor_report(report)

        self.assertIn("status=preflight failed", rendered)
        self.assertIn("preflight failed flutter-sdk", rendered)
        self.assertIn("preflight failed fatal-module", rendered)
        self.assertIn("degraded optional capability degraded-module", rendered)

    def test_doctor_report_includes_global_preflight_failures(self) -> None:
        with (
            mock.patch.object(
                launcher_server,
                "_global_preflight_checks",
                return_value=[
                    {
                        "id": "flutter-sdk",
                        "name": "Flutter SDK",
                        "preflightStatus": launcher_server.PREFLIGHT_FAILED,
                        "preflightMessage": "Flutter SDK cache is not writable: /tmp/flutter/bin/cache",
                        "capabilityWarnings": [],
                    }
                ],
            ),
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_OK,
                    message=None,
                ),
            ),
        ):
            report = self.state.doctor_report()

        self.assertEqual(report["status"], "error")
        self.assertEqual(report["fatalCount"], 1)
        self.assertEqual(len(report["globalChecks"]), 1)
        self.assertEqual(report["globalChecks"][0]["id"], "flutter-sdk")

    def test_global_preflight_checks_flag_unwritable_flutter_cache(self) -> None:
        flutter_bin = self.repo_root / "flutter" / "bin" / "flutter"
        cache_dir = flutter_bin.parent / "cache"
        cache_dir.mkdir(parents=True, exist_ok=True)
        flutter_bin.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        engine_stamp = cache_dir / "engine.stamp"
        engine_stamp.write_text("ready\n", encoding="utf-8")
        resolved_cache_dir = cache_dir.resolve()
        resolved_engine_stamp = engine_stamp.resolve()

        def fake_access(path: str | os.PathLike[str], mode: int) -> bool:
            normalized = Path(path).resolve()
            if normalized in {resolved_cache_dir, resolved_engine_stamp}:
                return False
            return True

        with (
            mock.patch.object(launcher_server.shutil, "which", return_value=str(flutter_bin)),
            mock.patch.object(launcher_server.os, "access", side_effect=fake_access),
        ):
            checks = launcher_server._global_preflight_checks()

        self.assertEqual(len(checks), 1)
        self.assertEqual(checks[0]["preflightStatus"], launcher_server.PREFLIGHT_FAILED)
        self.assertIn("not writable", str(checks[0]["preflightMessage"]))

    def test_main_returns_nonzero_for_fatal_doctor_report(self) -> None:
        fake_state = mock.Mock()
        fake_state.doctor_report.return_value = {
            "status": "error",
            "fatalCount": 1,
            "degradedCount": 0,
            "okCount": 0,
            "modules": [],
        }

        stdout = io.StringIO()
        with (
            mock.patch.object(launcher_server, "LauncherControlState", return_value=fake_state),
            mock.patch.object(sys, "stdout", stdout),
        ):
            exit_code = launcher_server.main(["--doctor", "--json"])

        self.assertEqual(exit_code, 1)
        fake_state.shutdown.assert_called_once()
        self.assertEqual(json.loads(stdout.getvalue()), fake_state.doctor_report.return_value)

    def test_main_returns_zero_for_degraded_only_doctor_report(self) -> None:
        fake_state = mock.Mock()
        fake_state.doctor_report.return_value = {
            "status": "ok",
            "fatalCount": 0,
            "degradedCount": 1,
            "okCount": 0,
            "modules": [
                {
                    "id": "dummy",
                    "preflightStatus": launcher_server.PREFLIGHT_DEGRADED,
                    "preflightMessage": "Optional capability unavailable: lava",
                    "capabilityWarnings": ["Optional capability unavailable: lava"],
                }
            ],
        }

        stdout = io.StringIO()
        with (
            mock.patch.object(launcher_server, "LauncherControlState", return_value=fake_state),
            mock.patch.object(sys, "stdout", stdout),
        ):
            exit_code = launcher_server.main(["--doctor", "--json"])

        self.assertEqual(exit_code, 0)
        fake_state.shutdown.assert_called_once()
        self.assertEqual(json.loads(stdout.getvalue()), fake_state.doctor_report.return_value)

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

    def test_preflight_accepts_recovered_poetry_probe_despite_stale_failed_fingerprint(self) -> None:
        self._write_poetry_pyproject()
        poetry_python = self.repo_root / "dummy_module" / ".venv" / "bin" / "python"
        poetry_python.parent.mkdir(parents=True, exist_ok=True)
        poetry_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        poetry_python.chmod(0o755)
        module = self.state._get_module("dummy")
        module["environmentFingerprint"] = "stale-fingerprint"
        module["preflightStatus"] = launcher_server.PREFLIGHT_FAILED
        module["preflightMessage"] = "Missing required dependency: fastapi (needed by app.main)"

        with (
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                return_value="fresh-fingerprint",
            ),
            mock.patch.object(
                self.state,
                "_run_import_probe",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_OK,
                ),
            ) as run_import_probe,
            mock.patch.object(self.state, "_install_sync") as install_sync,
        ):
            result = self.state._preflight_module(module, allow_repair=False)

        install_sync.assert_not_called()
        run_import_probe.assert_called_once_with(module)
        self.assertEqual(result.status, launcher_server.PREFLIGHT_OK)
        self.assertEqual(result.environment_fingerprint, "fresh-fingerprint")

    def test_preflight_cleans_poetry_env_before_reinstalling_once(self) -> None:
        self._write_poetry_pyproject()
        poetry_python = self.repo_root / "dummy_module" / ".venv" / "bin" / "python"
        poetry_python.parent.mkdir(parents=True, exist_ok=True)
        poetry_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        poetry_python.chmod(0o755)
        module = self.state._get_module("dummy")

        with (
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                side_effect=["fingerprint-before", "fingerprint-after"],
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
                        status=launcher_server.PREFLIGHT_OK,
                    ),
                ],
            ) as run_import_probe,
            mock.patch.object(self.state, "_cleanup_module_environment") as cleanup_env,
            mock.patch.object(self.state, "_install_sync") as install_sync,
        ):
            result = self.state._preflight_module(module, allow_repair=True)

        cleanup_env.assert_called_once_with("dummy")
        install_sync.assert_called_once_with("dummy")
        self.assertEqual(run_import_probe.call_count, 2)
        self.assertEqual(result.status, launcher_server.PREFLIGHT_OK)
        self.assertEqual(result.environment_fingerprint, "fingerprint-after")

    def test_cleanup_module_environment_removes_disposable_poetry_artifacts(self) -> None:
        self._write_poetry_pyproject()
        install_dir = self.repo_root / "dummy_module"
        for venv_name in (".venv", "venv"):
            venv_python = install_dir / venv_name / "bin" / "python"
            venv_python.parent.mkdir(parents=True, exist_ok=True)
            venv_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
            venv_python.chmod(0o755)
        poetry_toml = install_dir / "poetry.toml"
        poetry_toml.write_text("[virtualenvs]\nin-project = true\n", encoding="utf-8")
        fallback_env_root = self.repo_root / ".poetry-envs" / "dummy"
        fallback_python = fallback_env_root / "bin" / "python"
        fallback_python.parent.mkdir(parents=True, exist_ok=True)
        fallback_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fallback_python.chmod(0o755)

        with (
            mock.patch.object(launcher_server, "_poetry_command", return_value="poetry"),
            mock.patch.object(launcher_server.subprocess, "run") as poetry_run,
        ):
            self.state._cleanup_module_environment("dummy")

        self.assertFalse((install_dir / ".venv").exists())
        self.assertFalse((install_dir / "venv").exists())
        self.assertFalse(poetry_toml.exists())
        self.assertFalse(fallback_env_root.exists())
        poetry_run.assert_called_once_with(
            ["poetry", "env", "remove", "--all"],
            cwd=install_dir.resolve(),
            capture_output=True,
            text=True,
            check=False,
        )

    def test_install_sync_uses_poetry_install_no_root_for_poetry_projects(self) -> None:
        self._write_poetry_pyproject()
        poetry_python = self._create_fake_poetry_python()

        with (
            mock.patch.object(launcher_server, "_poetry_command", return_value="poetry"),
            mock.patch.object(
                launcher_server.subprocess,
                "run",
                return_value=mock.Mock(returncode=0, stdout=str(poetry_python.parents[1]), stderr=""),
            ),
            mock.patch.object(self.state, "_run_command") as run_command,
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                return_value="fingerprint-poetry",
            ),
        ):
            self.state._install_sync("dummy")

        self.assertEqual(
            run_command.call_args_list[-1].args[0],
            ["poetry", "install", "--no-interaction", "--no-root"],
        )

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
