"""Launcher control service tests: hardware preflight and doctor (akida connectivity, device verdicts, remote doctor, status reports)."""

from typing import Any
from unittest import mock

from base import LauncherControlServiceTestBase

import nmtk.launcher_control.server as launcher_server
from nmtk.launcher_control import provisioning_helpers


class TestLauncherHardwarePreflight(LauncherControlServiceTestBase):
    def test_akida_host_connectivity_marks_host_reachable(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={"status": "ok"},
        ) as request:
            updated = self.state.test_akida_host_connection(host["id"])

        self.assertEqual(updated["state"], "reachable")
        self.assertEqual(updated["lastPreflightMessage"], "Health reachable: ok")
        request.assert_called_once()

    def test_akida_host_preflight_reports_degraded_optional_capability(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={
                "sdk_available": False,
                "sdk_status": "sdk_unavailable",
                "sdk_issues": ["sdk_not_available", "unsupported_os"],
                "sdk_issue_detail": "BrainChip SDK missing on remote host",
                "runtime_target": "local_sdk",
                "environment_checks": {
                    "host_supported": False,
                    "python_supported": True,
                    "tensorflow_available": False,
                    "cnn2snn_available": False,
                    "akida_models_available": False,
                    "recommended_runtime": "local_sdk",
                },
            },
        ):
            result = self.state.fetch_akida_host_preflight(host["id"])

        self.assertEqual(
            result["host"]["state"],
            "degraded_optional_capability",
        )
        self.assertEqual(
            result["preflight"]["preflight_status"],
            launcher_server.PREFLIGHT_DEGRADED,
        )
        self.assertEqual(
            result["preflight"]["preflight_message"],
            "BrainChip SDK missing on remote host",
        )
        self.assertEqual(result["host"]["lastSdkStatus"], "sdk_unavailable")

    def _akida_probe_verdict(self, probe: dict[str, Any], usb: str = "") -> str:
        """Run the generated remote doctor's classifier on one probe result.

        The classifier ships inside the remote script text, so exec'ing the
        generated source is what actually proves the shipped copy behaves —
        importing a parallel implementation would not.
        """
        namespace: dict[str, Any] = {}
        exec(  # noqa: S102
            provisioning_helpers._remote_control_script_text().split("def _local_json")[
                0
            ],
            namespace,
        )
        return str(namespace["_akida_device_message"](probe, usb))

    def test_remote_doctor_names_the_hardware_fault_it_finds(self) -> None:
        absent = self._akida_probe_verdict({"present": False})
        unbound = self._akida_probe_verdict({"present": True, "driver": ""})
        wedged = self._akida_probe_verdict(
            {"present": True, "driver": "akida-pcie", "memorySpaceEnabled": False}
        )
        healthy = self._akida_probe_verdict(
            {"present": True, "driver": "akida-pcie", "memorySpaceEnabled": True}
        )

        self.assertIn("No Akida board", absent)
        self.assertIn("PCIe driver is not loaded", unbound)
        # The probe is PCI-only, so a USB Akida is absent from it. Claiming
        # "no board" there would be a confident lie; keep the SDK's own words.
        self.assertEqual(
            self._akida_probe_verdict(
                {"present": False},
                "Bus 002 Device 004: ID 1e7c:1000 BrainChip Akida USB",
            ),
            "",
        )
        self.assertIn("stopped responding", wedged)
        self.assertIn("off and on again", wedged)
        # Empty means "not a hardware fault", so a genuine SDK problem keeps
        # its own detail instead of being masked by a board verdict.
        self.assertEqual(healthy, "")

    def test_raw_device_errno_never_reaches_the_readiness_message(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )
        raw = "Error reading at 0xf0000010 len 4: err(110) Connection timed out"

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={
                "sdk_available": True,
                "sdk_status": "unknown",
                "sdk_issues": ["device_mapping_failure"],
                "sdk_issue_detail": raw,
                "runtime_target": "unknown",
            },
        ):
            result = self.state.fetch_akida_host_preflight(host["id"])

        readiness = result["host"]["lastReadinessMessage"]
        self.assertNotIn("0xf0000010", readiness)
        self.assertNotIn("err(110)", readiness)
        self.assertIn("off and on again", readiness)
        # The raw text is the developer's copy and must survive untouched; no
        # Akida client model reads lastPreflightMessage.
        self.assertEqual(result["host"]["lastPreflightMessage"], raw)

    def test_plain_language_preflight_messages_are_left_alone(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )
        message = "An Akida board is fitted but its PCIe driver is not loaded."

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={
                "sdk_available": True,
                "sdk_status": "unknown",
                "sdk_issues": ["device_mapping_failure"],
                "sdk_issue_detail": message,
                "runtime_target": "unknown",
            },
        ):
            result = self.state.fetch_akida_host_preflight(host["id"])

        self.assertEqual(result["host"]["lastReadinessMessage"], message)

    def test_akida_host_preflight_reports_failed_when_runtime_request_errors(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            side_effect=RuntimeError("remote verify exploded"),
        ):
            result = self.state.fetch_akida_host_preflight(host["id"])

        self.assertEqual(result["host"]["state"], "preflight_failed")
        self.assertEqual(
            result["preflight"]["preflight_status"],
            launcher_server.PREFLIGHT_FAILED,
        )
        self.assertIn(
            "remote verify exploded", result["preflight"]["preflight_message"]
        )

    def test_akida_remote_control_doctor_accepts_visible_hardware_before_model_mapping(
        self,
    ) -> None:
        namespace: dict[str, Any] = {}
        # exec is intentional: exercise the generated remote-control script
        # verbatim, isolated in a fresh namespace. The source is repo-owned
        # template text, not user input.
        exec(provisioning_helpers._remote_control_script_text(), namespace)  # noqa: S102

        def fake_local_json(path: str) -> tuple[int, dict[str, Any]]:
            if path == "/health":
                return 200, {"status": "healthy"}
            if path == "/api/neurochip/akida/status":
                return 200, {
                    "sdk_available": True,
                    "sdk_status": "unknown",
                    "sdk_issues": [],
                    "sdk_issue_detail": None,
                    "runtime_target": "hardware",
                    "device_info": "<akida.core.HardwareDevice object>",
                    "environment_checks": {
                        "host_supported": True,
                        "python_supported": True,
                        "tensorflow_available": True,
                        "cnn2snn_available": True,
                        "akida_models_available": True,
                        "recommended_runtime": "local_sdk",
                    },
                }
            raise AssertionError(f"unexpected path: {path}")

        namespace["_local_json"] = fake_local_json
        namespace["_run_probe"] = lambda _command: ""
        namespace["_load_install_status"] = lambda: {"installMode": "systemd"}

        payload = namespace["_doctor_payload"]()

        self.assertEqual(
            payload["preflight"]["preflight_status"], launcher_server.PREFLIGHT_OK
        )
        self.assertEqual(
            payload["preflight"]["preflight_message"],
            "Akida hardware runtime is ready.",
        )
        self.assertTrue(payload["preflight"]["physicalHardwareReady"])

    def test_akida_install_script_force_reinstalls_bundled_neurochip_wheel(
        self,
    ) -> None:
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
            wheel_name="neurochip-0.6.0-py3-none-any.whl",
            artifact_version="0.6.0",
            artifact_sha256="a" * 64,
            required_packages=[],
        )

        self.assertIn("akida_pip install --force-reinstall", script)
        self.assertNotIn("akida_pip install --force-reinstall --no-deps", script)

    def test_akida_preflight_promotes_stale_remote_doctor_when_hardware_is_ready(
        self,
    ) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "host": "akida-box.local",
                "username": "operator",
            }
        )
        runtime_status = {
            "sdk_available": True,
            "sdk_status": "unknown",
            "sdk_issues": [],
            "runtime_target": "hardware",
        }

        updated = self.state._apply_preflight_to_akida_host(
            host["id"],
            {
                "preflight_status": launcher_server.PREFLIGHT_DEGRADED,
                "preflight_message": "Optional Akida capability is degraded.",
                "runtime_target": "hardware",
                "sdk_status": "unknown",
            },
            runtime_status=runtime_status,
            install_status={"installMode": "systemd"},
        )

        self.assertEqual(updated["state"], "ready")
        self.assertEqual(updated["lastPreflightStatus"], launcher_server.PREFLIGHT_OK)
        self.assertEqual(
            updated["lastPreflightMessage"], "Akida hardware runtime is ready."
        )

    def test_akida_host_preflight_fallback_logs_single_high_level_message(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "controlApiUrl": "http://akida-box.local:8091",
            }
        )

        fallback_calls: list[tuple[str, str]] = []

        def _record_runtime_status(
            _host: dict[str, Any], method: str, path: str
        ) -> dict[str, Any]:
            fallback_calls.append((method, path))
            return {
                "sdk_available": False,
                "sdk_status": "sdk_unavailable",
                "sdk_issues": ["sdk_not_available"],
                "sdk_issue_detail": "BrainChip SDK missing on remote host",
                "runtime_target": "local_sdk",
                "environment_checks": {
                    "host_supported": False,
                    "python_supported": True,
                    "tensorflow_available": False,
                    "cnn2snn_available": False,
                    "akida_models_available": False,
                    "recommended_runtime": "local_sdk",
                },
            }

        with (
            self.assertLogs(
                "nmtk.launcher_control.akida_remote_client", level="ERROR"
            ) as captured,
            mock.patch.object(
                self.state,
                "_akida_control_json_request",
                side_effect=RuntimeError(
                    "Control request failed for GET http://akida-box.local:8090/api/remote-akida/doctor: offline"
                ),
            ),
            mock.patch.object(
                self.state,
                "_akida_json_request",
                side_effect=_record_runtime_status,
            ),
        ):
            self.state.fetch_akida_host_preflight(host["id"])

        log_output = "\n".join(
            str(getattr(record, "message_detail", record.getMessage()))
            for record in captured.records
        )
        self.assertEqual(fallback_calls, [("GET", "/api/neurochip/akida/status")])
        self.assertIn("remote control API unavailable during preflight", log_output)
        self.assertIn("falling back to runtime status", log_output)
        self.assertNotIn("control request failed:", log_output)

    def test_akida_host_status_fallback_logs_single_high_level_message(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "controlApiUrl": "http://akida-box.local:8091",
                "lastPreflightStatus": launcher_server.PREFLIGHT_OK,
            }
        )

        with (
            self.assertLogs(
                "nmtk.launcher_control.akida_remote_client", level="ERROR"
            ) as captured,
            mock.patch.object(
                self.state,
                "_akida_control_json_request",
                side_effect=RuntimeError(
                    "Control request failed for GET http://akida-box.local:8090/api/remote-akida/doctor: offline"
                ),
            ),
            mock.patch.object(
                self.state,
                "_akida_json_request",
                return_value={"state": "mapped", "device_info": "AKD1000"},
            ),
        ):
            result = self.state.fetch_akida_host_status(host["id"])

        self.assertEqual(result["host"]["state"], "ready")
        log_output = "\n".join(
            str(getattr(record, "message_detail", record.getMessage()))
            for record in captured.records
        )
        self.assertIn("remote control API unavailable during status poll", log_output)
        self.assertNotIn("control request failed:", log_output)

    def test_akida_host_status_marks_mapped_host_ready(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "lastPreflightStatus": launcher_server.PREFLIGHT_OK,
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={"state": "mapped", "device_info": "AKD1000"},
        ):
            result = self.state.fetch_akida_host_status(host["id"])

        self.assertEqual(result["host"]["state"], "ready")
        self.assertEqual(result["status"]["state"], "mapped")

    def test_akida_host_status_marks_failed_host_error(self) -> None:
        host = self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
            }
        )

        with mock.patch.object(
            self.state,
            "_akida_json_request",
            return_value={"state": "failed"},
        ):
            result = self.state.fetch_akida_host_status(host["id"])

        self.assertEqual(result["host"]["state"], "error")
        self.assertEqual(result["status"]["state"], "failed")

    def test_doctor_report_includes_akida_hosts(self) -> None:
        self.state.create_akida_host(
            {
                "displayName": "Lab Akida",
                "baseUrl": "http://akida-box.local:8002",
                "state": "degraded_optional_capability",
                "lastPreflightStatus": launcher_server.PREFLIGHT_DEGRADED,
                "lastPreflightMessage": "BrainChip SDK missing on remote host",
            }
        )

        with mock.patch.object(
            self.state,
            "_preflight_module",
            return_value=launcher_server.PreflightResult(
                status=launcher_server.PREFLIGHT_OK,
                message="ok",
                environment_fingerprint="fingerprint-4",
            ),
        ):
            report = self.state.doctor_report()

        self.assertIn("akidaHosts", report)
        self.assertEqual(
            report["akidaHosts"][0]["state"],
            "degraded_optional_capability",
        )
        self.assertGreaterEqual(report["degradedCount"], 1)

    def test_doctor_report_includes_pynq_boards(self) -> None:
        self.state.create_pynq_board(
            {
                "displayName": "Desk PYNQ",
                "host": "198.51.100.50",
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

    def test_doctor_report_includes_ready_remote_sdk_akida_hosts(self) -> None:
        self.state.create_akida_host(
            {
                "displayName": "Linux Akida Host",
                "runtimeApiUrl": "http://198.51.100.60:8002",
                "runtimeMode": "remote_sdk",
                "state": "ready",
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

        self.assertIn("akidaHosts", report)
        self.assertEqual(report["akidaHosts"][0]["runtimeMode"], "remote_sdk")
        self.assertEqual(report["akidaHosts"][0]["state"], "ready")
