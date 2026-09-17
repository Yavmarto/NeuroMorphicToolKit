"""Launcher control service tests: module lifecycle CLI (argument binding, start path, health polling)."""

import os
import subprocess
import sys
import threading
from pathlib import Path
from unittest import mock

from base import PROJECT_ROOT, LauncherControlServiceTestBase

import nmtk.launcher_control.module_lifecycle as launcher_module_lifecycle
import nmtk.launcher_control.server as launcher_server
import nmtk.launcher_control.suite_api_service as launcher_suite_api_service


class TestLauncherLifecycleDoctorCli(LauncherControlServiceTestBase):
    def test_cli_binds_to_loopback_unless_remote_host_is_explicit(self) -> None:
        parser = launcher_server._build_cli_parser()

        self.assertEqual(parser.parse_args([]).host, "127.0.0.1")
        self.assertEqual(parser.parse_args(["--host", "0.0.0.0"]).host, "0.0.0.0")

    def test_diagnostic_state_starts_no_background_work(self) -> None:
        with (
            mock.patch.object(threading.Thread, "start") as start_thread,
            mock.patch.object(subprocess, "Popen") as start_process,
            mock.patch.object(launcher_server, "_write_json_file") as server_write,
            mock.patch.object(
                launcher_module_lifecycle, "_write_json_file"
            ) as lifecycle_write,
            mock.patch.object(Path, "write_text") as path_write,
        ):
            state = launcher_server.LauncherControlState(diagnostic=True)
            try:
                report = state.doctor_report()
            finally:
                state.shutdown()

        start_thread.assert_not_called()
        start_process.assert_not_called()
        server_write.assert_not_called()
        lifecycle_write.assert_not_called()
        path_write.assert_not_called()
        self.assertIn("fatalCount", report)

    def test_doctor_report_skips_not_installed_module_preflight(self) -> None:
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["notInstalled"]

        with mock.patch.object(self.state, "_preflight_module") as preflight:
            report = self.state.doctor_report()

        preflight.assert_not_called()
        self.assertEqual(
            report["modules"][0]["preflightMessage"], "Module not installed"
        )

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
            check=False,
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
            check=False,
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
            mock.patch.object(
                self.state, "_probe_health", return_value=(True, 200, "ok")
            ),
            mock.patch.object(
                launcher_server.subprocess, "Popen", return_value=_FakeProcess()
            ) as popen,
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
            self.assertRaises(RuntimeError),
        ):
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
            mock.patch.object(
                self.state, "_probe_health", return_value=(True, 200, "ok")
            ),
            mock.patch.object(
                launcher_server.subprocess, "Popen", return_value=_FakeProcess()
            ),
        ):
            self.state._start_sync("dummy")

        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["degraded"])
        self.assertEqual(payload["preflightStatus"], launcher_server.PREFLIGHT_DEGRADED)
        self.assertEqual(
            payload["capabilityWarnings"],
            ["Optional capability unavailable: lava.magma.core.run_conditions"],
        )

    def test_start_module_requires_suite_api_ready_for_monolith_modules(self) -> None:
        module = self.state._get_module("dummy")
        module["startStrategy"] = "none"
        module["port"] = launcher_server.DEFAULT_SUITE_API_PORT  # monolith port
        self.state._manage_suite_api = True
        self.state._suite_api_status = launcher_server.SUITE_API_STATUS_PREFLIGHT_FAILED
        self.state._suite_api_message = "suite_api runtime dependencies are missing"

        with self.assertRaises(RuntimeError) as exc_info:
            self.state._start_sync("dummy")

        self.assertIn(
            "suite_api runtime dependencies are missing", str(exc_info.exception)
        )
        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["error"])
        self.assertEqual(payload["preflightStatus"], launcher_server.PREFLIGHT_FAILED)
        self.assertIn("suite_api", payload["preflightMessage"])

    def test_start_monolith_requires_suite_api_health_in_container_mode(self) -> None:
        module = self.state._get_module("dummy")
        module["startStrategy"] = "none"
        module["port"] = launcher_server.DEFAULT_SUITE_API_PORT
        self.state._manage_suite_api = False

        with (
            mock.patch.object(
                launcher_suite_api_service,
                "_suite_api_health_probe",
                return_value=(False, "connection refused"),
            ),
            self.assertRaises(RuntimeError),
        ):
            self.state._start_sync("dummy")

        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["error"])
        self.assertIn("not reachable", payload["healthStatus"])

    def test_health_poll_promotes_waiting_monolith_after_suite_api_recovers(
        self,
    ) -> None:
        module = self.state._get_module("dummy")
        module["startStrategy"] = "none"
        module["port"] = launcher_server.DEFAULT_SUITE_API_PORT
        module["status"] = launcher_server.STATUS_INDEX["starting"]
        self.state._manage_suite_api = False

        # Stop background health thread to prevent race conditions during synchronous test
        self.state._shutdown.set()
        if (
            hasattr(self.state, "_health_thread")
            and self.state._health_thread.is_alive()
        ):
            self.state._health_thread.join(timeout=2.0)
        self.state._shutdown.clear()

        with (
            mock.patch.object(
                launcher_module_lifecycle,
                "_suite_api_health_probe",
                return_value=(True, '{"status":"ok"}'),
            ),
            mock.patch.object(self.state, "_shutdown") as mock_shutdown,
        ):
            # A callable avoids a fragile finite iterator when another
            # lifecycle worker observes the mocked shutdown event during
            # test teardown.
            poll_count = 0

            def stop_after_first_poll(_: float) -> bool:
                nonlocal poll_count
                poll_count += 1
                return poll_count > 1

            mock_shutdown.wait.side_effect = stop_after_first_poll
            self.state._health_poll_loop()

        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["running"])
        self.assertEqual(payload["healthStatus"], "Managed by suite_api")

    def test_health_poll_survives_an_unwritable_state_file(self) -> None:
        """An unwritable state volume must not stop status reconciliation.

        The write used to propagate out of the poll thread and end it, so the
        first module to reach "starting" stayed there for the life of the
        process and the workspace waited on it forever.
        """
        module = self.state._get_module("dummy")
        module["startStrategy"] = "none"
        module["port"] = launcher_server.DEFAULT_SUITE_API_PORT
        module["status"] = launcher_server.STATUS_INDEX["starting"]
        self.state._manage_suite_api = False

        self.state._shutdown.set()
        if (
            hasattr(self.state, "_health_thread")
            and self.state._health_thread.is_alive()
        ):
            self.state._health_thread.join(timeout=2.0)
        self.state._shutdown.clear()

        with (
            mock.patch.object(
                launcher_module_lifecycle,
                "_suite_api_health_probe",
                return_value=(True, '{"status":"ok"}'),
            ),
            mock.patch.object(
                launcher_module_lifecycle,
                "_write_json_file",
                side_effect=PermissionError(13, "Permission denied"),
            ),
            mock.patch.object(self.state, "_shutdown") as mock_shutdown,
        ):
            poll_count = 0

            def stop_after_two_polls(_: float) -> bool:
                nonlocal poll_count
                poll_count += 1
                return poll_count > 2

            mock_shutdown.wait.side_effect = stop_after_two_polls
            self.state._health_poll_loop()

        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["running"])
        # Two iterations ran, so the thread outlived the failed write.
        self.assertEqual(poll_count, 3)
