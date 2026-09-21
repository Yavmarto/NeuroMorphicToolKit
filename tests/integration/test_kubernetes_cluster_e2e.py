"""Real Kubernetes integration test for the launcher Kubernetes deployment executor.

This suite closes the gap called out in the CEL-382 roadmap Section 3 table:

    Kubernetes -> a real integration test against a cluster (none exists today
    - that's the actual gap, not the executor code).

The unit tests in ``tests/launcher_control/test_launcher_deployment_k8s.py``
mock ``subprocess.run`` and ``urllib.request``. They prove the executor builds
the right command sequence, but they cannot catch a manifest that a real API
server rejects, a rollout that never becomes ready, or a service wiring mistake.
This suite exercises the real executor against a real cluster:

1. ``test_rendered_manifests_pass_server_side_validation`` renders the product
   manifest set with the real renderer and asks a live API server to validate it
   (``kubectl apply --dry-run=server``). This runs without pulling any image.
2. ``test_kubernetes_executor_deploys_and_reports_healthy`` runs the real
   ``KubernetesDeploymentExecutor.run`` end to end: preflight -> render -> apply
   -> rollout status -> health probe. The workload image is a tiny stub
   (``hashicorp/http-echo``) so the suite stays fast and offline-friendly; every
   line of executor logic under test is real.

=== Opt-in ===

Set ``K8S_INTEGRATION_TEST=true`` to activate this suite, mirroring the
``AKIDA_HARDWARE_TEST`` / ``PYNQ_HARDWARE_TEST`` convention. The suite skips when
the flag is absent so ordinary CI (no cluster) is not disrupted.

A reachable cluster is required when the flag is set. Point ``kubectl`` at it
with the normal ``KUBECONFIG`` / ``--context`` mechanism, or let this suite
provision a throwaway ``kind`` cluster by also setting
``K8S_KIND_PROVISION=true`` (requires Docker and the ``kind`` binary).

Environment overrides:

- ``K8S_INTEGRATION_TEST``   opt in (``true``/``1``/``yes``)
- ``K8S_KIND_PROVISION``     create and delete a temporary kind cluster
- ``K8S_KIND_CLUSTER``       kind cluster name (default ``nmtk-k8s-it``)
- ``K8S_KUBECTL_CONTEXT``    kubectl context to target (optional)
- ``K8S_TEST_IMAGE``         stub workload image (default ``hashicorp/http-echo:1.0``)
- ``K8S_TEST_IMAGE_PORT``    stub container port (default ``5678``)
"""

from __future__ import annotations

import os
import shutil
import socket
import subprocess
import threading
import time
import uuid
from pathlib import Path

import pytest

pytestmark = pytest.mark.kubernetes

REPO_ROOT = Path(__file__).resolve().parents[2]

_OPT_IN = os.getenv("K8S_INTEGRATION_TEST", "").lower() in {"1", "true", "yes"}
_KIND_PROVISION = os.getenv("K8S_KIND_PROVISION", "").lower() in {"1", "true", "yes"}
_KIND_CLUSTER = os.getenv("K8S_KIND_CLUSTER", "nmtk-k8s-it")
_KUBECTL_CONTEXT = os.getenv("K8S_KUBECTL_CONTEXT", "").strip()
_TEST_IMAGE = os.getenv("K8S_TEST_IMAGE", "hashicorp/http-echo:1.0").strip()
_TEST_IMAGE_PORT = int(os.getenv("K8S_TEST_IMAGE_PORT", "5678"))
_APP_NAME = "nmtk-suite-api"


def _kubectl_path() -> str | None:
    return shutil.which("kubectl")


def _kubectl_base(context: str = "") -> list[str]:
    kubectl = _kubectl_path()
    if kubectl is None:
        raise RuntimeError("kubectl is not installed")
    cmd = [kubectl]
    if context:
        cmd.extend(["--context", context])
    return cmd


def _run(
    argv: list[str],
    *,
    timeout: float = 60.0,
    check: bool = False,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        argv,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=check,
        env=env,
    )


def _cluster_reachable(context: str = "") -> tuple[bool, str]:
    kubectl = _kubectl_path()
    if kubectl is None:
        return False, "kubectl is not installed"
    try:
        result = _run(_kubectl_base(context) + ["cluster-info"], timeout=20)
    except (OSError, subprocess.TimeoutExpired) as exc:  # pragma: no cover - env
        return False, f"kubectl cluster-info failed: {exc}"
    if result.returncode != 0:
        return False, (
            result.stderr.strip()
            or result.stdout.strip()
            or "kubectl cannot reach a cluster"
        )
    return True, result.stdout.strip()


def _free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def _tcp_open(host: str, port: int, timeout: float = 0.5) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def _wait_for_port_forward_ready(
    proc: subprocess.Popen[str], port: int, seconds: float = 20.0
) -> None:
    """Poll a kubectl port-forward process until its local listener accepts."""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if proc.poll() is not None:
            raise RuntimeError(
                f"kubectl port-forward exited early (rc={proc.returncode})"
            )
        if _tcp_open("127.0.0.1", port):
            return
        time.sleep(0.25)
    raise RuntimeError("kubectl port-forward did not open its local listener")


@pytest.fixture(scope="module", autouse=True)
def _provisioned_cluster() -> object:
    """Provision a throwaway kind cluster for the module when requested.

    Deletion always runs so a failed test cannot leak a cluster.
    """
    if not _OPT_IN:
        yield None
        return
    if not _KIND_PROVISION:
        yield None
        return
    kind = shutil.which("kind")
    if kind is None:
        pytest.fail("K8S_KIND_PROVISION=true but the 'kind' binary is not installed")
    if shutil.which("docker") is None:
        pytest.fail("K8S_KIND_PROVISION=true but docker is not installed")

    existing = _run([kind, "get", "clusters"], timeout=30)
    created = _KIND_CLUSTER not in existing.stdout.split()
    if created:
        result = _run(
            [kind, "create", "cluster", "--name", _KIND_CLUSTER, "--wait", "120s"],
            timeout=300,
        )
        if result.returncode != 0:
            pytest.fail(f"kind create cluster failed: {result.stderr.strip()}")
        context = f"kind-{_KIND_CLUSTER}"
        os.environ.setdefault("K8S_KUBECTL_CONTEXT", context)
    try:
        yield _KIND_CLUSTER
    finally:
        if created:
            _run([kind, "delete", "cluster", "--name", _KIND_CLUSTER], timeout=180)


@pytest.fixture()
def kubectl_context() -> str:
    return os.getenv("K8S_KUBECTL_CONTEXT", "").strip()


@pytest.fixture()
def live_cluster(kubectl_context: str) -> str:
    if not _OPT_IN:
        pytest.skip(
            "Kubernetes integration test is opt-in; set K8S_INTEGRATION_TEST=true "
            "and point kubectl at a reachable cluster"
        )
    reachable, detail = _cluster_reachable(kubectl_context)
    if not reachable:
        pytest.fail("K8S_INTEGRATION_TEST=true but no reachable cluster: " + detail)
    return kubectl_context


@pytest.fixture()
def namespace(live_cluster: str) -> str:
    """Create a unique namespace for one test and delete it afterwards."""
    ns = f"nmtk-k8s-it-{uuid.uuid4().hex[:8]}"
    result = _run(_kubectl_base(live_cluster) + ["create", "namespace", ns], timeout=30)
    if result.returncode != 0:
        pytest.fail(f"failed to create namespace {ns}: {result.stderr.strip()}")
    try:
        yield ns
    finally:
        _run(
            _kubectl_base(live_cluster) + ["delete", "namespace", ns, "--wait=false"],
            timeout=120,
        )


def _render_product_manifests(namespace: str) -> dict[str, str]:
    from nmtk.launcher_control.deployment_contracts import DeploymentTarget
    from nmtk.launcher_control.deployment_k8s_renderer import render_manifests

    target = DeploymentTarget(
        id="k8s-it-render",
        display_name="K8s IT Render",
        target_type="kubernetes_cluster",
        mode="kubernetes",
        namespace=namespace,
        backend_port=9000,
        image_tag="1.0",
    )
    return render_manifests(
        target,
        app_name=_APP_NAME,
        image="ghcr.io/yavmarto/neurocnl",
        health_path="/api/suite/health",
        container_port=9000,
        replicas=1,
        env={"LOG_LEVEL": "info"},
        secret_env={"API_KEY": "integration-secret"},
    )


def test_rendered_manifests_pass_server_side_validation(
    live_cluster: str, namespace: str, tmp_path: Path
) -> None:
    """The real API server must admit the rendered product manifest set.

    ``--dry-run=server`` sends every manifest through the live apiserver's
    schema, defaulting, and admission pipeline without persisting objects. This
    catches manifest bugs that mocked tests cannot.
    """
    from nmtk.launcher_control.deployment_k8s_renderer import write_manifests

    manifests = _render_product_manifests(namespace)
    manifest_dir = tmp_path / "manifests"
    write_manifests(manifests, manifest_dir)

    for filename in sorted(manifests):
        path = manifest_dir / filename
        result = _run(
            _kubectl_base(live_cluster)
            + ["--namespace", namespace, "apply", "--dry-run=server", "-f", str(path)],
            timeout=60,
        )
        assert result.returncode == 0, (
            f"apiserver rejected {filename}:\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )


def test_kubernetes_executor_deploys_and_reports_healthy(
    live_cluster: str, namespace: str, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Drive the real executor: preflight -> apply -> rollout -> health probe."""
    from nmtk.launcher_control import deployment_executor_kubernetes as k8s_module
    from nmtk.launcher_control.deployment_contracts import DeploymentTarget
    from nmtk.launcher_control.deployment_executors import (
        KubernetesDeploymentExecutor,
    )

    real_render = k8s_module.render_manifests

    def _render_with_stub_workload(target, **kwargs):  # type: ignore[no-untyped-def]
        # Keep every executor/manifest decision real, but swap the heavy product
        # image for a stub that answers 200 on every path so the readiness/liveness
        # probes and the executor health check resolve quickly.
        kwargs["image"] = _TEST_IMAGE.rsplit(":", 1)[0]
        kwargs["container_port"] = _TEST_IMAGE_PORT
        return real_render(target, **kwargs)

    monkeypatch.setattr(k8s_module, "render_manifests", _render_with_stub_workload)

    service_port = _free_port()
    target = DeploymentTarget(
        id="k8s-it-exec",
        display_name="K8s IT Exec",
        target_type="kubernetes_cluster",
        mode="kubernetes",
        namespace=namespace,
        backend_port=service_port,
        image_tag=_TEST_IMAGE.rsplit(":", 1)[-1],
        host="127.0.0.1",
        context=live_cluster,
    )

    executor = KubernetesDeploymentExecutor(repo_root=REPO_ROOT)
    events: list[tuple[str, str, float]] = []
    run_error: list[BaseException] = []

    def _emit(stage: str, message: str, percent: float) -> None:
        events.append((stage, message, percent))

    def _run_executor() -> None:
        try:
            executor.run(target, _emit)
        except BaseException as exc:  # noqa: BLE001 - surfacing in main thread
            run_error.append(exc)

    worker = threading.Thread(target=_run_executor, name="k8s-executor", daemon=True)
    worker.start()

    forward: subprocess.Popen[str] | None = None
    try:
        forward = _start_service_port_forward(
            live_cluster, namespace, service_port, deadline_seconds=240
        )
        worker.join(timeout=420)
        assert not worker.is_alive(), (
            "KubernetesDeploymentExecutor.run did not finish within 420s"
        )
        if run_error:
            raise run_error[0]

        assert events[-1][0] == "completed"
        stages = [stage for stage, _message, _percent in events]
        assert "preflight_running" in stages
        assert "installing" in stages
        assert "verifying" in stages

        deployment = _run(
            _kubectl_base(live_cluster)
            + [
                "--namespace",
                namespace,
                "get",
                "deployment",
                _APP_NAME,
                "-o",
                "jsonpath={.status.availableReplicas}",
            ],
            timeout=30,
        )
        assert deployment.returncode == 0, deployment.stderr
        assert deployment.stdout.strip() == "1", (
            f"expected 1 available replica, got {deployment.stdout!r}"
        )

        service = _run(
            _kubectl_base(live_cluster)
            + ["--namespace", namespace, "get", "service", _APP_NAME],
            timeout=30,
        )
        assert service.returncode == 0, service.stderr
    finally:
        if forward is not None and forward.poll() is None:
            forward.terminate()
            try:
                forward.wait(timeout=10)
            except subprocess.TimeoutExpired:  # pragma: no cover - best effort
                forward.kill()


def _start_service_port_forward(
    context: str,
    namespace: str,
    port: int,
    *,
    deadline_seconds: float,
) -> subprocess.Popen[str]:
    """Wait for the deployed Service to have endpoints, then port-forward it.

    A LoadBalancer Service in a local cluster (kind/minikube without a cloud
    provider) never receives an external IP, so the executor health probe is
    pointed at 127.0.0.1 through ``kubectl port-forward``. The forward is started
    while the executor is still waiting for rollout; the executor's own health
    check retries for 120s, so a small startup delay is tolerated.
    """
    deadline = time.monotonic() + deadline_seconds
    last_detail = "service not found yet"
    while time.monotonic() < deadline:
        endpoints = _run(
            _kubectl_base(context)
            + [
                "--namespace",
                namespace,
                "get",
                "endpoints",
                _APP_NAME,
                "-o",
                "jsonpath={.subsets[*].addresses[*].ip}",
            ],
            timeout=15,
        )
        if endpoints.returncode == 0 and endpoints.stdout.strip():
            break
        last_detail = endpoints.stderr.strip() or last_detail
        time.sleep(1.0)
    else:
        raise RuntimeError(
            f"service {_APP_NAME} never gained ready endpoints: {last_detail}"
        )

    proc = subprocess.Popen(
        _kubectl_base(context)
        + [
            "--namespace",
            namespace,
            "port-forward",
            f"service/{_APP_NAME}",
            f"{port}:{port}",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    _wait_for_port_forward_ready(proc, port)
    return proc
