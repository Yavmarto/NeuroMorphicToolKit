"""Launcher control service tests: TestLauncherDeployment."""

from pathlib import Path
import io
import json
import nmtk.launcher_control.server as launcher_server
from unittest import mock
import os
import subprocess
import sys
import threading
import time
import urllib.request
from base import LauncherControlServiceTestBase

# Captured before any test applies mock.patch("...subprocess.run", ...) --
# `deployment_user_bootstrap.subprocess` is the same module object as this
# top-level `subprocess` import, so patching one patches both; tests that
# need to let ssh-keygen actually run must call through this reference, not
# re-import subprocess (which would just return the already-patched module).
_REAL_SUBPROCESS_RUN = subprocess.run


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

    def test_k8s_manifest_renderer_produces_ordered_files(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_k8s_renderer import render_manifests

        target = DeploymentTarget(
            id="k8s-test",
            display_name="K8s Test",
            target_type="kubernetes_cluster",
            mode="kubernetes",
            namespace="nmtk-test",
            backend_port=9000,
            image_tag="v1.2.3",
        )
        manifests = render_manifests(
            target,
            app_name="nmtk-suite-api",
            image="ghcr.io/completed-spoon-6/neurocnl",
            env={"LOG_LEVEL": "info"},
            secret_env={"API_KEY": "secret-value"},
        )

        self.assertEqual(
            list(manifests.keys()),
            [
                "00-namespace.yaml",
                "01-configmap.yaml",
                "02-secret.yaml",
                "03-deployment.yaml",
                "04-service.yaml",
            ],
        )
        self.assertIn("name: nmtk-test", manifests["00-namespace.yaml"])
        self.assertIn("LOG_LEVEL: info", manifests["01-configmap.yaml"])
        self.assertIn("API_KEY: secret-value", manifests["02-secret.yaml"])
        self.assertIn(
            "image: ghcr.io/completed-spoon-6/neurocnl:v1.2.3",
            manifests["03-deployment.yaml"],
        )
        self.assertIn("imagePullPolicy: IfNotPresent", manifests["03-deployment.yaml"])
        self.assertIn("type: LoadBalancer", manifests["04-service.yaml"])

    def test_k8s_manifest_renderer_includes_ingress_when_domain_set(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_k8s_renderer import render_manifests

        target = DeploymentTarget(
            id="k8s-test",
            display_name="K8s Test",
            target_type="kubernetes_cluster",
            mode="kubernetes",
            namespace="nmtk-test",
            domain="nmtk.example.com",
            backend_port=9000,
        )
        manifests = render_manifests(target, app_name="nmtk-suite-api")
        self.assertIn("05-ingress.yaml", manifests)
        self.assertIn("host: nmtk.example.com", manifests["05-ingress.yaml"])
        self.assertIn("type: ClusterIP", manifests["04-service.yaml"])

    def test_k8s_executor_runs_kubectl_commands(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import (
            KubernetesDeploymentExecutor,
        )

        target = DeploymentTarget(
            id="k8s-exec",
            display_name="K8s Exec",
            target_type="kubernetes_cluster",
            mode="kubernetes",
            namespace="nmtk-test",
            backend_port=9000,
        )
        executor = KubernetesDeploymentExecutor(repo_root=self.repo_root)
        events: list[tuple[str, str, float]] = []

        def emit(stage: str, message: str, percent: float) -> None:
            events.append((stage, message, percent))

        with (
            mock.patch(
                "nmtk.launcher_control.deployment_executors.shutil.which"
            ) as mock_which,
            mock.patch(
                "nmtk.launcher_control.deployment_executors.subprocess.run"
            ) as mock_run,
            mock.patch(
                "nmtk.launcher_control.deployment_executors.urllib.request.urlopen"
            ) as mock_urlopen,
        ):
            mock_which.return_value = "/usr/local/bin/kubectl"
            mock_run.return_value = mock.Mock(returncode=0, stdout="", stderr="")
            mock_urlopen.return_value.__enter__ = mock.Mock(
                return_value=mock.Mock(status=200)
            )
            mock_urlopen.return_value.__exit__ = mock.Mock(return_value=False)

            executor.run(target, emit)

        self.assertEqual(events[-1][0], "completed")
        self.assertIn("Validating Kubernetes cluster access", [e[1] for e in events])
        self.assertIn(
            "Applying namespace-scoped backend resources", [e[1] for e in events]
        )
        self.assertIn("Waiting for rollout readiness", [e[1] for e in events])
        self.assertIn("Running backend health verification", [e[1] for e in events])

        apply_calls = [c for c in mock_run.call_args_list if "apply" in str(c)]
        rollout_calls = [c for c in mock_run.call_args_list if "rollout" in str(c)]
        self.assertEqual(len(apply_calls), 1)
        self.assertEqual(len(rollout_calls), 1)

    def test_kubectl_env_ctx_cleans_up_kubeconfig_tempfile(self) -> None:
        """The kubeconfig temp file must be deleted after the context manager exits."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import (
            KubernetesDeploymentExecutor,
        )
        from pathlib import Path

        target = DeploymentTarget(
            id="k8s-cleanup",
            display_name="K8s Cleanup",
            target_type="kubernetes_cluster",
            mode="kubernetes",
            auth_mode="kubeconfig",
            secret_refs={"kubeconfig": "ref:my-kubeconfig"},
        )
        executor = KubernetesDeploymentExecutor(
            repo_root=Path("/tmp"),
            secret_resolver=lambda _ref: "apiVersion: v1\nclusters: []\n",
        )

        leaked_path: list[str] = []

        with executor._kubectl_env_ctx(target) as env:
            path = env.get("KUBECONFIG", "")
            assert path, "expected KUBECONFIG to be set inside the context"
            assert os.path.exists(
                path
            ), "expected temp file to exist inside the context"
            leaked_path.append(path)

        assert leaked_path, "context manager did not yield"
        assert not os.path.exists(
            leaked_path[0]
        ), f"kubeconfig temp file was NOT deleted after context exit: {leaked_path[0]}"

    def test_k8s_preflight_blocks_without_kubectl(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_preflight import run_preflight

        target = DeploymentTarget(
            id="k8s-pf",
            display_name="K8s PF",
            target_type="kubernetes_cluster",
            mode="kubernetes",
            namespace="nmtk-test",
        )
        with mock.patch(
            "nmtk.launcher_control.deployment_preflight.shutil.which"
        ) as mock_which:
            mock_which.return_value = None
            result = run_preflight(target, repo_root=self.repo_root)

        self.assertEqual(result.status, "failed")
        self.assertIn("kubectl is not installed", result.message)

    def test_k8s_preflight_degrades_missing_namespace(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_preflight import run_preflight

        target = DeploymentTarget(
            id="k8s-pf",
            display_name="K8s PF",
            target_type="kubernetes_cluster",
            mode="kubernetes",
        )
        with (
            mock.patch(
                "nmtk.launcher_control.deployment_preflight.shutil.which"
            ) as mock_which,
            mock.patch(
                "nmtk.launcher_control.deployment_preflight.subprocess.run"
            ) as mock_run,
        ):
            mock_which.return_value = "/usr/local/bin/kubectl"
            mock_run.side_effect = [
                mock.Mock(returncode=0, stdout="minikube", stderr=""),
                mock.Mock(returncode=0, stdout="Kubernetes control plane", stderr=""),
            ]
            result = run_preflight(target, repo_root=self.repo_root)

        self.assertEqual(result.status, "degraded")
        self.assertTrue(
            any(
                "namespace defaults to current context" in f
                for f in result.degraded_findings
            )
        )

    def test_init_remote_secrets_quotes_deploy_dir(self) -> None:
        """deploy_dir with shell metacharacters must not be passed raw to the SSH command."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="remote-inject",
            display_name="Remote Inject",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.1",
            auth_mode="none",
            install_root="/opt/nmtk; echo INJECTED",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        captured_cmds: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured_cmds.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._init_remote_secrets(target, "/opt/nmtk; echo INJECTED")

        assert captured_cmds, "expected _ssh_run to be called"
        cmd = captured_cmds[0]
        # shlex.quote wraps the path in single quotes, neutralising the injection
        assert (
            "echo INJECTED" not in cmd.split("'")[0]
        ), f"shell injection not neutralised; raw cmd: {cmd!r}"

    def test_init_remote_secrets_clean_path(self) -> None:
        """A clean deploy_dir produces a valid shell command without altering the path."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="remote-clean",
            display_name="Remote Clean",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.1",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        captured_cmds: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured_cmds.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._init_remote_secrets(target, "/opt/nmtk")

        assert captured_cmds, "expected _ssh_run to be called"
        cmd = captured_cmds[0]
        assert "/opt/nmtk" in cmd, f"deploy_dir not found in cmd: {cmd!r}"
        assert "GRAFANA_ADMIN_PASSWORD" in cmd, f"secret setup not in cmd: {cmd!r}"

    def test_init_remote_secrets_path_with_spaces(self) -> None:
        """A deploy_dir containing spaces must be quoted so the shell treats it as one token."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="remote-spaces",
            display_name="Remote Spaces",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.1",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        captured_cmds: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured_cmds.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._init_remote_secrets(target, "/opt/my deploy dir")

        assert captured_cmds, "expected _ssh_run to be called"
        cmd = captured_cmds[0]
        assert (
            "'/opt/my deploy dir'" in cmd
        ), f"expected path with spaces to be single-quoted; cmd: {cmd!r}"

    @staticmethod
    def _fake_rsync_popen(returncode: int = 0, output_lines: "list[str] | None" = None):
        """Build a fake Popen double for the streaming _ssh_run reader loop.

        `proc.stdout` is a real io.StringIO so the reader thread's
        `iter(proc.stdout.readline, "")` behaves exactly like a real pipe
        that's already fully written and closed -- it drains immediately.
        """
        proc = mock.Mock()
        proc.stdout = io.StringIO("".join(f"{line}\n" for line in (output_lines or [])))
        proc.poll.return_value = returncode
        proc.wait.return_value = returncode
        return proc

    def test_ssh_run_streams_output_to_log_channel(self) -> None:
        """docker compose pull/up output must stream line-by-line to the
        log channel (self._log), not be discarded like the old blocking
        subprocess.run did on success."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="ssh-stream",
            display_name="Ssh Stream",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.9",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        collected: list[str] = []
        executor._log = collected.append

        def fake_popen(cmd: list[str], **kwargs: object) -> mock.Mock:
            return self._fake_rsync_popen(
                output_lines=["#1 building", "#2 exporting", "#3 done"]
            )

        with mock.patch(
            "nmtk.launcher_control.deployment_executors.subprocess.Popen",
            side_effect=fake_popen,
        ):
            with mock.patch.object(executor, "_ssh_key_context") as mock_ctx:
                mock_ctx.return_value.__enter__ = mock.Mock(return_value=None)
                mock_ctx.return_value.__exit__ = mock.Mock(return_value=False)
                executor._ssh_run(target, "docker compose build")

        assert collected, "expected _ssh_run to forward output to the log channel"
        assert collected[0] == "$ docker compose build", collected
        # The final line is always flushed so the last step stays visible.
        assert collected[-1] == "#3 done", collected
        assert set(collected[1:]).issubset({"#1 building", "#2 exporting", "#3 done"})

    def test_ssh_run_failure_raises_with_output_tail(self) -> None:
        """A non-zero remote command must raise with a tail of its output."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="ssh-fail",
            display_name="Ssh Fail",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.10",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        def fake_popen(cmd: list[str], **kwargs: object) -> mock.Mock:
            return self._fake_rsync_popen(
                returncode=1, output_lines=["step ok", "ERROR: build failed"]
            )

        with mock.patch(
            "nmtk.launcher_control.deployment_executors.subprocess.Popen",
            side_effect=fake_popen,
        ):
            with mock.patch.object(executor, "_ssh_key_context") as mock_ctx:
                mock_ctx.return_value.__enter__ = mock.Mock(return_value=None)
                mock_ctx.return_value.__exit__ = mock.Mock(return_value=False)
                with self.assertRaises(RuntimeError) as ctx:
                    executor._ssh_run(target, "docker compose build")

        assert "build failed" in str(ctx.exception), str(ctx.exception)

    def test_remote_compose_cmd_uses_prod_files_and_env(self) -> None:
        """The remote docker compose command must select both compose files
        and set the env the prod stack needs (mirrors `make deploy-prod`)."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="compose-cmd",
            display_name="Compose Cmd",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
        )
        cmd = executor._remote_compose_cmd("/home/nmtk/nmtk-deploy", target, "pull")

        assert (
            "-f docker-compose.yml -f docker-compose.prod.yml "
            "-f docker-compose.remote.yml"
        ) in cmd, cmd
        assert "pull" in cmd, cmd
        assert "LAUNCHER_CONTROL_PORT=8090" in cmd, cmd
        assert "JUPYTER_PUBLIC_URL=" in cmd and "192.168.2.34:8008/lab" in cmd, cmd
        assert "nmtk-deploy" in cmd, cmd
        # No source build anywhere in the source-free flow.
        assert "build" not in cmd, cmd
        # Docker path activates the docker group via `sg` for a just-added membership.
        assert "sg docker" in cmd, cmd

    def test_remote_compose_cmd_uses_selected_image_tag(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="compose-tag",
            display_name="Compose Tag",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
            image_tag="v2026.07.24",
        )

        cmd = executor._remote_compose_cmd("/home/nmtk/nmtk-deploy", target, "pull")

        assert "NMTK_IMAGE_TAG=v2026.07.24" in cmd, cmd
        assert executor._image_tag(target) == "v2026.07.24"
        target.image_tag = "bad tag; rm -rf /"
        assert executor._image_tag(target) == "latest"

    def test_compose_contract_does_not_gate_suite_api_on_lava_health(self) -> None:
        compose = (
            Path(__file__).resolve().parents[2] / "docker-compose.yml"
        ).read_text(encoding="utf-8")
        suite_block = compose.split("  neurosense-hw-worker:", 1)[0]
        assert "condition: service_started" in suite_block
        assert "required: false" in suite_block
        assert "condition: service_healthy" not in suite_block
        # The hardware worker starts independently; Lava failures are reported
        # by its runtime routes instead of blocking the core stack.
        neurochip_block = compose.split("  neurochip-hw-worker:", 1)[1].split(
            "\n  lava-backend:", 1
        )[0]
        assert "condition: service_started" in neurochip_block
        assert "required: false" in neurochip_block
        assert "condition: service_healthy" not in neurochip_block

    def test_remote_provider_preflight_checks_engine_and_merged_config(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="provider-pf",
            display_name="Provider PF",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
            container_engine="podman",
        )
        commands: list[str] = []

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: commands.append(command),
        ):
            executor._remote_provider_preflight(target, "/home/nmtk/nmtk-deploy")

        assert len(commands) == 2
        assert "podman info" in commands[0], commands
        assert "podman compose version" in commands[0], commands
        assert "config --quiet" in commands[1], commands

    def test_legacy_compose_project_uses_deploy_directory_basename(self) -> None:
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        assert (
            DockerDeploymentExecutor._legacy_compose_project("/home/nmtk/nmtk-deploy")
            == "nmtk-deploy"
        )
        assert DockerDeploymentExecutor._legacy_compose_project("/home/nmtk/nmtk") == ""

    def test_stale_cleanup_is_label_scoped_across_runtimes(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="cleanup-labels",
            display_name="Cleanup Labels",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
            container_engine="podman",
        )
        commands: list[str] = []

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: commands.append(command),
        ):
            executor._remote_cleanup_stale_projects(target, "/home/nmtk/nmtk-deploy")

        assert len(commands) == 1
        command = commands[0]
        assert "for runtime in podman docker" in command
        assert "com.docker.compose.project=$project" in command
        assert "io.podman.compose.project=$project" in command
        assert "nmtk-deploy" in command
        assert "{{.ID}} {{.Names}}" in command
        assert "jupyter-server" in command
        assert "fuser" not in command
        assert "volume" not in command

    def test_factory_reset_cleanup_removes_only_labelled_volumes(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="cleanup-volumes",
            display_name="Cleanup Volumes",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
        )
        commands: list[str] = []

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: commands.append(command),
        ):
            executor._remote_cleanup_stale_projects(
                target,
                "/home/nmtk/nmtk-deploy",
                remove_volumes=True,
            )

        command = commands[0]
        assert "volume ls -q --filter" in command
        assert "volume rm -f" in command
        assert "volume prune" not in command

    def test_port_owner_probe_reports_client_ports_and_compose_labels(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="port-owner",
            display_name="Port Owner",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
        )
        commands: list[str] = []

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: commands.append(command),
        ):
            executor._remote_port_owner_probe(target)

        assert len(commands) == 1
        command = commands[0]
        assert "for port in 9000 8090 8008" in command
        assert "com.docker.compose.project" in command
        assert "io.podman.compose.project" in command
        assert "ss -ltnp" in command

    def test_startup_diagnostics_include_compose_state_and_lava_logs(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="diagnostics",
            display_name="Diagnostics",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
            container_engine="podman",
        )
        commands: list[str] = []
        logs: list[str] = []
        executor._log = logs.append

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: commands.append(command),
        ):
            executor._collect_remote_startup_diagnostics(
                target, "/home/nmtk/nmtk-deploy"
            )

        assert any(" ps -a" in command for command in commands), commands
        assert any(
            "logs --tail=100 lava-backend" in command for command in commands
        ), commands
        assert any("inspect --format" in command for command in commands), commands
        assert any("probe_status" in command for command in commands), commands
        assert any("config --format json" in command for command in commands), commands
        assert any("health diagnostics" in line for line in logs), logs

    def test_readiness_diagnostics_include_suite_api_logs_and_direct_probe(
        self,
    ) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="readiness-diagnostics",
            display_name="Readiness Diagnostics",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
            backend_port=9010,
            container_engine="podman",
        )
        commands: list[str] = []
        logs: list[str] = []
        executor._log = logs.append

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: commands.append(command),
        ):
            executor._collect_remote_readiness_diagnostics(
                target, "/home/nmtk/nmtk-deploy"
            )

        assert any("logs --tail=200 suite_api" in command for command in commands)
        probe_command = commands[-1]
        assert "127.0.0.1:9010/api/suite/health" in probe_command
        assert "host listener tcp/9010" in probe_command
        assert "inspect --format" in probe_command
        assert any("[nmtk-suite-api]" in line for line in logs)

    def test_remote_readiness_timeout_collects_diagnostics_before_raising(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="readiness-timeout",
            display_name="Readiness Timeout",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        diagnostics = mock.Mock()

        with (
            mock.patch.object(
                executor,
                "_resolve_remote_deploy_dir",
                return_value="/home/nmtk/nmtk-deploy",
            ),
            mock.patch.object(executor, "_ensure_engine_installed"),
            mock.patch.object(executor, "_prepare_podman_runtime"),
            mock.patch.object(executor, "_copy_manifests_to_remote"),
            mock.patch.object(executor, "_init_remote_secrets"),
            mock.patch.object(executor, "_remote_provider_preflight"),
            mock.patch.object(executor, "_remote_port_owner_probe"),
            mock.patch.object(executor, "_remote_cleanup_stale_projects"),
            mock.patch.object(executor, "_ssh_run"),
            mock.patch.object(
                executor,
                "_health_check",
                side_effect=RuntimeError(
                    "Backend health check timed out at http://192.168.2.34:9000/api/suite/health: timed out"
                ),
            ),
            mock.patch.object(
                executor,
                "_collect_remote_readiness_diagnostics",
                diagnostics,
            ),
        ):
            with self.assertRaises(RuntimeError) as context:
                executor._deploy_remote(target, lambda *_args: None)

        diagnostics.assert_called_once_with(target, "/home/nmtk/nmtk-deploy")
        assert "readiness diagnostics were collected" in str(context.exception)

    def test_remote_jupyter_failure_collects_diagnostics_and_blocks_ready(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="jupyter-timeout",
            display_name="Jupyter Timeout",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        diagnostics = mock.Mock()

        with (
            mock.patch.object(
                executor,
                "_resolve_remote_deploy_dir",
                return_value="/home/nmtk/nmtk-deploy",
            ),
            mock.patch.object(executor, "_ensure_engine_installed"),
            mock.patch.object(executor, "_prepare_podman_runtime"),
            mock.patch.object(executor, "_copy_manifests_to_remote"),
            mock.patch.object(executor, "_init_remote_secrets"),
            mock.patch.object(executor, "_remote_provider_preflight"),
            mock.patch.object(executor, "_remote_port_owner_probe"),
            mock.patch.object(executor, "_remote_cleanup_stale_projects"),
            mock.patch.object(executor, "_ssh_run"),
            mock.patch.object(executor, "_health_check"),
            mock.patch.object(
                executor,
                "_jupyter_health_check",
                side_effect=RuntimeError("Jupyter readiness timed out"),
            ),
            mock.patch.object(
                executor, "_collect_remote_jupyter_diagnostics", diagnostics
            ),
        ):
            with self.assertRaises(RuntimeError) as context:
                executor._deploy_remote(target, lambda *_args: None)

        diagnostics.assert_called_once_with(target, "/home/nmtk/nmtk-deploy")
        assert "degraded optional capability: Jupyter" in str(context.exception)

    def test_jupyter_readiness_checks_internal_and_public_endpoints(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        target = DeploymentTarget(
            id="jupyter-ready",
            display_name="Jupyter Ready",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        class Response:
            status = 200

            def read(self) -> bytes:
                return b'{"status":"ok","module":"jupyter"}'

            def __enter__(self):
                return self

            def __exit__(self, *_args) -> None:
                return None

        with mock.patch(
            "nmtk.launcher_control.deployment_executors.urllib.request.urlopen",
            side_effect=[Response(), Response()],
        ) as urlopen:
            executor._jupyter_health_check(target)

        calls = [str(call.args[0]) for call in urlopen.call_args_list]
        assert calls == [
            "http://192.168.2.34:9000/api/jupyter/health",
            "http://192.168.2.34:8008/api/status",
        ]

    def test_remote_compose_cmd_podman_skips_docker_group_dance(self) -> None:
        """Podman is rootless by design: no `sg docker`/group-membership wrapper."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        target = DeploymentTarget(
            id="compose-cmd-podman",
            display_name="Compose Cmd Podman",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
            container_engine="podman",
        )
        cmd = executor._remote_compose_cmd("/home/nmtk/nmtk-deploy", target, "pull")

        assert cmd.startswith("cd "), cmd
        assert (
            "podman compose --project-name nmtk -f docker-compose.yml "
            "-f docker-compose.prod.yml "
            "-f docker-compose.remote.yml pull" in cmd
        ), cmd
        assert "DOCKER_HOST=unix:///run/user/$(id -u)/podman/podman.sock" in cmd, cmd
        assert "sg docker" not in cmd, cmd
        assert "getent group docker" not in cmd, cmd

    def test_prepare_podman_runtime_configures_rootless_socket(self) -> None:
        from nmtk.launcher_control.deployment_contracts import (
            DeploymentTarget,
            podman_runtime_setup_script,
        )
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="podman-runtime",
            display_name="Podman Runtime",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
            auth_mode="ssh_password",
            secret_refs={"sshPassword": "ref:my-secret"},
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(
            repo_root=Path("/tmp"),
            secret_resolver=lambda _ref: "supersecret",
        )
        captured: list[str] = []

        with mock.patch.object(
            executor,
            "_ssh_run",
            side_effect=lambda _target, command, timeout=600: captured.append(command),
        ):
            executor._prepare_podman_runtime(target)

        assert len(captured) == 1
        assert captured[0].startswith(
            "env NMTK_DEPLOY_SUDO_PASSWORD=supersecret bash -c "
        )
        setup_script = podman_runtime_setup_script()
        assert "systemctl --user enable --now podman.socket" in setup_script
        assert "XDG_RUNTIME_DIR" in setup_script
        assert "DOCKER_HOST" in setup_script
        assert "Podman socket was not created" in setup_script

    def test_deploy_remote_prepares_podman_before_manifests(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="podman-order",
            display_name="Podman Order",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        calls: list[str] = []

        def emit(_stage: str, _message: str, _percent: float) -> None:
            pass

        with (
            mock.patch.object(
                executor,
                "_resolve_remote_deploy_dir",
                return_value="/home/nmtk/nmtk-deploy",
            ),
            mock.patch.object(
                executor,
                "_ensure_engine_installed",
                side_effect=lambda _target: calls.append("install"),
            ),
            mock.patch.object(
                executor,
                "_prepare_podman_runtime",
                side_effect=lambda _target: calls.append("podman-runtime"),
            ),
            mock.patch.object(
                executor,
                "_copy_manifests_to_remote",
                side_effect=lambda _target, _directory: calls.append("manifests"),
            ),
            mock.patch.object(
                executor,
                "_init_remote_secrets",
                side_effect=lambda _target, _directory: calls.append("secrets"),
            ),
            mock.patch.object(
                executor,
                "_ssh_run",
                side_effect=lambda *_args, **_kwargs: calls.append("compose"),
            ),
            mock.patch.object(
                executor,
                "_health_check",
                side_effect=lambda _target, host: calls.append("health"),
            ),
            mock.patch.object(
                executor,
                "_jupyter_health_check",
                side_effect=lambda _target: calls.append("jupyter-health"),
            ),
        ):
            executor._deploy_remote(target, emit)

        assert calls.index("install") < calls.index("podman-runtime"), calls
        assert calls.index("podman-runtime") < calls.index("manifests"), calls
        assert calls.count("compose") == 8, calls

    def test_remote_deploy_cleans_project_before_pull_and_up(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="cleanup-order",
            display_name="Cleanup Order",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        commands: list[str] = []

        with (
            mock.patch.object(
                executor,
                "_resolve_remote_deploy_dir",
                return_value="/home/nmtk/nmtk-deploy",
            ),
            mock.patch.object(executor, "_ensure_engine_installed"),
            mock.patch.object(executor, "_prepare_podman_runtime"),
            mock.patch.object(executor, "_copy_manifests_to_remote"),
            mock.patch.object(executor, "_init_remote_secrets"),
            mock.patch.object(
                executor,
                "_ssh_run",
                side_effect=lambda _target, command, timeout=600: commands.append(
                    command
                ),
            ),
            mock.patch.object(executor, "_health_check"),
            mock.patch.object(executor, "_jupyter_health_check"),
        ):
            executor._deploy_remote(target, lambda *_args: None)

        assert len(commands) == 8, commands
        assert "--project-name nmtk" in commands[1], commands
        assert all(
            "--project-name nmtk" in command for command in commands[4:7]
        ), commands
        assert "down --remove-orphans" in commands[4], commands
        assert " pull" in commands[5], commands
        assert "up -d --remove-orphans" in commands[6], commands
        assert (
            "Lava is optional" in commands[7] or "inspect --format" in commands[7]
        ), commands

    def test_remote_deploy_blocks_when_stale_stack_cleanup_fails(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="cleanup-failure",
            display_name="Cleanup Failure",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        with (
            mock.patch.object(
                executor,
                "_resolve_remote_deploy_dir",
                return_value="/home/nmtk/nmtk-deploy",
            ),
            mock.patch.object(executor, "_ensure_engine_installed"),
            mock.patch.object(executor, "_prepare_podman_runtime"),
            mock.patch.object(executor, "_copy_manifests_to_remote"),
            mock.patch.object(executor, "_init_remote_secrets"),
            mock.patch.object(
                executor,
                "_ssh_run",
                side_effect=[
                    None,
                    None,
                    None,
                    RuntimeError("old compose project is already gone"),
                ],
            ),
            mock.patch.object(executor, "_health_check"),
            mock.patch.object(executor, "_jupyter_health_check"),
        ):
            with self.assertRaises(RuntimeError) as context:
                executor._deploy_remote(target, lambda *_args: None)

        assert "could not be reconciled safely" in str(context.exception)

    def test_remote_port_conflict_error_names_port_and_safe_recovery(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="port-conflict",
            display_name="Port Conflict",
            target_type="remote_host",
            mode="docker",
            host="192.168.2.34",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        conflict = RuntimeError(
            "Remote command failed: rootlessport listen tcp 0.0.0.0:8012: "
            "bind: address already in use"
        )

        with (
            mock.patch.object(
                executor,
                "_resolve_remote_deploy_dir",
                return_value="/home/nmtk/nmtk-deploy",
            ),
            mock.patch.object(executor, "_ensure_engine_installed"),
            mock.patch.object(executor, "_prepare_podman_runtime"),
            mock.patch.object(executor, "_copy_manifests_to_remote"),
            mock.patch.object(executor, "_init_remote_secrets"),
            mock.patch.object(executor, "_remote_port_owner_probe"),
            mock.patch.object(executor, "_collect_remote_startup_diagnostics"),
            mock.patch.object(
                executor,
                "_ssh_run",
                side_effect=[None, None, None, None, None, conflict],
            ),
        ):
            with self.assertRaises(RuntimeError) as context:
                executor._deploy_remote(target, lambda *_args: None)

        message = str(context.exception)
        assert "host port 8012" in message, message
        assert "unrelated service" in message, message
        assert "fuser" not in message, message

    def test_copy_manifests_password_not_in_cmdline(self) -> None:
        """The manifest copy must ship only the compose files + monitoring/,
        and carry the SSH password via SSHPASS env, never in argv."""
        import tempfile
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "docker-compose.yml").write_text("services: {}\n")
            (root / "docker-compose.prod.yml").write_text("services: {}\n")
            (root / "docker-compose.remote.yml").write_text("services: {}\n")
            (root / "monitoring").mkdir()

            target = DeploymentTarget(
                id="copy-pwd",
                display_name="Copy Pwd",
                target_type="remote_host",
                mode="docker",
                host="10.0.0.2",
                auth_mode="ssh_password",
                secret_refs={"sshPassword": "ref:my-secret"},
            )
            executor = DockerDeploymentExecutor(
                repo_root=root,
                secret_resolver=lambda _ref: "supersecret",
            )

            calls: list[dict] = []

            def fake_run(cmd: list[str], **kwargs: object) -> mock.Mock:
                calls.append({"cmd": cmd, "env": kwargs.get("env", {})})
                return mock.Mock(returncode=0, stdout="", stderr="")

            with mock.patch(
                "nmtk.launcher_control.deployment_executors.subprocess.run",
                side_effect=fake_run,
            ):
                with mock.patch.object(executor, "_ssh_key_context") as mock_ctx:
                    mock_ctx.return_value.__enter__ = mock.Mock(return_value=None)
                    mock_ctx.return_value.__exit__ = mock.Mock(return_value=False)
                    executor._copy_manifests_to_remote(target, "/home/nmtk/nmtk-deploy")

        assert calls, "expected rsync to be invoked"
        cmd_str = " ".join(calls[0]["cmd"])
        env = calls[0]["env"]
        assert "supersecret" not in cmd_str, cmd_str
        assert env.get("SSHPASS") == "supersecret", list(env.keys())
        assert "sshpass -e" in cmd_str, cmd_str
        assert (
            "docker-compose.yml" in cmd_str
            and "docker-compose.prod.yml" in cmd_str
            and "docker-compose.remote.yml" in cmd_str
        ), cmd_str
        assert "monitoring" in cmd_str, cmd_str

    def test_copy_manifests_missing_raises_actionable_error(self) -> None:
        """If the compose files aren't present (bundle didn't ship them),
        the error must say so rather than silently copying nothing."""
        import tempfile
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor

        with tempfile.TemporaryDirectory() as tmp:
            target = DeploymentTarget(
                id="copy-missing",
                display_name="Copy Missing",
                target_type="remote_host",
                mode="docker",
                host="10.0.0.2",
                auth_mode="none",
            )
            executor = DockerDeploymentExecutor(repo_root=Path(tmp))
            with self.assertRaises(RuntimeError) as ctx:
                executor._copy_manifests_to_remote(target, "/home/nmtk/nmtk-deploy")

        assert "manifests not found" in str(ctx.exception).lower(), str(ctx.exception)

    def test_emit_log_appends_line_without_changing_stage(self) -> None:
        """_emit_log adds a raw output line to job.logs but must NOT touch
        stage/percent/stage_label -- the headline stays the high-level phase
        while live output streams beneath it."""
        from nmtk.launcher_control.deployment_contracts import DeploymentJob
        from nmtk.launcher_control.deployment_service import DeploymentService
        from unittest import mock

        service = DeploymentService(store=mock.Mock(), repo_root=Path("/tmp"))
        job = DeploymentJob(
            id="job-log",
            target_id="t1",
            mode="docker",
            stage="installing",
            percent=52.0,
            stage_label="Building Docker images on remote host",
        )

        service._emit_log(job, "#5 [build] compiling wheels")

        self.assertEqual(job.stage, "installing")
        self.assertEqual(job.percent, 52.0)
        self.assertEqual(job.stage_label, "Building Docker images on remote host")
        self.assertEqual(job.logs[-1], "#5 [build] compiling wheels")
        self.assertEqual(job.terminal_output[-1], "#5 [build] compiling wheels")
        self.assertEqual(job.last_log_line, "#5 [build] compiling wheels")
        self.assertEqual(job.events[-1]["message"], "#5 [build] compiling wheels")

        service._emit_log(job, "  indented server output")
        self.assertEqual(job.terminal_output[-1], "  indented server output")

        # Empty/whitespace-only lines are dropped.
        service._emit_log(job, "   ")
        self.assertEqual(len(job.logs), 2)
        service._cancel_log_persistence(job.id)

    def test_high_volume_terminal_output_debounces_persistence(self) -> None:
        from nmtk.launcher_control.deployment_contracts import DeploymentJob
        from nmtk.launcher_control.deployment_service import DeploymentService
        from unittest import mock

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
            service._emit_log(job, f"server output {index}")

        writes_during_stream = store.save_job.call_count
        self.assertLess(writes_during_stream, 20)
        self.assertEqual(job.terminal_output[-1], "server output 999")

        service._emit(job, "verifying", "Verifying", 80)

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

    def test_resolve_remote_deploy_dir_uses_configured_install_root(self) -> None:
        """An explicitly configured install_root is used as-is, not overridden."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="remote-configured",
            display_name="Remote Configured",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.3",
            auth_mode="none",
            install_root="/srv/nmtk",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        captured: list[list[str]] = []

        def fake_run(cmd: list[str], **kwargs: object) -> mock.Mock:
            captured.append(cmd)
            return mock.Mock(returncode=0, stdout="/srv/nmtk\n", stderr="")

        with mock.patch(
            "nmtk.launcher_control.deployment_executors.subprocess.run",
            side_effect=fake_run,
        ):
            resolved = executor._resolve_remote_deploy_dir(target)

        assert resolved == "/srv/nmtk"
        assert captured, "expected subprocess.run to be called"
        remote_cmd = captured[0][-1]
        assert "/srv/nmtk" in remote_cmd
        assert "mkdir -p" in remote_cmd and "pwd" in remote_cmd

    def test_resolve_remote_deploy_dir_defaults_to_home_directory(self) -> None:
        """With no install_root set, falls back to ~/nmtk-deploy, not a root-owned system path."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="remote-default",
            display_name="Remote Default",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.4",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        captured: list[list[str]] = []

        def fake_run(cmd: list[str], **kwargs: object) -> mock.Mock:
            captured.append(cmd)
            return mock.Mock(
                returncode=0, stdout="/home/deploy/nmtk-deploy\n", stderr=""
            )

        with mock.patch(
            "nmtk.launcher_control.deployment_executors.subprocess.run",
            side_effect=fake_run,
        ):
            resolved = executor._resolve_remote_deploy_dir(target)

        assert resolved == "/home/deploy/nmtk-deploy"
        remote_cmd = captured[0][-1]
        assert "~/nmtk-deploy" in remote_cmd
        assert "/opt/nmtk" not in remote_cmd

    def test_resolve_remote_deploy_dir_raises_friendly_error_on_permission_denied(
        self,
    ) -> None:
        """A permission-denied mkdir failure surfaces an actionable message, not raw stderr."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="remote-denied",
            display_name="Remote Denied",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.5",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        def fake_run(cmd: list[str], **kwargs: object) -> mock.Mock:
            return mock.Mock(
                returncode=1,
                stdout="",
                stderr="mkdir: cannot create directory 'nmtk-deploy': Permission denied",
            )

        with mock.patch(
            "nmtk.launcher_control.deployment_executors.subprocess.run",
            side_effect=fake_run,
        ):
            with self.assertRaises(RuntimeError) as excinfo:
                executor._resolve_remote_deploy_dir(target)

        message = str(excinfo.exception)
        assert "Permission denied" in message
        assert "home directory" in message

    def test_resolve_remote_deploy_dir_configured_permission_denied_mentions_install_root(
        self,
    ) -> None:
        """When a configured install_root is rejected, the error names it explicitly."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="remote-configured-denied",
            display_name="Remote Configured Denied",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.6",
            auth_mode="none",
            install_root="/opt/nmtk",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        def fake_run(cmd: list[str], **kwargs: object) -> mock.Mock:
            return mock.Mock(
                returncode=1,
                stdout="",
                stderr="mkdir: cannot create directory '/opt/nmtk': Permission denied",
            )

        with mock.patch(
            "nmtk.launcher_control.deployment_executors.subprocess.run",
            side_effect=fake_run,
        ):
            with self.assertRaises(RuntimeError) as excinfo:
                executor._resolve_remote_deploy_dir(target)

        message = str(excinfo.exception)
        assert "/opt/nmtk" in message
        assert "not writable" in message

    @staticmethod
    def _decode_engine_install_script(remote_cmd: str) -> str:
        """Decode the base64 payload from the generated remote command."""
        import base64

        echo_part = remote_cmd.split("echo ", 1)[1]
        encoded = echo_part.split(" | base64", 1)[0]
        return base64.b64decode(encoded).decode()

    def test_ensure_engine_installed_docker_checks_presence_before_sudo(self) -> None:
        """The `command -v docker` presence guard must run before the sudo
        gate, so an already-provisioned host never needs sudo access."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="engine-install-docker",
            display_name="Engine Install Docker",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.20",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        captured: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._ensure_engine_installed(target)

        assert captured, "expected _ssh_run to be called"
        script = self._decode_engine_install_script(captured[0])
        presence_idx = script.index("command -v docker")
        sudo_idx = script.index("sudo_available")
        assert presence_idx < sudo_idx, script
        assert "exit 0" in script
        assert "get.docker.com" in script

    def test_ensure_engine_installed_podman_uses_apt(self) -> None:
        """Podman installs via apt + podman-compose, never the Docker install path."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="engine-install-podman",
            display_name="Engine Install Podman",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.21",
            auth_mode="none",
            container_engine="podman",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        captured: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._ensure_engine_installed(target)

        script = self._decode_engine_install_script(captured[0])
        assert "command -v podman" in script
        assert "apt-get install -y -qq podman podman-compose" in script
        assert "get.docker.com" not in script

    def test_ensure_engine_installed_password_auth_sets_sudo_password(self) -> None:
        """Password-auth targets reuse the SSH login password as the sudo
        password, mirroring `_ensure_docker_permissions`."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="engine-install-pw",
            display_name="Engine Install Pw",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.22",
            auth_mode="ssh_password",
            secret_refs={"sshPassword": "ref:my-secret"},
        )
        executor = DockerDeploymentExecutor(
            repo_root=Path("/tmp"), secret_resolver=lambda _ref: "supersecret"
        )
        captured: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._ensure_engine_installed(target)

        assert captured[0].startswith(
            "env NMTK_DEPLOY_SUDO_PASSWORD=supersecret bash -c "
        )

    def test_ensure_engine_installed_key_auth_no_sudo_password_prefix(self) -> None:
        """Key-auth targets carry no password, so no sudo-password prefix is
        added -- elevation relies on passwordless sudo (or the host already
        having the engine installed, per the presence guard)."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="engine-install-key",
            display_name="Engine Install Key",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.23",
            auth_mode="ssh_key",
            secret_refs={"sshPrivateKey": "ref:my-key"},
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        captured: list[str] = []

        def fake_ssh_run(tgt: object, remote_cmd: str, timeout: int = 600) -> None:
            captured.append(remote_cmd)

        with mock.patch.object(executor, "_ssh_run", side_effect=fake_ssh_run):
            executor._ensure_engine_installed(target)

        assert "NMTK_DEPLOY_SUDO_PASSWORD" not in captured[0]
        assert captured[0].startswith("echo ")

    def test_deploy_remote_runs_engine_install_before_permissions_and_manifests(
        self,
    ) -> None:
        """`_ensure_engine_installed` must run before both the docker-only
        permission fix-up and copying manifests, for every remote deploy."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="engine-order",
            display_name="Engine Order",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.24",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))
        call_order: list[str] = []

        def emit(stage: str, message: str, percent: float) -> None:
            pass

        with (
            mock.patch.object(
                executor,
                "_resolve_remote_deploy_dir",
                return_value="/home/nmtk/nmtk-deploy",
            ),
            mock.patch.object(
                executor,
                "_ensure_engine_installed",
                side_effect=lambda t: call_order.append("install"),
            ),
            mock.patch.object(
                executor,
                "_ensure_docker_permissions",
                side_effect=lambda t: call_order.append("permissions"),
            ),
            mock.patch.object(
                executor,
                "_copy_manifests_to_remote",
                side_effect=lambda t, d: call_order.append("manifests"),
            ),
            mock.patch.object(
                executor,
                "_init_remote_secrets",
                side_effect=lambda t, d: call_order.append("secrets"),
            ),
            mock.patch.object(
                executor,
                "_ssh_run",
                side_effect=lambda *a, **k: call_order.append("ssh_run"),
            ),
            mock.patch.object(
                executor,
                "_health_check",
                side_effect=lambda t, host: call_order.append("health"),
            ),
            mock.patch.object(
                executor,
                "_jupyter_health_check",
                side_effect=lambda t: call_order.append("jupyter-health"),
            ),
        ):
            executor._deploy_remote(target, emit)

        assert call_order.index("install") < call_order.index("permissions"), call_order
        assert call_order.index("permissions") < call_order.index(
            "manifests"
        ), call_order

    def test_deploy_remote_aborts_before_manifests_when_engine_install_fails(
        self,
    ) -> None:
        """If install isn't possible (no sudo / no apt-get), the raised error
        must stop the deploy before any compose command runs."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="engine-install-fail",
            display_name="Engine Install Fail",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.25",
            auth_mode="none",
        )
        executor = DockerDeploymentExecutor(repo_root=Path("/tmp"))

        def emit(stage: str, message: str, percent: float) -> None:
            pass

        with (
            mock.patch.object(
                executor,
                "_resolve_remote_deploy_dir",
                return_value="/home/nmtk/nmtk-deploy",
            ),
            mock.patch.object(
                executor,
                "_ensure_engine_installed",
                side_effect=RuntimeError(
                    "Remote command failed: apt-get not found; automatic Podman "
                    "install only supports Debian/Ubuntu"
                ),
            ),
            mock.patch.object(executor, "_copy_manifests_to_remote") as mock_copy,
        ):
            with self.assertRaises(RuntimeError) as ctx:
                executor._deploy_remote(target, emit)

        assert "apt-get not found" in str(ctx.exception)
        mock_copy.assert_not_called()


class TestDeploymentUserBootstrap(LauncherControlServiceTestBase):
    """One-time root SSH bootstrap: nmtk/launcher_control/deployment_user_bootstrap.py.

    Real `ssh-keygen` is allowed to run (fast, local, no network) so these
    tests exercise the real key-generation path; only the SSH call itself is
    faked, since that's the one that would otherwise need a real remote host.
    """

    def _fake_ssh_success(self, captured: list[list[str]]):
        from unittest import mock

        def fake_run(cmd: list[str], **kwargs: object):
            if cmd[0] == "ssh-keygen":
                return _REAL_SUBPROCESS_RUN(cmd, **kwargs)
            captured.append(cmd)
            return mock.Mock(
                returncode=0,
                stdout="[nmtk-bootstrap] creating user 'nmtk'\n[nmtk-bootstrap] done\n",
                stderr="",
            )

        return fake_run

    @staticmethod
    def _decode_remote_script(remote_cmd: str) -> str:
        """Decode the base64 payload from the generated remote command."""
        import base64

        echo_part = remote_cmd.split("echo ", 1)[1]
        encoded = echo_part.split(" | base64", 1)[0]
        return base64.b64decode(encoded).decode()

    def test_ssh_root_bootstrap_script_contains_expected_steps(self) -> None:
        """The remote command must create the user, add it to docker, and install the key
        via sudo (not assuming the SSH login itself is literally root)."""
        from unittest import mock
        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        captured: list[list[str]] = []
        with mock.patch(
            "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
            side_effect=self._fake_ssh_success(captured),
        ):
            result = ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="root",
                root_password="totally-secret-root-pw",
            )

        assert result["username"] == "nmtk"
        assert "BEGIN OPENSSH PRIVATE KEY" in result["sshPrivateKey"]
        assert captured, "expected an ssh subprocess call"

        remote_cmd = captured[0][-1]
        script = self._decode_remote_script(remote_cmd)
        assert "sudo_cmd useradd --create-home --shell /bin/bash" in script
        assert "sudo_cmd usermod -aG docker" in script
        assert "authorized_keys" in script
        assert "sudo_cmd install -m 600" in script
        assert "sudo_available" in script

    def test_ssh_root_bootstrap_login_password_via_sshpass_not_argv(self) -> None:
        """The SSH *login* password must still travel via SSHPASS env var, never as an
        ssh argv item -- only the (separate, already-accepted) sudo-password prefix on
        the remote command is expected to carry it, covered by the next test."""
        from unittest import mock
        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        captured: list[dict] = []

        def fake_run(cmd, **kwargs):
            if cmd[0] == "ssh-keygen":
                return _REAL_SUBPROCESS_RUN(cmd, **kwargs)
            captured.append({"cmd": cmd, "env": kwargs.get("env", {})})
            return mock.Mock(returncode=0, stdout="[nmtk-bootstrap] done\n", stderr="")

        with mock.patch(
            "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
            side_effect=fake_run,
        ):
            with mock.patch(
                "nmtk.launcher_control.deployment_executors.shutil.which",
                return_value="/usr/bin/sshpass",
            ):
                ssh_root_bootstrap(
                    host="10.0.0.9",
                    root_username="root",
                    root_password="totally-secret-root-pw",
                )

        assert captured, "expected an ssh subprocess call"
        cmd = captured[0]["cmd"]
        # The password must not appear as its own ssh/sshpass argv token (e.g. a `-p`
        # style argument); it's only allowed to appear inside the trailing remote
        # command string, where it's the deliberate sudo-password prefix.
        assert "totally-secret-root-pw" not in cmd[:-1]
        assert captured[0]["env"].get("SSHPASS") == "totally-secret-root-pw"

    def test_ssh_root_bootstrap_sudo_password_reaches_decoder_environment(
        self,
    ) -> None:
        """The sudo password must be attached to the decoder Bash process."""
        from unittest import mock
        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        captured: list[list[str]] = []
        with mock.patch(
            "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
            side_effect=self._fake_ssh_success(captured),
        ):
            ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="root",
                root_password="totally-secret-root-pw",
            )

        remote_cmd = captured[0][-1]
        assert remote_cmd.startswith(
            "env NMTK_DEPLOY_SUDO_PASSWORD=totally-secret-root-pw bash -c "
        )

    def test_encode_remote_script_passes_environment_to_decoded_bash(self) -> None:
        from nmtk.launcher_control.deployment_contracts import encode_remote_script

        remote_cmd = encode_remote_script(
            'printf "%s" "$NMTK_DEPLOY_SUDO_PASSWORD"',
            env={"NMTK_DEPLOY_SUDO_PASSWORD": "correct horse battery staple"},
        )
        result = _REAL_SUBPROCESS_RUN(
            ["bash", "-c", remote_cmd],
            capture_output=True,
            text=True,
            check=False,
        )

        assert result.returncode == 0, result.stderr
        assert result.stdout == "correct horse battery staple"

    def test_ssh_root_bootstrap_no_sudo_password_prefix_for_key_auth(self) -> None:
        """SSH-key auth carries no password at all, so no sudo-password prefix is added --
        elevation for a key-authenticated non-root account relies on passwordless sudo."""
        from unittest import mock
        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        captured: list[list[str]] = []
        with mock.patch(
            "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
            side_effect=self._fake_ssh_success(captured),
        ):
            ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="root",
                root_private_key="-----BEGIN FAKE KEY-----\nabc\n-----END FAKE KEY-----\n",
            )

        remote_cmd = captured[0][-1]
        assert "NMTK_DEPLOY_SUDO_PASSWORD" not in remote_cmd
        assert remote_cmd.startswith("echo ")

    def test_ssh_root_bootstrap_sudo_unavailable_surfaces_actionable_error(
        self,
    ) -> None:
        """If sudo elevation isn't possible at all, the script's own check fails fast with
        a clear, actionable message rather than a cryptic permission-denied string."""
        from unittest import mock
        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        def fake_run(cmd, **kwargs):
            if cmd[0] == "ssh-keygen":
                return _REAL_SUBPROCESS_RUN(cmd, **kwargs)
            return mock.Mock(
                returncode=1,
                stdout="[nmtk-bootstrap] ERROR: this account cannot run privileged commands"
                " (no root session, no passwordless/NOPASSWD sudo, and no sudo password"
                " available). Use a password-based login for an admin account, true root"
                " credentials, or configure NOPASSWD sudo for this account.\n",
                stderr="",
            )

        with mock.patch(
            "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
            side_effect=fake_run,
        ):
            with self.assertRaises(RuntimeError) as excinfo:
                ssh_root_bootstrap(
                    host="10.0.0.9",
                    root_username="mooseryzen",
                    root_password="not-actually-sudo-capable",
                )

        message = str(excinfo.exception)
        assert "cannot run privileged commands" in message
        assert "not-actually-sudo-capable" not in message

    def test_ssh_root_bootstrap_key_file_cleaned_up(self) -> None:
        """The root private key temp file must be 0600 during use and removed after."""
        import os
        import stat
        from unittest import mock
        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        observed_key_paths: list[str] = []

        def fake_run(cmd, **kwargs):
            if cmd[0] == "ssh-keygen":
                return _REAL_SUBPROCESS_RUN(cmd, **kwargs)
            if "-i" in cmd:
                key_path = cmd[cmd.index("-i") + 1]
                observed_key_paths.append(key_path)
                mode = stat.S_IMODE(os.stat(key_path).st_mode)
                assert mode == 0o600, f"expected key file mode 0600, got {oct(mode)}"
            return mock.Mock(returncode=0, stdout="[nmtk-bootstrap] done\n", stderr="")

        with mock.patch(
            "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
            side_effect=fake_run,
        ):
            ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="root",
                root_private_key="-----BEGIN FAKE KEY-----\nabc\n-----END FAKE KEY-----\n",
            )

        assert observed_key_paths, "expected the root key to be written to a temp file"
        assert not os.path.exists(
            observed_key_paths[0]
        ), "root key temp file must be deleted after use"

    def test_ssh_root_bootstrap_requires_exactly_one_credential(self) -> None:
        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        with self.assertRaises(ValueError):
            ssh_root_bootstrap(host="10.0.0.9", root_username="root")

        with self.assertRaises(ValueError):
            ssh_root_bootstrap(
                host="10.0.0.9",
                root_username="root",
                root_password="a",
                root_private_key="b",
            )

    def test_ssh_root_bootstrap_failure_does_not_leak_password(self) -> None:
        from unittest import mock
        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        def fake_run(cmd, **kwargs):
            if cmd[0] == "ssh-keygen":
                return _REAL_SUBPROCESS_RUN(cmd, **kwargs)
            return mock.Mock(
                returncode=1,
                stdout="",
                stderr="Permission denied (publickey,password).",
            )

        with mock.patch(
            "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
            side_effect=fake_run,
        ):
            with self.assertRaises(RuntimeError) as excinfo:
                ssh_root_bootstrap(
                    host="10.0.0.9",
                    root_username="root",
                    root_password="totally-secret-root-pw",
                )

        message = str(excinfo.exception)
        assert "Permission denied" in message
        assert "totally-secret-root-pw" not in message

    def test_ssh_root_bootstrap_never_touches_secret_store(self) -> None:
        """The bootstrap path must never write through FileBackedSecretStore/DeploymentStore."""
        from unittest import mock
        from nmtk.launcher_control.deployment_store import FileBackedSecretStore
        from nmtk.launcher_control.deployment_user_bootstrap import ssh_root_bootstrap

        captured: list[list[str]] = []
        with mock.patch(
            "nmtk.launcher_control.deployment_user_bootstrap.subprocess.run",
            side_effect=self._fake_ssh_success(captured),
        ):
            with mock.patch.object(
                FileBackedSecretStore,
                "put",
                side_effect=AssertionError("must not persist root creds"),
            ):
                result = ssh_root_bootstrap(
                    host="10.0.0.9",
                    root_username="root",
                    root_password="totally-secret-root-pw",
                )

        assert result["username"] == "nmtk"
