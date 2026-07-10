"""Launcher control service tests: TestLauncherDeployment."""

from pathlib import Path
import io
import json
import nmtk.launcher_control.server as launcher_server
from unittest import mock
import os
import sys
import threading
import time
import urllib.request
from base import LauncherControlServiceTestBase


class TestLauncherDeployment(LauncherControlServiceTestBase):
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
        deadline = time.time() + 3.0
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
        server.state._append_log("dummy", "stderr line", stderr=True, emit_terminal=False)
        server.state._suite_api_logs.append("suite stdout")
        server.state._suite_api_logs.append("[stderr] suite stderr")

        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_address[1]}/api/launcher/logs"
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            payload = json.loads(response.read().decode("utf-8"))

        lines = payload["lines"]
        self.assertTrue(any("[suite_api] suite stdout" in line for line in lines))
        self.assertTrue(any("[suite_api] [stderr] suite stderr" in line for line in lines))
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
        server.state._append_log("dummy", "stderr line", stderr=True, emit_terminal=False)
        server.state._suite_api_logs.append("suite stdout")
        server.state._suite_api_logs.append("[stderr] suite stderr")

        request = urllib.request.Request(
            f"http://127.0.0.1:{server.server_address[1]}/api/launcher/logs?filter=error"
        )
        with urllib.request.urlopen(request, timeout=5) as response:
            payload = json.loads(response.read().decode("utf-8"))

        lines = payload["lines"]
        self.assertTrue(any("[suite_api] [stderr] suite stderr" in line for line in lines))
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
            ["00-namespace.yaml", "01-configmap.yaml", "02-secret.yaml", "03-deployment.yaml", "04-service.yaml"],
        )
        self.assertIn("name: nmtk-test", manifests["00-namespace.yaml"])
        self.assertIn("LOG_LEVEL: info", manifests["01-configmap.yaml"])
        self.assertIn("API_KEY: secret-value", manifests["02-secret.yaml"])
        self.assertIn("image: ghcr.io/completed-spoon-6/neurocnl:v1.2.3", manifests["03-deployment.yaml"])
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
        from nmtk.launcher_control.deployment_executors import KubernetesDeploymentExecutor

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

        with mock.patch("nmtk.launcher_control.deployment_executors.shutil.which") as mock_which, \
             mock.patch("nmtk.launcher_control.deployment_executors.subprocess.run") as mock_run, \
             mock.patch("nmtk.launcher_control.deployment_executors.urllib.request.urlopen") as mock_urlopen:
            mock_which.return_value = "/usr/local/bin/kubectl"
            mock_run.return_value = mock.Mock(returncode=0, stdout="", stderr="")
            mock_urlopen.return_value.__enter__ = mock.Mock(return_value=mock.Mock(status=200))
            mock_urlopen.return_value.__exit__ = mock.Mock(return_value=False)

            executor.run(target, emit)

        self.assertEqual(events[-1][0], "completed")
        self.assertIn("Validating Kubernetes cluster access", [e[1] for e in events])
        self.assertIn("Applying namespace-scoped backend resources", [e[1] for e in events])
        self.assertIn("Waiting for rollout readiness", [e[1] for e in events])
        self.assertIn("Running backend health verification", [e[1] for e in events])

        apply_calls = [c for c in mock_run.call_args_list if "apply" in str(c)]
        rollout_calls = [c for c in mock_run.call_args_list if "rollout" in str(c)]
        self.assertEqual(len(apply_calls), 1)
        self.assertEqual(len(rollout_calls), 1)

    def test_kubectl_env_ctx_cleans_up_kubeconfig_tempfile(self) -> None:
        """The kubeconfig temp file must be deleted after the context manager exits."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import KubernetesDeploymentExecutor
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
            assert os.path.exists(path), "expected temp file to exist inside the context"
            leaked_path.append(path)

        assert leaked_path, "context manager did not yield"
        assert not os.path.exists(leaked_path[0]), (
            f"kubeconfig temp file was NOT deleted after context exit: {leaked_path[0]}"
        )

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
        with mock.patch("nmtk.launcher_control.deployment_preflight.shutil.which") as mock_which:
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
        with mock.patch("nmtk.launcher_control.deployment_preflight.shutil.which") as mock_which, \
             mock.patch("nmtk.launcher_control.deployment_preflight.subprocess.run") as mock_run:
            mock_which.return_value = "/usr/local/bin/kubectl"
            mock_run.side_effect = [
                mock.Mock(returncode=0, stdout="minikube", stderr=""),
                mock.Mock(returncode=0, stdout="Kubernetes control plane", stderr=""),
            ]
            result = run_preflight(target, repo_root=self.repo_root)

        self.assertEqual(result.status, "degraded")
        self.assertTrue(
            any("namespace defaults to current context" in f for f in result.degraded_findings)
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
        assert "echo INJECTED" not in cmd.split("'")[0], (
            f"shell injection not neutralised; raw cmd: {cmd!r}"
        )

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
        assert "'/opt/my deploy dir'" in cmd, (
            f"expected path with spaces to be single-quoted; cmd: {cmd!r}"
        )

    def test_rsync_password_not_in_cmdline(self) -> None:
        """SSH password must travel via SSHPASS env var, not via sshpass -p <plaintext>."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import DockerDeploymentExecutor
        from unittest import mock

        target = DeploymentTarget(
            id="rsync-pwd",
            display_name="Rsync Pwd",
            target_type="remote_host",
            mode="docker",
            host="10.0.0.2",
            auth_mode="ssh_password",
            secret_refs={"sshPassword": "ref:my-secret"},
        )
        executor = DockerDeploymentExecutor(
            repo_root=Path("/tmp"),
            secret_resolver=lambda _ref: "supersecret",
        )

        captured: list[dict] = []

        def fake_run(cmd: list[str], **kwargs: object) -> mock.Mock:
            captured.append({"cmd": cmd, "env": kwargs.get("env", {})})
            return mock.Mock(returncode=0, stdout="", stderr="")

        with mock.patch("nmtk.launcher_control.deployment_executors.subprocess.run", side_effect=fake_run):
            with mock.patch("nmtk.launcher_control.deployment_executors.shutil.which", return_value="/usr/bin/rsync"):
                with mock.patch.object(executor, "_ssh_key_context") as mock_ctx:
                    mock_ctx.return_value.__enter__ = mock.Mock(return_value=None)
                    mock_ctx.return_value.__exit__ = mock.Mock(return_value=False)
                    executor._rsync_to_remote(target, "/opt/nmtk")

        rsync_calls = [c for c in captured if any("--delete" in str(a) for a in c["cmd"])]
        assert rsync_calls, "expected at least one rsync subprocess call"

        rsync_cmd = rsync_calls[0]
        cmd_str = " ".join(rsync_cmd["cmd"])
        env = rsync_cmd["env"]

        assert "supersecret" not in cmd_str, (
            f"plaintext password appeared in rsync command line: {cmd_str!r}"
        )
        assert env.get("SSHPASS") == "supersecret", (
            f"expected SSHPASS env var to carry the password; env keys: {list(env.keys())}"
        )
        assert "sshpass -e" in cmd_str, (
            f"expected 'sshpass -e' in rsync -e arg; got: {cmd_str!r}"
        )
