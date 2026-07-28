"""Launcher control service tests: TestLauncherLifecycleDoctorCli."""

from pathlib import Path
import io
import json
import nmtk.launcher_control.server as launcher_server
import nmtk.launcher_control.module_lifecycle as launcher_module_lifecycle
import nmtk.launcher_control.module_install as launcher_module_install
import nmtk.launcher_control.doctor_service as launcher_doctor_service
from unittest import mock
import os
import subprocess
import sys
import urllib.request
from base import LauncherControlServiceTestBase, PROJECT_ROOT


class TestLauncherLifecycleDoctorCli(LauncherControlServiceTestBase):
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

        with mock.patch.object(
            launcher_module_lifecycle,
            "_suite_api_health_probe",
            return_value=(False, "connection refused"),
        ):
            with self.assertRaises(RuntimeError):
                self.state._start_sync("dummy")

        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["error"])
        self.assertIn("not reachable", payload["healthStatus"])

    def test_health_poll_promotes_waiting_monolith_after_suite_api_recovers(self) -> None:
        module = self.state._get_module("dummy")
        module["startStrategy"] = "none"
        module["port"] = launcher_server.DEFAULT_SUITE_API_PORT
        module["status"] = launcher_server.STATUS_INDEX["starting"]
        self.state._manage_suite_api = False

        with (
            mock.patch.object(
                launcher_module_lifecycle,
                "_suite_api_health_probe",
                return_value=(True, '{"status":"ok"}'),
            ),
            mock.patch.object(self.state, "_shutdown") as mock_shutdown,
        ):
            mock_shutdown.wait.side_effect = [False, True]
            self.state._health_poll_loop()

        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["running"])
        self.assertEqual(payload["healthStatus"], "Managed by suite_api")

    def test_doctor_report_marks_fatal_preflight_as_blocking(self) -> None:
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["installed"]
        with (
            mock.patch.object(
                launcher_module_lifecycle, "_global_preflight_checks", return_value=[]
            ),
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
        self.assertEqual(
            report["modules"][0]["preflightStatus"], launcher_server.PREFLIGHT_FAILED
        )
        self.assertIn("fastapi", report["modules"][0]["preflightMessage"])

    def test_doctor_report_marks_suite_api_failure_as_blocking_for_monolith_modules(
        self,
    ) -> None:
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["installed"]
        module["startStrategy"] = "none"
        module["port"] = launcher_server.DEFAULT_SUITE_API_PORT  # monolith port
        self.state._manage_suite_api = True
        self.state._suite_api_status = launcher_server.SUITE_API_STATUS_PREFLIGHT_FAILED
        self.state._suite_api_message = (
            "suite_api port 9000 is occupied by another process"
        )

        with mock.patch.object(
            launcher_module_lifecycle, "_global_preflight_checks", return_value=[]
        ):
            report = self.state.doctor_report()

        self.assertEqual(report["status"], "error")
        self.assertEqual(report["fatalCount"], 1)
        self.assertEqual(
            report["modules"][0]["preflightStatus"], launcher_server.PREFLIGHT_FAILED
        )
        self.assertIn("port 9000", report["modules"][0]["preflightMessage"])

    def test_doctor_report_keeps_optional_capability_degradation_nonfatal(self) -> None:
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["installed"]
        with (
            mock.patch.object(
                launcher_module_lifecycle, "_global_preflight_checks", return_value=[]
            ),
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

    def test_start_sync_external_service_marks_running_when_healthy(self) -> None:
        """When an externally managed standalone service responds to health,
        _start_sync should mark it running without any suite_api interaction."""
        module = self.state._get_module("dummy")
        # Remove uvicornTarget so _module_start_strategy returns "none";
        # port 8123 != DEFAULT_SUITE_API_PORT so it becomes externally managed.
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"

        with mock.patch.object(
            self.state, "_probe_health", return_value=(True, 200, "healthy")
        ):
            self.state._start_sync("dummy")

        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["running"])
        self.assertEqual(payload["healthStatus"], "healthy")

    def test_start_sync_external_service_marks_error_when_not_reachable(self) -> None:
        """When an externally managed service is not reachable, _start_sync
        should raise RuntimeError and mark the module as error."""
        module = self.state._get_module("dummy")
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"
        module["deployment"] = {
            "composeProfile": "notebooks",
            "healthPath": "/api/status",
        }

        with mock.patch.object(
            self.state, "_probe_health", return_value=(False, 0, None)
        ):
            self.state._start_sync("dummy")

        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], 0)
        self.assertIn("port", payload["healthStatus"])

    def test_start_sync_external_service_does_not_check_suite_api(self) -> None:
        """Externally managed services must not gate on suite_api readiness."""
        module = self.state._get_module("dummy")
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"
        self.state._manage_suite_api = True
        self.state._suite_api_status = launcher_server.SUITE_API_STATUS_PREFLIGHT_FAILED

        with mock.patch.object(
            self.state, "_probe_health", return_value=(True, 200, "ok")
        ):
            self.state._start_sync("dummy")

        payload = self.state.serialize_module("dummy")
        # Should be running despite suite_api being down
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["running"])

    def test_probe_health_uses_deployment_health_path_for_external_service(
        self,
    ) -> None:
        """_probe_health should use deployment.healthPath for externally managed
        services, not the monolith /api/<id>/health pattern."""
        module = self.state._get_module("dummy")
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"
        module["deployment"] = {"healthPath": "/api/status"}

        captured_urls: list[str] = []

        def fake_urlopen(url: str, timeout: float = 2.0) -> object:
            captured_urls.append(url)
            raise urllib.error.URLError("connection refused")

        with mock.patch("urllib.request.urlopen", side_effect=fake_urlopen):
            self.state._probe_health(module)

        self.assertEqual(len(captured_urls), 1)
        self.assertIn("/api/status", captured_urls[0])
        self.assertNotIn(f"/api/{module['id']}/health", captured_urls[0])

    def test_doctor_report_external_service_reachable_is_ok(self) -> None:
        """doctor_report should report PREFLIGHT_OK for a reachable external service."""
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["installed"]
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"

        with (
            mock.patch.object(
                launcher_module_lifecycle, "_global_preflight_checks", return_value=[]
            ),
            mock.patch.object(
                self.state, "_probe_health", return_value=(True, 200, "ok")
            ),
        ):
            report = self.state.doctor_report()

        self.assertEqual(
            report["modules"][0]["preflightStatus"], launcher_server.PREFLIGHT_OK
        )
        self.assertEqual(report["fatalCount"], 0)
        self.assertEqual(report["degradedCount"], 0)

    def test_doctor_report_external_service_not_reachable_is_degraded(self) -> None:
        """doctor_report should report PREFLIGHT_DEGRADED (not fatal) when an
        external service is not running — it is optional and externally managed."""
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["installed"]
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"
        module["deployment"] = {
            "composeProfile": "notebooks",
            "healthPath": "/api/status",
        }

        with (
            mock.patch.object(
                launcher_module_lifecycle, "_global_preflight_checks", return_value=[]
            ),
            mock.patch.object(
                self.state, "_probe_health", return_value=(False, 0, None)
            ),
        ):
            report = self.state.doctor_report()

        self.assertEqual(
            report["modules"][0]["preflightStatus"], launcher_server.PREFLIGHT_DEGRADED
        )
        self.assertIn("notebooks", report["modules"][0]["preflightMessage"])
        self.assertEqual(report["fatalCount"], 0)
        self.assertEqual(report["degradedCount"], 1)

    def test_health_poll_loop_recovers_external_service_from_error(self) -> None:
        """The health poll loop should transition an external service from error
        back to running when it becomes reachable again."""
        module = self.state._get_module("dummy")
        module["uvicornTarget"] = ""
        module["startStrategy"] = "none"
        module["status"] = launcher_server.STATUS_INDEX["error"]

        call_count = 0

        def probe_side_effect(m: dict) -> tuple[bool, int, str | None]:
            nonlocal call_count
            call_count += 1
            if launcher_server._is_externally_managed_service(m):
                return (True, 200, "recovered")
            return (False, 0, None)

        with (
            mock.patch.object(
                self.state,
                "_suite_api_health_probe" if False else "_probe_health",
                side_effect=probe_side_effect,
            ),
            mock.patch.object(self.state, "_shutdown") as mock_shutdown,
        ):
            # Simulate one poll tick, then stay shut down. A callable avoids a
            # fragile finite iterator when another lifecycle worker observes
            # the mocked shutdown event during test teardown.
            poll_count = 0

            def stop_after_first_poll(_: float) -> bool:
                nonlocal poll_count
                poll_count += 1
                return poll_count > 1

            mock_shutdown.wait.side_effect = stop_after_first_poll
            self.state._manage_suite_api = False
            self.state._health_poll_loop()

        payload = self.state.serialize_module("dummy")
        self.assertEqual(payload["status"], launcher_server.STATUS_INDEX["running"])
        self.assertEqual(payload["healthStatus"], "recovered")

    def test_doctor_report_handles_akida_hosts_without_cached_host_field(self) -> None:
        self.state._settings["akidaHosts"] = [
            {
                "id": "akida-1",
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "state": "ready",
                "lastPreflightStatus": launcher_server.PREFLIGHT_OK,
            }
        ]
        with (
            mock.patch.object(
                launcher_module_lifecycle, "_global_preflight_checks", return_value=[]
            ),
            mock.patch.object(
                self.state,
                "_preflight_module",
                return_value=launcher_server.PreflightResult(
                    status=launcher_server.PREFLIGHT_OK,
                    message="ready",
                    environment_fingerprint="fingerprint-ok",
                ),
            ),
        ):
            report = self.state.doctor_report()

        self.assertEqual(report["status"], "ok")
        self.assertEqual(report["akidaHosts"][0]["host"], "akida-box.local")
        self.assertEqual(
            report["akidaHosts"][0]["baseUrl"], "http://akida-box.local:8002"
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
                launcher_module_lifecycle,
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
            mock.patch.object(
                launcher_server.shutil, "which", return_value=str(flutter_bin)
            ),
            mock.patch.object(launcher_server.os, "access", side_effect=fake_access),
        ):
            checks = launcher_doctor_service._global_preflight_checks()

        flutter_check = next(check for check in checks if check["id"] == "flutter-sdk")
        self.assertEqual(
            flutter_check["preflightStatus"], launcher_server.PREFLIGHT_FAILED
        )
        self.assertIn("not writable", str(flutter_check["preflightMessage"]))

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
            mock.patch.object(
                launcher_server, "LauncherControlState", return_value=fake_state
            ),
            mock.patch.object(sys, "stdout", stdout),
        ):
            exit_code = launcher_server.main(["--doctor", "--json"])

        self.assertEqual(exit_code, 1)
        fake_state.shutdown.assert_called_once()
        self.assertEqual(
            json.loads(stdout.getvalue()), fake_state.doctor_report.return_value
        )

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
            mock.patch.object(
                launcher_server, "LauncherControlState", return_value=fake_state
            ),
            mock.patch.object(sys, "stdout", stdout),
        ):
            exit_code = launcher_server.main(["--doctor", "--json"])

        self.assertEqual(exit_code, 0)
        fake_state.shutdown.assert_called_once()
        self.assertEqual(
            json.loads(stdout.getvalue()), fake_state.doctor_report.return_value
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

    def test_preflight_accepts_recovered_poetry_probe_despite_stale_failed_fingerprint(
        self,
    ) -> None:
        self._write_poetry_pyproject()
        poetry_python = self.repo_root / "dummy_module" / ".venv" / "bin" / "python"
        poetry_python.parent.mkdir(parents=True, exist_ok=True)
        poetry_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        poetry_python.chmod(0o755)
        module = self.state._get_module("dummy")
        module["environmentFingerprint"] = "stale-fingerprint"
        module["preflightStatus"] = launcher_server.PREFLIGHT_FAILED
        module["preflightMessage"] = (
            "Missing required dependency: fastapi (needed by app.main)"
        )

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

    def test_cleanup_module_environment_removes_disposable_poetry_artifacts(
        self,
    ) -> None:
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
            mock.patch.object(
                launcher_module_install, "_poetry_command", return_value="poetry"
            ),
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
            mock.patch.object(
                launcher_module_install, "_poetry_command", return_value="poetry"
            ),
            mock.patch.object(
                launcher_server.subprocess,
                "run",
                return_value=mock.Mock(
                    returncode=0, stdout=str(poetry_python.parents[1]), stderr=""
                ),
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

    def test_install_sync_uses_module_python_for_pip_commands_when_only_dotvenv_exists(
        self,
    ) -> None:
        install_dir = self.repo_root / "dummy_module"
        dotvenv_python = install_dir / ".venv" / "bin" / "python"
        dotvenv_python.parent.mkdir(parents=True, exist_ok=True)
        dotvenv_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        dotvenv_python.chmod(0o755)

        with (
            mock.patch.object(self.state, "_run_command") as run_command,
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                return_value="fingerprint-dotvenv",
            ),
        ):
            self.state._install_sync("dummy")

        pip_calls = [
            call.args[0]
            for call in run_command.call_args_list
            if call.args and isinstance(call.args[0], list) and "pip" in call.args[0]
        ]
        self.assertTrue(
            any(
                call[:4] == [str(call[0]), "-m", "pip", "install"]
                and str(call[0]).endswith("/dummy_module/.venv/bin/python")
                and call[-1] == "."
                for call in pip_calls
            )
        )
        self.assertFalse(
            any(
                str(call[0]).endswith("/dummy_module/venv/bin/pip")
                for call in pip_calls
            )
        )

    def test_install_sync_bootstraps_pip_when_module_env_lacks_it(self) -> None:
        install_dir = self.repo_root / "dummy_module"
        dotvenv_python = install_dir / ".venv" / "bin" / "python"
        dotvenv_python.parent.mkdir(parents=True, exist_ok=True)
        dotvenv_python.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        dotvenv_python.chmod(0o755)

        subprocess_results = [
            mock.Mock(returncode=1, stdout="", stderr="No module named pip"),
            mock.Mock(returncode=0, stdout="bootstrapped", stderr=""),
            mock.Mock(returncode=0, stdout="pip 25.0", stderr=""),
        ]

        with (
            mock.patch.object(self.state, "_run_command") as run_command,
            mock.patch.object(
                self.state,
                "_compute_environment_fingerprint",
                return_value="fingerprint-pip-bootstrap",
            ),
            mock.patch.object(
                launcher_server.subprocess,
                "run",
                side_effect=subprocess_results,
            ) as subprocess_run,
        ):
            self.state._install_sync("dummy")

        ensurepip_call = [
            str(dotvenv_python.resolve()),
            "-m",
            "ensurepip",
            "--upgrade",
        ]
        self.assertEqual(subprocess_run.call_args_list[1].args[0], ensurepip_call)
        self.assertTrue(
            any(
                call.args[0][:4]
                == [str(dotvenv_python.resolve()), "-m", "pip", "install"]
                for call in run_command.call_args_list
            )
        )

    def test_repair_module_returns_installing_state_immediately(self) -> None:
        """repair_module() returns the module in 'installing' state immediately."""
        # Prevent the background thread from running so we see the initial state.
        with mock.patch.object(self.state, "_repair_sync", return_value=None):
            result = self.state.repair_module("dummy")

        self.assertEqual(result["status"], launcher_server.STATUS_INDEX["installing"])
        self.assertIsNone(result["healthStatus"])
        self.assertEqual(result["preflightStatus"], launcher_server.PREFLIGHT_OK)

    def test_repair_module_sets_installed_when_preflight_ok(self) -> None:
        """After a successful repair (preflight OK), module ends in 'installed' state."""
        # Put the module in error first.
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["error"]
        module["healthStatus"] = "import probe failed"

        ok_result = launcher_server.PreflightResult(
            status=launcher_server.PREFLIGHT_OK,
            message=None,
            capability_warnings=[],
            environment_fingerprint="abc123",
        )
        with mock.patch.object(self.state, "_preflight_module", return_value=ok_result):
            self.state.repair_module("dummy")
            task = self.state._tasks.get("dummy")
            if task:
                task.join(timeout=5.0)

        module = self.state._get_module("dummy")
        self.assertEqual(module["status"], launcher_server.STATUS_INDEX["installed"])
        self.assertIsNone(module["healthStatus"])

    def test_repair_module_sets_error_when_preflight_fails(self) -> None:
        """After a failed repair (preflight FAILED), module ends in 'error' state."""
        module = self.state._get_module("dummy")
        module["status"] = launcher_server.STATUS_INDEX["error"]

        failed_result = launcher_server.PreflightResult(
            status=launcher_server.PREFLIGHT_FAILED,
            message="Cannot find required dependency: torch",
            capability_warnings=[],
            environment_fingerprint=None,
        )
        with mock.patch.object(
            self.state, "_preflight_module", return_value=failed_result
        ):
            self.state.repair_module("dummy")
            task = self.state._tasks.get("dummy")
            if task:
                task.join(timeout=5.0)

        module = self.state._get_module("dummy")
        self.assertEqual(module["status"], launcher_server.STATUS_INDEX["error"])
        self.assertEqual(
            module["healthStatus"], "Cannot find required dependency: torch"
        )

    def test_install_sync_cleans_venv_on_pip_failure(self) -> None:
        """When pip install fails, _install_sync removes the partial venv directory."""
        # Create a fake partial venv as if a previous install was interrupted.
        venv_path = self.repo_root / "dummy_module" / "venv"
        venv_path.mkdir(parents=True, exist_ok=True)
        (venv_path / "pyvenv.cfg").write_text("home = /usr/bin\n", encoding="utf-8")

        # Make _run_command raise to simulate a pip failure.
        call_count: dict[str, int] = {"n": 0}
        original_run_cmd = self.state._run_command

        def fail_on_pip(command: list, cwd: object, module_id: str) -> None:
            call_count["n"] += 1
            if "pip" in command or "install" in command:
                raise RuntimeError("pip install failed: network error")
            return original_run_cmd(command, cwd, module_id)  # type: ignore[return-value]

        with mock.patch.object(self.state, "_run_command", side_effect=fail_on_pip):
            with self.assertRaises(RuntimeError):
                self.state._install_sync("dummy")

        self.assertFalse(
            venv_path.exists(),
            "Partial venv directory must be removed after a failed pip install",
        )
