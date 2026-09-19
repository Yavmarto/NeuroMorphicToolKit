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
        self.assertIn("LOG_LEVEL: info", manifests["01-configmap.yaml"])
        self.assertIn("API_KEY: secret-value", manifests["02-secret.yaml"])
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
