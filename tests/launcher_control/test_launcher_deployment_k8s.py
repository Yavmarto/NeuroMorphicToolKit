"""Launcher control service tests: Kubernetes deployment (manifest renderer, kubectl executor, preflight)."""

import os
from pathlib import Path
from unittest import mock

from base import LauncherControlServiceTestBase


class TestLauncherDeploymentK8s(LauncherControlServiceTestBase):
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
            image="ghcr.io/yavmarto/neurocnl",
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
        self.assertIn('LOG_LEVEL: "info"', manifests["01-configmap.yaml"])
        self.assertIn('API_KEY: "secret-value"', manifests["02-secret.yaml"])
        self.assertIn(
            "image: ghcr.io/yavmarto/neurocnl:v1.2.3",
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
            assert os.path.exists(path), (
                "expected temp file to exist inside the context"
            )
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

    def test_k8s_rendered_manifests_are_valid_yaml_with_string_data(self) -> None:
        """Regression: the rendered set must parse and use string Config/Secret data.

        A real apiserver rejected the pre-fix output twice over: unquoted numeric
        ``ConfigMap`` values, and the secret ``env`` block emitted a duplicate,
        mis-indented ``env:`` key. Assert the exact properties that failed so the
        breakage is caught without a live cluster.
        """
        import yaml

        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_k8s_renderer import render_manifests

        target = DeploymentTarget(
            id="k8s-yaml",
            display_name="K8s YAML",
            target_type="kubernetes_cluster",
            mode="kubernetes",
            namespace="nmtk-yaml",
            backend_port=9000,
            image_tag="1.0",
        )
        manifests = render_manifests(
            target,
            app_name="nmtk-suite-api",
            image="ghcr.io/yavmarto/neurocnl",
            health_path="/api/suite/health",
            container_port=9000,
            replicas=1,
            env={"LOG_LEVEL": "info"},
            secret_env={"API_KEY": "secret-value"},
        )

        docs = {name: yaml.safe_load(text) for name, text in manifests.items()}
        self.assertEqual(
            {name: doc["kind"] for name, doc in docs.items()},
            {
                "00-namespace.yaml": "Namespace",
                "01-configmap.yaml": "ConfigMap",
                "02-secret.yaml": "Secret",
                "03-deployment.yaml": "Deployment",
                "04-service.yaml": "Service",
            },
        )

        config_data = docs["01-configmap.yaml"]["data"]
        self.assertEqual(config_data["SUITE_API_PORT"], "9000")
        self.assertTrue(all(isinstance(value, str) for value in config_data.values()))

        secret_data = docs["02-secret.yaml"]["stringData"]
        self.assertTrue(all(isinstance(value, str) for value in secret_data.values()))

        containers = docs["03-deployment.yaml"]["spec"]["template"]["spec"][
            "containers"
        ]
        self.assertEqual(len(containers), 1)
        env_entries = {entry["name"]: entry for entry in containers[0]["env"]}
        self.assertEqual(env_entries["PYTHONUNBUFFERED"]["value"], "1")
        self.assertEqual(
            env_entries["API_KEY"]["valueFrom"]["secretKeyRef"]["name"],
            "nmtk-suite-api-secrets",
        )

    def test_k8s_health_check_resolves_target_host_not_api_server(self) -> None:
        """The health probe must target the backend host, never the kube API server."""
        from nmtk.launcher_control.deployment_contracts import DeploymentTarget
        from nmtk.launcher_control.deployment_executors import (
            KubernetesDeploymentExecutor,
        )

        target = DeploymentTarget(
            id="k8s-health",
            display_name="K8s Health",
            target_type="kubernetes_cluster",
            mode="kubernetes",
            namespace="nmtk-test",
            host="backend.example.test",
            backend_port=9000,
            api_server="https://api.example.test:6443",
        )
        executor = KubernetesDeploymentExecutor(repo_root=self.repo_root)
        opened: list[str] = []

        class _Response:
            status = 200

            def __enter__(self):
                return self

            def __exit__(self, *exc: object) -> bool:
                return False

        def _open(url: str, *, timeout: float) -> _Response:
            opened.append(url)
            return _Response()

        with mock.patch.object(executor, "_open_url", side_effect=_open):
            executor._health_check(target)

        self.assertEqual(opened, ["http://backend.example.test:9000/api/suite/health"])
