"""Render Kubernetes manifests from launcher deployment targets and module metadata.

This module produces namespace-scoped YAML that can be piped directly to
``kubectl apply -f``.  No Jinja dependency is required; templates use
:py:class:`string.Template` with a small helper for list rendering.
"""

from __future__ import annotations

import json
import textwrap
from pathlib import Path
from string import Template

from .deployment_contracts import DeploymentTarget


def _indent(text: str, prefix: str = "  ") -> str:
    """Indent every non-empty line of *text* by *prefix*."""
    return "\n".join(
        prefix + line if line.strip() else line for line in text.splitlines()
    )


# ---------------------------------------------------------------------------
# YAML templates
# ---------------------------------------------------------------------------

_NAMESPACE = Template(
    textwrap.dedent(
        """\
        apiVersion: v1
        kind: Namespace
        metadata:
          name: $namespace
        """
    )
)

_CONFIGMAP = Template(
    textwrap.dedent(
        """\
        apiVersion: v1
        kind: ConfigMap
        metadata:
          name: $name
          namespace: $namespace
          labels:
            app.kubernetes.io/name: $app_name
            app.kubernetes.io/component: backend
        data:
        $data
        """
    )
)

_SECRET = Template(
    textwrap.dedent(
        """\
        apiVersion: v1
        kind: Secret
        metadata:
          name: $name
          namespace: $namespace
          labels:
            app.kubernetes.io/name: $app_name
            app.kubernetes.io/component: backend
        type: Opaque
        stringData:
        $data
        """
    )
)

_DEPLOYMENT = Template(
    textwrap.dedent(
        """\
        apiVersion: apps/v1
        kind: Deployment
        metadata:
          name: $name
          namespace: $namespace
          labels:
            app.kubernetes.io/name: $app_name
            app.kubernetes.io/component: backend
        spec:
          replicas: $replicas
          selector:
            matchLabels:
              app.kubernetes.io/name: $app_name
          template:
            metadata:
              labels:
                app.kubernetes.io/name: $app_name
                app.kubernetes.io/component: backend
            spec:
              containers:
                - name: $app_name
                  image: $image
                  imagePullPolicy: $pull_policy
                  ports:
                    - containerPort: $container_port
                      name: http
                  envFrom:
                    - configMapRef:
                        name: $configmap_name
                  env:
                    - name: PYTHONUNBUFFERED
                      value: "1"
        $extra_env
                  resources:
                    requests:
                      memory: "256Mi"
                      cpu: "250m"
                    limits:
                      memory: "1Gi"
                      cpu: "1000m"
                  livenessProbe:
                    httpGet:
                      path: $health_path
                      port: http
                    initialDelaySeconds: 30
                    periodSeconds: 10
                  readinessProbe:
                    httpGet:
                      path: $health_path
                      port: http
                    initialDelaySeconds: 5
                    periodSeconds: 5
              securityContext:
                runAsNonRoot: true
                runAsUser: 1000
                runAsGroup: 1000
                fsGroup: 1000
        """
    )
)

_SERVICE = Template(
    textwrap.dedent(
        """\n        apiVersion: v1
        kind: Service
        metadata:
          name: $name
          namespace: $namespace
          labels:
            app.kubernetes.io/name: $app_name
            app.kubernetes.io/component: backend
        spec:
          selector:
            app.kubernetes.io/name: $app_name
          ports:
            - protocol: TCP
              port: $service_port
              targetPort: $target_port
              name: http
          type: $service_type
        """
    )
)

_INGRESS = Template(
    textwrap.dedent(
        """\
        apiVersion: networking.k8s.io/v1
        kind: Ingress
        metadata:
          name: $name
          namespace: $namespace
          labels:
            app.kubernetes.io/name: $app_name
            app.kubernetes.io/component: backend
        spec:
          rules:
            - host: $domain
              http:
                paths:
                  - path: /
                    pathType: Prefix
                    backend:
                      service:
                        name: $service_name
                        port:
                          number: $service_port
        """
    )
)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _render_env_block(env: dict[str, str], secret_name: str | None = None) -> str:
    """Render an ``env:`` list for a Deployment manifest.

    Plain values are emitted as ``value:`` entries; keys that match
    ``secretFields`` are emitted as ``valueFrom: secretKeyRef`` refs.
    """
    lines: list[str] = []
    for key, value in env.items():
        if secret_name and value == "__SECRET_REF__":
            lines.append(
                f"- name: {key}\n"
                f"  valueFrom:\n"
                f"    secretKeyRef:\n"
                f"      name: {secret_name}\n"
                f"      key: {key}"
            )
        else:
            lines.append(f'- name: {key}\n  value: "{value}"')
    return "\n".join(lines) if lines else ""


def _dict_to_yaml(data: dict[str, str]) -> str:
    """Convert a flat dict into inline YAML key-value pairs.

    Values are rendered as double-quoted YAML scalars. Kubernetes
    ``ConfigMap`` and ``Secret`` data fields must be strings, so an unquoted
    numeric value such as ``9000`` is rejected by the API server; JSON-escaped
    quoting keeps every value a valid string scalar.
    """
    return "\n".join(f"  {k}: {json.dumps(str(v))}" for k, v in data.items())


def _build_image(image: str, tag: str) -> str:
    """Replace or append a tag to a container image reference."""
    if ":" in image.split("/")[-1]:
        # image already contains a tag or digest
        return image
    return f"{image}:{tag}"


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------


def render_manifests(
    target: DeploymentTarget,
    *,
    app_name: str = "nmtk-suite-api",
    image: str = "",
    health_path: str = "/api/suite/health",
    container_port: int = 9000,
    replicas: int = 1,
    env: dict[str, str] | None = None,
    secret_env: dict[str, str] | None = None,
) -> dict[str, str]:
    """Render a complete manifest set for a Kubernetes backend deployment.

    Parameters
    ----------
    target:
        The deployment target (must have ``target_type == "kubernetes_cluster"``
        and ``mode == "kubernetes"``).
    app_name:
        Kubernetes resource app label and container name.
    image:
        Container image to deploy.  If empty, a placeholder is used.
    health_path:
        HTTP path for liveness/readiness probes.
    container_port:
        Port the container listens on.
    replicas:
        Number of pod replicas.
    env:
        Non-sensitive environment variables (placed in a ConfigMap).
    secret_env:
        Sensitive environment variables (placed in a Secret).

    Returns
    -------
    A mapping of ``filename -> yaml_content``.  The filenames are ordered so
    that ``kubectl apply -f`` processes them correctly (namespace first).
    """
    namespace = target.namespace or "nmtk-backend"
    tag = target.image_tag or "latest"
    resolved_image = _build_image(image or "nmtk/suite-api", tag)
    pull_policy = "Always" if tag == "latest" else "IfNotPresent"
    configmap_name = f"{app_name}-env"
    secret_name = f"{app_name}-secrets"

    manifests: dict[str, str] = {}

    # 1. Namespace
    manifests["00-namespace.yaml"] = _NAMESPACE.substitute(namespace=namespace)

    # 2. ConfigMap
    plain_env = dict(env) if env else {}
    plain_env.setdefault("SUITE_API_PORT", str(container_port))
    if plain_env:
        manifests["01-configmap.yaml"] = _CONFIGMAP.substitute(
            name=configmap_name,
            namespace=namespace,
            app_name=app_name,
            data=_indent(_dict_to_yaml(plain_env)),
        )

    # 3. Secret
    secrets = dict(secret_env) if secret_env else {}
    if secrets:
        manifests["02-secret.yaml"] = _SECRET.substitute(
            name=secret_name,
            namespace=namespace,
            app_name=app_name,
            data=_indent(_dict_to_yaml(secrets)),
        )

    # 4. Deployment
    extra_env = ""
    if secrets:
        extra_env = _indent(
            _render_env_block(
                {k: "__SECRET_REF__" for k in secrets}, secret_name=secret_name
            ),
            prefix="            ",
        )

    manifests["03-deployment.yaml"] = _DEPLOYMENT.substitute(
        name=app_name,
        namespace=namespace,
        app_name=app_name,
        replicas=replicas,
        image=resolved_image,
        pull_policy=pull_policy,
        container_port=container_port,
        configmap_name=configmap_name,
        health_path=health_path,
        extra_env=extra_env,
    )

    # 5. Service
    service_type = "ClusterIP" if target.domain else "LoadBalancer"
    manifests["04-service.yaml"] = _SERVICE.substitute(
        name=app_name,
        namespace=namespace,
        app_name=app_name,
        service_port=target.backend_port or container_port,
        target_port="http",
        service_type=service_type,
    )

    # 6. Ingress (optional)
    if target.domain:
        manifests["05-ingress.yaml"] = _INGRESS.substitute(
            name=f"{app_name}-ingress",
            namespace=namespace,
            app_name=app_name,
            domain=target.domain,
            service_name=app_name,
            service_port=target.backend_port or container_port,
        )

    return manifests


def write_manifests(
    manifests: dict[str, str],
    output_dir: Path,
) -> list[Path]:
    """Write a manifest dictionary to *output_dir* and return the file paths.

    Files are written in lexicographic order so ``kubectl apply -f <dir>``
    processes them correctly.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    written: list[Path] = []
    for filename in sorted(manifests):
        path = output_dir / filename
        path.write_text(manifests[filename], encoding="utf-8")
        written.append(path)
    return written
