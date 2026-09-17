"""Launcher control service tests: doctor report (fatal vs degraded findings, external services, exit codes)."""

import io
import json
import os
import sys
import urllib.request
from pathlib import Path
from unittest import mock

from base import LauncherControlServiceTestBase

import nmtk.launcher_control.doctor_service as launcher_doctor_service
import nmtk.launcher_control.module_lifecycle as launcher_module_lifecycle
import nmtk.launcher_control.server as launcher_server


class TestLauncherDoctorReport(LauncherControlServiceTestBase):
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

        # Stop background health thread to prevent race conditions during synchronous test
        self.state._shutdown.set()
        if (
            hasattr(self.state, "_health_thread")
            and self.state._health_thread.is_alive()
        ):
            self.state._health_thread.join(timeout=2.0)
        self.state._shutdown.clear()

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
            return normalized not in {resolved_cache_dir, resolved_engine_stamp}

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

    def test_global_preflight_checks_skip_flutter_on_remote_backend(self) -> None:
        with mock.patch.dict(
            os.environ,
            {"NMTK_BACKEND_DEPLOYMENT_READY": "1"},
            clear=True,
        ):
            checks = launcher_doctor_service._global_preflight_checks()

        check_ids = {check["id"] for check in checks}
        self.assertNotIn("flutter-sdk", check_ids)
        self.assertIn("studio-framework-sdks", check_ids)

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
            ) as state_factory,
            mock.patch.object(sys, "stdout", stdout),
        ):
            exit_code = launcher_server.main(["--doctor", "--json"])

        self.assertEqual(exit_code, 1)
        fake_state.shutdown.assert_called_once()
        state_factory.assert_called_once_with(diagnostic=True)
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
