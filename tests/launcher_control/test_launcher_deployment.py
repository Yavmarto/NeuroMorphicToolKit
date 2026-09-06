"""Launcher control service tests: deployment service core (readiness, logs, deployment jobs, job persistence)."""

import io
import json
import sys
import threading
import time
import urllib.request
from pathlib import Path
from unittest import mock

from base import LauncherControlServiceTestBase

import nmtk.launcher_control.server as launcher_server


class TestLauncherDeployment(LauncherControlServiceTestBase):
    def test_persisted_remote_readiness_is_cleared_when_external_probes_fail(
        self,
    ) -> None:
        from nmtk.launcher_control.deployment_service import DeploymentService

        store = mock.Mock()
        store.selected_target.return_value = {
            "id": "remote-192-168-2-34",
            "targetType": "remote_host",
            "host": "192.168.2.34",
            "backendPort": 9000,
            "lastReadiness": "ready",
        }
        service = DeploymentService(store=store, repo_root=Path("/tmp"))

        with mock.patch(
            "nmtk.launcher_control.deployment_service.urllib.request.urlopen",
            side_effect=OSError("connection refused"),
        ):
            self.assertFalse(service.is_ready())

        store.update_target_readiness.assert_called_once_with(
            "remote-192-168-2-34",
            readiness="failed",
            failure_reason=(
                "Required client-facing services are not reachable from "
                "launcher control at 192.168.2.34."
            ),
        )

    def test_persisted_remote_readiness_requires_all_external_probes(self) -> None:
        from nmtk.launcher_control.deployment_service import DeploymentService

        store = mock.Mock()
        store.selected_target.return_value = {
            "id": "remote-192-168-2-34",
            "targetType": "remote_host",
            "host": "192.168.2.34",
            "backendPort": 9000,
            "lastReadiness": "ready",
        }
        response = mock.MagicMock(status=200)
        response.__enter__.return_value = response
        service = DeploymentService(store=store, repo_root=Path("/tmp"))

        with mock.patch(
            "nmtk.launcher_control.deployment_service.urllib.request.urlopen",
            return_value=response,
        ) as urlopen:
            self.assertTrue(service.is_ready())

        self.assertEqual(urlopen.call_count, 3)
        requested_urls = [call.args[0] for call in urlopen.call_args_list]
        self.assertIn("http://192.168.2.34:9000/api/suite/health", requested_urls)
        self.assertIn("http://192.168.2.34:8090/health", requested_urls)
        self.assertIn(
            "http://192.168.2.34:9000/api/neurocnl/health",
            requested_urls,
        )
        store.update_target_readiness.assert_not_called()

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

    def test_deployment_target_persists_without_plaintext_secret(self) -> None:
        target = self.state.create_deployment_target(
            {
                "displayName": "Remote backend",
                "targetType": "remote_host",
                "mode": "standalone",
                "authMode": "ssh_password",
                "host": "192.0.2.10",
                "username": "nmtk",
                "password": "super-secret",
            }
        )

        self.assertEqual(target["displayName"], "Remote backend")
        self.assertEqual(target["secretRefs"]["password"][:12], "file-secret:")
        state_text = launcher_server.DEPLOYMENT_STATE_FILE.read_text(encoding="utf-8")
        secret_text = launcher_server.DEPLOYMENT_SECRET_FILE.read_text(encoding="utf-8")
        self.assertNotIn("super-secret", state_text)
        self.assertIn("super-secret", secret_text)

    def test_deployment_preflight_reports_local_standalone_ready(self) -> None:
        result = self.state.deployment_preflight(
            {
                "target": {
                    "displayName": "This machine",
                    "targetType": "local",
                    "mode": "standalone",
                    "backendPort": 65530,
                }
            }
        )

        self.assertEqual(result["status"], "ok")
        self.assertEqual(result["message"], "preflight ready")

    def test_deployment_job_records_progress_events(self) -> None:
        target = self.state.create_deployment_target(
            {
                "displayName": "This machine",
                "targetType": "local",
                "mode": "standalone",
                "backendPort": 65531,
            }
        )

        job = self.state.create_deployment_job({"targetId": target["id"]})
        deadline = time.time() + 10.0
        while time.time() < deadline:
            job = self.state.get_deployment_job(job["id"])
            if job["stage"] in {"completed", "failed"}:
                break
            time.sleep(0.05)

        self.assertEqual(job["stage"], "completed")
        self.assertGreaterEqual(len(job["events"]), 3)
        sse_events = self.state.deployment_job_events(job["id"])
        self.assertTrue(sse_events[0].startswith("event: progress"))
        settings = self.state.get_settings()
        self.assertTrue(settings["backendDeploymentReady"])
        self.assertEqual(
            settings["selectedBackendDeploymentTarget"]["lastReadiness"],
            "ready",
        )

    def test_all_logs_endpoint_returns_aggregated_lines(self) -> None:
        server = launcher_server.create_server("127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 1.0)

        server.state._append_log("dummy", "stdout line", emit_terminal=False)
        server.state._append_log(
            "dummy", "stderr line", stderr=True, emit_terminal=False
        )
        server.state._suite_api_logs.append("suite stdout")
        server.state._suite_api_logs.append("[stderr] suite stderr")

        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_address[1]}/api/launcher/logs"
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            payload = json.loads(response.read().decode("utf-8"))

        lines = payload["lines"]
        self.assertTrue(any("[suite_api] suite stdout" in line for line in lines))
        self.assertTrue(
            any("[suite_api] [stderr] suite stderr" in line for line in lines)
        )
        self.assertTrue(any("[dummy] stdout line" in line for line in lines))
        self.assertTrue(any("[dummy] [stderr] stderr line" in line for line in lines))

    def test_all_logs_filter_error_only_returns_stderr_lines(self) -> None:
        server = launcher_server.create_server("127.0.0.1", 0)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.shutdown)
        self.addCleanup(server.server_close)
        self.addCleanup(thread.join, 1.0)

        server.state._append_log("dummy", "stdout line", emit_terminal=False)
        server.state._append_log(
            "dummy", "stderr line", stderr=True, emit_terminal=False
        )
        server.state._suite_api_logs.append("suite stdout")
        server.state._suite_api_logs.append("[stderr] suite stderr")

        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_address[1]}/api/launcher/logs?filter=error"
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            payload = json.loads(response.read().decode("utf-8"))

        lines = payload["lines"]
        self.assertTrue(
            any("[suite_api] [stderr] suite stderr" in line for line in lines)
        )
        self.assertTrue(any("[dummy] [stderr] stderr line" in line for line in lines))
        self.assertFalse(any("stdout line" in line for line in lines))

    def test_emit_log_appends_line_without_changing_stage(self) -> None:
        """_emit_log adds a raw output line to job.logs but must NOT touch
        stage/percent/stage_label -- the headline stays the high-level phase
        while live output streams beneath it."""
        from unittest import mock

        from nmtk.launcher_control.deployment_contracts import DeploymentJob
        from nmtk.launcher_control.deployment_service import DeploymentService

        service = DeploymentService(store=mock.Mock(), repo_root=Path("/tmp"))
        job = DeploymentJob(
            id="job-log",
            target_id="t1",
            mode="docker",
            stage="installing",
            percent=52.0,
            stage_label="Building Docker images on remote host",
        )

        service._jobs._emit_log(job, "#5 [build] compiling wheels")

        self.assertEqual(job.stage, "installing")
        self.assertEqual(job.percent, 52.0)
        self.assertEqual(job.stage_label, "Building Docker images on remote host")
        self.assertEqual(job.logs[-1], "#5 [build] compiling wheels")
        self.assertEqual(job.terminal_output[-1], "#5 [build] compiling wheels")
        self.assertEqual(job.last_log_line, "#5 [build] compiling wheels")
        self.assertEqual(job.events[-1]["message"], "#5 [build] compiling wheels")

        service._jobs._emit_log(job, "  indented server output")
        self.assertEqual(job.terminal_output[-1], "  indented server output")

        # Empty/whitespace-only lines are dropped.
        service._jobs._emit_log(job, "   ")
        self.assertEqual(len(job.logs), 2)
        service._jobs._cancel_log_persistence(job.id)

    def test_high_volume_terminal_output_debounces_persistence(self) -> None:
        from unittest import mock

        from nmtk.launcher_control.deployment_contracts import DeploymentJob
        from nmtk.launcher_control.deployment_service import DeploymentService

        store = mock.Mock()
        service = DeploymentService(store=store, repo_root=Path("/tmp"))
        job = DeploymentJob(
            id="job-volume",
            target_id="t1",
            mode="podman",
            stage="installing",
            percent=52.0,
            stage_label="Installing",
        )

        for index in range(1_000):
            service._jobs._emit_log(job, f"server output {index}")

        writes_during_stream = store.save_job.call_count
        self.assertLess(writes_during_stream, 20)
        self.assertEqual(job.terminal_output[-1], "server output 999")

        service._jobs._emit(job, "verifying", "Verifying", 80)

        self.assertEqual(store.save_job.call_count, writes_during_stream + 1)
        self.assertEqual(
            store.save_job.call_args.args[0].terminal_output[-1], "server output 999"
        )

    def test_deployment_job_round_trips_structured_failure_details(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentJob

        job = DeploymentJob(
            id="job-failed",
            target_id="remote-192-168-2-34",
            mode="docker",
            stage="failed",
            error="Podman access failed",
            terminal_output=[
                "$ podman info",
                "✗ podman info failed (exit 125)",
            ],
            requires_ephemeral_administrator=True,
            failure_details={
                "code": "podman_inspection_failed",
                "phase": "reconciling_existing_install",
                "summary": "Podman installations could not be inspected",
                "recovery": "Check Podman access and retry.",
                "technicalDetails": "podman info returned 125",
                "exitCode": 29,
                "existingConnectionReachable": True,
            },
        )

        restored = DeploymentJob.from_json(job.to_json())

        assert restored.failure_details is not None
        self.assertEqual(restored.failure_details["code"], "podman_inspection_failed")
        self.assertTrue(restored.failure_details["existingConnectionReachable"])
        self.assertEqual(
            restored.terminal_output[-1], "✗ podman info failed (exit 125)"
        )
        self.assertTrue(restored.requires_ephemeral_administrator)

    def test_deployment_job_bounds_and_redacts_terminal_output(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentJob

        job = DeploymentJob.from_json(
            {
                "id": "job-terminal",
                "targetId": "remote",
                "mode": "docker",
                "terminalOutput": [
                    *[f"$ check {index}" for index in range(250)],
                    "password=temporary-secret",
                    "NMTK_DEPLOY_PRIVATE_KEY_B64=cHJpdmF0ZQ==",
                ],
            }
        )

        payload = job.to_json()
        self.assertLessEqual(len(payload["terminalOutput"]), 2_000)
        report = "\n".join(payload["terminalOutput"])
        self.assertNotIn("temporary-secret", report)
        self.assertNotIn("cHJpdmF0ZQ==", report)

    def test_deployment_job_marks_truncated_raw_ssh_output(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentJob

        job = DeploymentJob.from_json(
            {
                "id": "job-terminal",
                "targetId": "remote",
                "mode": "docker",
                "terminalOutput": [
                    *[f"server output {index}" for index in range(2_100)],
                    "Authorization: Bearer server-token",
                    "https://operator:password@example.test/path",
                    "\x1b[31mfailed\x1b[0m",
                ],
            }
        )

        report = "\n".join(job.to_json()["terminalOutput"])
        self.assertEqual(
            job.to_json()["terminalOutput"][0],
            "[client: earlier SSH output truncated]",
        )
        self.assertNotIn("server-token", report)
        self.assertNotIn("operator:password", report)
        self.assertNotIn("\x1b", report)
