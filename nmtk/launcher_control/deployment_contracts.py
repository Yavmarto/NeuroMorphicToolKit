"""Typed contracts for launcher-owned backend deployment setup."""

from __future__ import annotations

import base64
import json
import re
import shlex
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

DEPLOYMENT_TARGET_TYPES = {"local", "remote_host", "kubernetes_cluster"}
DEPLOYMENT_MODES = {"standalone", "docker", "kubernetes"}
DEPLOYMENT_CONTAINER_ENGINES = {"docker", "podman"}
DEPLOYMENT_AUTH_MODES = {
    "none",
    "ssh_key",
    "ssh_password",
    "username_password",
    "kubeconfig",
    "bearer_token",
}
DEPLOYMENT_JOB_STAGES = {
    "queued",
    "preflight_running",
    "awaiting_confirmation",
    "installing",
    "verifying",
    "completed",
    "failed",
    "cancelled",
}
TERMINAL_JOB_STAGES = {"completed", "failed", "cancelled"}
SECRET_FIELD_NAMES = {
    "password",
    "sshPassword",
    "sshPrivateKey",
    "privateKey",
    "bearerToken",
    "token",
    "kubeconfig",
}


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def slugify(value: str, *, fallback: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9_.-]+", "-", value.strip()).strip("-._")
    return slug or fallback


def redact_text(value: str) -> str:
    redacted = value
    for pattern in (
        r"(?i)(password=)([^\s]+)",
        r"(?i)(token=)([^\s]+)",
        r"(?i)(bearer\s+)([A-Za-z0-9._~-]+)",
        r"(?i)(api[-_]?key=)([^\s]+)",
    ):
        redacted = re.sub(pattern, r"\1<redacted>", redacted)
    redacted = re.sub(
        r"-----BEGIN (?:OPENSSH |RSA |EC )?PRIVATE KEY-----[\s\S]*?"
        r"-----END (?:OPENSSH |RSA |EC )?PRIVATE KEY-----",
        "<redacted private key>",
        redacted,
    )
    redacted = re.sub(
        r"NMTK_DEPLOY_PRIVATE_KEY_B64=[A-Za-z0-9+/=]+",
        "NMTK_DEPLOY_PRIVATE_KEY_B64=<redacted>",
        redacted,
    )
    redacted = re.sub(
        r"(?i)(authorization:\s*(?:bearer|basic)\s+)([^\s]+)",
        r"\1<redacted>",
        redacted,
    )
    redacted = re.sub(
        r"(?i)([a-z][a-z0-9+.-]*://)([^/\s:@]+):([^@\s/]+)@",
        r"\1<redacted>@",
        redacted,
    )
    redacted = re.sub(r"\x1b\[[0-?]*[ -/]*[@-~]", "", redacted)
    redacted = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]", "", redacted)
    return redacted


def bounded_terminal_output(lines: list[str]) -> list[str]:
    max_lines = 2_000
    max_characters = 512_000
    truncation_marker = "[client: earlier SSH output truncated]"
    already_truncated = any(str(line) == truncation_marker for line in lines)
    sanitized = [
        redact_text(str(line)) for line in lines if str(line) != truncation_marker
    ]
    truncated = already_truncated or len(sanitized) > max_lines
    bounded = sanitized[-max_lines:]
    while bounded and sum(len(line) + 1 for line in bounded) > max_characters:
        bounded.pop(0)
        truncated = True
    if truncated:
        while len(bounded) >= max_lines:
            bounded.pop(0)
        while (
            bounded
            and sum(len(line) + 1 for line in bounded) + len(truncation_marker) + 1
            > max_characters
        ):
            bounded.pop(0)
        bounded.insert(0, truncation_marker)
    return bounded


def redact_payload(payload: Any) -> Any:
    if isinstance(payload, dict):
        return {
            key: "<redacted>" if key in SECRET_FIELD_NAMES else redact_payload(value)
            for key, value in payload.items()
        }
    if isinstance(payload, list):
        return [redact_payload(item) for item in payload]
    if isinstance(payload, str):
        return redact_text(payload)
    return payload


def encode_remote_script(
    script: str,
    *,
    env: dict[str, str] | None = None,
) -> str:
    """Encode `script` as a single argv-safe remote command.

    Base64-encoding avoids any shell-quoting hazard from the script's own
    content (heredocs, `$()` substitutions, embedded quotes) -- the encoded
    form contains only `[A-Za-z0-9+/=]`, none of which need escaping, and
    decoding happens entirely on the remote side. Shared by
    `deployment_user_bootstrap` (root bootstrap script) and
    `deployment_executors` (deploy-time engine install) so both transmit
    multi-line remote scripts the same safe way. When `env` is provided,
    variables are attached to the decoder's Bash process rather than the
    pipeline's `echo` process, so the decoded script can read them.
    """
    encoded = base64.b64encode(script.encode("utf-8")).decode("ascii")
    pipeline = f"echo {encoded} | base64 -d | bash"
    if not env:
        return pipeline
    assignments = " ".join(f"{key}={shlex.quote(value)}" for key, value in env.items())
    return f"env {assignments} bash -c {shlex.quote(pipeline)}"


def sudo_elevation_preamble() -> str:
    """Bash `sudo_cmd`/`sudo_available` helpers plus a hard-fail guard.

    `sudo_cmd` feeds a sudo password via `NMTK_DEPLOY_SUDO_PASSWORD` (set by
    the caller) through `sudo -S`, or falls back to passwordless `sudo -n`
    -- which also covers a literal root login for free, since root never
    needs a sudo password. The trailing guard fails fast with an actionable
    message when neither path can elevate, rather than letting later
    privileged steps fail with a cryptic permission error.
    """
    return """sudo_cmd() {
  if [ -n "${NMTK_DEPLOY_SUDO_PASSWORD:-}" ]; then
    printf '%s\\n' "$NMTK_DEPLOY_SUDO_PASSWORD" | sudo -S -p "" "$@"
  else
    sudo -n "$@"
  fi
}
sudo_available() {
  if [ -n "${NMTK_DEPLOY_SUDO_PASSWORD:-}" ]; then
    printf '%s\\n' "$NMTK_DEPLOY_SUDO_PASSWORD" | sudo -S -p "" true >/dev/null 2>&1
  else
    sudo -n true >/dev/null 2>&1
  fi
}

if ! sudo_available; then
  echo "[nmtk-bootstrap] ERROR: this account cannot run privileged commands (no root session, no passwordless/NOPASSWD sudo, and no sudo password available). Use a password-based login for an admin account, true root credentials, or configure NOPASSWD sudo for this account." >&2
  exit 1
fi
"""


def container_engine_install_commands(container_engine: str) -> str:
    """Bash that installs `container_engine` on a remote host, via `sudo_cmd`.

    Assumes `sudo_cmd`/`sudo_available` (see `sudo_elevation_preamble`) are
    already defined in the surrounding script.

    `container_engine="podman"` installs Podman + podman-compose via `apt`
    (Debian/Ubuntu only -- matches the actual deploy target; unlike Docker
    there's no distro-agnostic install one-liner). Podman is rootless by
    design, so unlike the Docker branch there is no `usermod -aG <group>`
    step here.
    """
    if container_engine == "podman":
        return """if command -v podman >/dev/null 2>&1; then
  echo "[nmtk-bootstrap] Podman already installed"
else
  echo "[nmtk-bootstrap] Podman not found -- installing via apt (Debian/Ubuntu)..."
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "[nmtk-bootstrap] ERROR: apt-get not found; automatic Podman install only supports Debian/Ubuntu. Install podman + podman-compose manually and retry." >&2
    exit 1
  fi
  sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get update -qq
  sudo_cmd env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq podman podman-compose
  echo "[nmtk-bootstrap] Podman installed"
fi
"""
    return """if getent group docker >/dev/null 2>&1; then
  echo "[nmtk-bootstrap] Docker Engine already installed"
else
  echo "[nmtk-bootstrap] Docker Engine not found \u2014 installing via get.docker.com..."
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://get.docker.com | sudo_cmd sh
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://get.docker.com | sudo_cmd sh
  else
    echo "[nmtk-bootstrap] ERROR: neither curl nor wget available; cannot install Docker" >&2
    exit 1
  fi
  echo "[nmtk-bootstrap] Docker Engine installed"
fi
"""


def podman_runtime_setup_script() -> str:
    """Build the remote script that prepares rootless Podman's API socket."""
    return """#!/usr/bin/env bash
set -euo pipefail

UID_VALUE="$(id -u)"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$UID_VALUE}"
SOCKET_PATH="$XDG_RUNTIME_DIR/podman/podman.sock"
export DOCKER_HOST="unix://$SOCKET_PATH"

enable_linger() {
  if ! command -v loginctl >/dev/null 2>&1; then
    return 0
  fi
  if [ -n "${NMTK_DEPLOY_SUDO_PASSWORD:-}" ]; then
    printf '%s\n' "$NMTK_DEPLOY_SUDO_PASSWORD" |
      sudo -S -p "" loginctl enable-linger "$USER"
  else
    sudo -n loginctl enable-linger "$USER"
  fi
}

enable_linger >/dev/null 2>&1 || true
if command -v systemctl >/dev/null 2>&1 &&
   systemctl --user enable --now podman.socket >/dev/null 2>&1; then
  :
else
  mkdir -p "$XDG_RUNTIME_DIR/podman"
  if [ ! -S "$SOCKET_PATH" ]; then
    nohup podman system service --time=0 "unix://$SOCKET_PATH" \
      >/tmp/nmtk-podman-service.log 2>&1 &
  fi
fi

for _attempt in 1 2 3 4 5 6 7 8 9 10; do
  if [ -S "$SOCKET_PATH" ]; then
    break
  fi
  sleep 1
done

if [ ! -S "$SOCKET_PATH" ]; then
  echo "[nmtk-podman] ERROR: rootless Podman socket was not created at $SOCKET_PATH. Enable a user systemd session or install a working Podman system service." >&2
  exit 1
fi

if command -v curl >/dev/null 2>&1 &&
   ! curl --silent --show-error --fail --unix-socket "$SOCKET_PATH" \
      http://localhost/_ping >/dev/null; then
  echo "[nmtk-podman] ERROR: Podman socket exists at $SOCKET_PATH but its API did not respond. Check the podman.socket user service and runtime logs." >&2
  exit 1
fi

echo "[nmtk-podman] rootless Podman API ready at $DOCKER_HOST"
"""


@dataclass(frozen=True)
class DeploymentCapability:
    supported_modes: tuple[str, ...] = ("standalone", "docker", "kubernetes")
    health_path: str = "/health"
    required_ports: tuple[int, ...] = ()
    required_environment: tuple[str, ...] = ()
    secret_fields: tuple[str, ...] = ()
    default_container_image: str = ""
    compose_profile: str = ""
    chart_template_id: str = ""
    startup_timeout_seconds: float = 120.0
    readiness_timeout_seconds: float = 120.0

    @classmethod
    def from_json(cls, payload: Any) -> DeploymentCapability:
        if not isinstance(payload, dict):
            return cls()
        supported_modes = tuple(
            mode
            for mode in (
                str(item).strip() for item in payload.get("supportedModes", [])
            )
            if mode in DEPLOYMENT_MODES
        )
        required_ports = tuple(
            int(item)
            for item in payload.get("requiredPorts", [])
            if isinstance(item, int) or str(item).isdigit()
        )
        return cls(
            supported_modes=supported_modes or cls.supported_modes,
            health_path=str(payload.get("healthPath") or "/health"),
            required_ports=required_ports,
            required_environment=tuple(
                str(item).strip()
                for item in payload.get("requiredEnvironment", [])
                if str(item).strip()
            ),
            secret_fields=tuple(
                str(item).strip()
                for item in payload.get("secretFields", [])
                if str(item).strip()
            ),
            default_container_image=str(payload.get("defaultContainerImage") or ""),
            compose_profile=str(payload.get("composeProfile") or ""),
            chart_template_id=str(payload.get("chartTemplateId") or ""),
            startup_timeout_seconds=float(
                payload.get("startupTimeoutSeconds") or 120.0
            ),
            readiness_timeout_seconds=float(
                payload.get("readinessTimeoutSeconds") or 120.0
            ),
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "supportedModes": list(self.supported_modes),
            "healthPath": self.health_path,
            "requiredPorts": list(self.required_ports),
            "requiredEnvironment": list(self.required_environment),
            "secretFields": list(self.secret_fields),
            "defaultContainerImage": self.default_container_image,
            "composeProfile": self.compose_profile,
            "chartTemplateId": self.chart_template_id,
            "startupTimeoutSeconds": self.startup_timeout_seconds,
            "readinessTimeoutSeconds": self.readiness_timeout_seconds,
        }


@dataclass
class DeploymentTarget:
    id: str
    display_name: str
    target_type: str
    mode: str
    auth_mode: str = "none"
    host: str = ""
    ssh_port: int = 22
    username: str = ""
    install_root: str = ""
    backend_port: int = 9000
    namespace: str = ""
    context: str = ""
    api_server: str = ""
    image_tag: str = "latest"
    domain: str = ""
    container_engine: str = "docker"
    secret_refs: dict[str, str] = field(default_factory=dict)
    module_environment: dict[str, str] = field(default_factory=dict)
    module_secret_refs: dict[str, str] = field(default_factory=dict)
    last_readiness: str = "unknown"
    last_deployed_version: str = ""
    last_failure_reason: str = ""
    created_at: str = field(default_factory=utc_now_iso)
    updated_at: str = field(default_factory=utc_now_iso)

    @classmethod
    def from_json(cls, payload: dict[str, Any]) -> DeploymentTarget:
        display_name = str(
            payload.get("displayName") or payload.get("display_name") or ""
        )
        target_type = str(
            payload.get("targetType") or payload.get("target_type") or "local"
        )
        mode = str(payload.get("mode") or "standalone")
        auth_mode = str(payload.get("authMode") or payload.get("auth_mode") or "none")
        container_engine = str(
            payload.get("containerEngine")
            or payload.get("container_engine")
            or "docker"
        )
        if target_type not in DEPLOYMENT_TARGET_TYPES:
            raise ValueError(f"Unsupported deployment target type: {target_type}")
        if mode not in DEPLOYMENT_MODES:
            raise ValueError(f"Unsupported deployment mode: {mode}")
        if auth_mode not in DEPLOYMENT_AUTH_MODES:
            raise ValueError(f"Unsupported deployment auth mode: {auth_mode}")
        if container_engine not in DEPLOYMENT_CONTAINER_ENGINES:
            raise ValueError(f"Unsupported container engine: {container_engine}")
        target_id = str(payload.get("id") or "").strip()
        if not target_id:
            target_id = slugify(
                display_name or f"{target_type}-{mode}", fallback=str(uuid4())
            )
        if not display_name:
            display_name = target_id
        return cls(
            id=target_id,
            display_name=display_name,
            target_type=target_type,
            mode=mode,
            auth_mode=auth_mode,
            host=str(payload.get("host") or ""),
            ssh_port=int(payload.get("sshPort") or payload.get("ssh_port") or 22),
            username=str(payload.get("username") or ""),
            install_root=str(
                payload.get("installRoot") or payload.get("install_root") or ""
            ),
            backend_port=int(
                payload.get("backendPort") or payload.get("backend_port") or 9000
            ),
            namespace=str(payload.get("namespace") or ""),
            context=str(payload.get("context") or ""),
            api_server=str(payload.get("apiServer") or payload.get("api_server") or ""),
            image_tag=str(
                payload.get("imageTag") or payload.get("image_tag") or "latest"
            ),
            domain=str(payload.get("domain") or ""),
            container_engine=container_engine,
            secret_refs=dict(
                payload.get("secretRefs") or payload.get("secret_refs") or {}
            ),
            module_environment={
                str(key): str(value)
                for key, value in (
                    payload.get("moduleEnvironment")
                    or payload.get("module_environment")
                    or {}
                ).items()
                if str(key).strip() and str(value).strip()
            },
            module_secret_refs={
                str(key): str(value)
                for key, value in (
                    payload.get("moduleSecretRefs")
                    or payload.get("module_secret_refs")
                    or {}
                ).items()
                if str(key).strip() and str(value).strip()
            },
            last_readiness=str(payload.get("lastReadiness") or "unknown"),
            last_deployed_version=str(payload.get("lastDeployedVersion") or ""),
            last_failure_reason=str(payload.get("lastFailureReason") or ""),
            created_at=str(payload.get("createdAt") or utc_now_iso()),
            updated_at=str(payload.get("updatedAt") or utc_now_iso()),
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "displayName": self.display_name,
            "targetType": self.target_type,
            "mode": self.mode,
            "authMode": self.auth_mode,
            "host": self.host,
            "sshPort": self.ssh_port,
            "username": self.username,
            "installRoot": self.install_root,
            "backendPort": self.backend_port,
            "namespace": self.namespace,
            "context": self.context,
            "apiServer": self.api_server,
            "imageTag": self.image_tag,
            "domain": self.domain,
            "containerEngine": self.container_engine,
            "secretRefs": dict(self.secret_refs),
            "moduleEnvironment": dict(self.module_environment),
            "moduleSecretRefs": dict(self.module_secret_refs),
            "lastReadiness": self.last_readiness,
            "lastDeployedVersion": self.last_deployed_version,
            "lastFailureReason": self.last_failure_reason,
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
        }


@dataclass
class DeploymentPreflightResult:
    status: str
    message: str
    blocking_findings: list[str] = field(default_factory=list)
    degraded_findings: list[str] = field(default_factory=list)
    suggested_recovery: str = ""

    def to_json(self) -> dict[str, Any]:
        return {
            "status": self.status,
            "message": self.message,
            "blockingFindings": list(self.blocking_findings),
            "degradedFindings": list(self.degraded_findings),
            "suggestedRecovery": self.suggested_recovery,
        }


@dataclass
class DeploymentEvent:
    job_id: str
    stage: str
    message: str
    percent: float
    created_at: str = field(default_factory=utc_now_iso)

    def to_json(self) -> dict[str, Any]:
        return {
            "jobId": self.job_id,
            "stage": self.stage,
            "message": redact_text(self.message),
            "percent": self.percent,
            "createdAt": self.created_at,
        }

    def to_sse(self) -> str:
        return (
            "event: progress\ndata: "
            + json.dumps(self.to_json(), sort_keys=True)
            + "\n\n"
        )


@dataclass
class DeploymentJob:
    id: str
    target_id: str
    mode: str
    clean_install: bool = False
    stage: str = "queued"
    percent: float = 0.0
    stage_label: str = "Queued"
    last_log_line: str = ""
    logs: list[str] = field(default_factory=list)
    terminal_output: list[str] = field(default_factory=list)
    requires_ephemeral_administrator: bool = False
    started_at: str = field(default_factory=utc_now_iso)
    updated_at: str = field(default_factory=utc_now_iso)
    blocking_input_needed: str = ""
    terminal_outcome: str = ""
    error: str = ""
    failure_details: dict[str, Any] | None = None
    events: list[dict[str, Any]] = field(default_factory=list)

    @classmethod
    def from_json(cls, payload: dict[str, Any]) -> DeploymentJob:
        return cls(
            id=str(payload.get("id") or uuid4()),
            target_id=str(payload.get("targetId") or payload.get("target_id") or ""),
            mode=str(payload.get("mode") or "standalone"),
            stage=str(payload.get("stage") or "queued"),
            percent=float(payload.get("percent") or 0.0),
            stage_label=str(payload.get("stageLabel") or "Queued"),
            last_log_line=str(payload.get("lastLogLine") or ""),
            logs=[str(item) for item in payload.get("logs", [])],
            terminal_output=bounded_terminal_output(
                list(payload.get("terminalOutput", []))
            ),
            requires_ephemeral_administrator=bool(
                payload.get("requiresEphemeralAdministrator", False)
            ),
            started_at=str(payload.get("startedAt") or utc_now_iso()),
            updated_at=str(payload.get("updatedAt") or utc_now_iso()),
            blocking_input_needed=str(payload.get("blockingInputNeeded") or ""),
            terminal_outcome=str(payload.get("terminalOutcome") or ""),
            error=str(payload.get("error") or ""),
            failure_details=(
                redact_payload(payload["failureDetails"])
                if isinstance(payload.get("failureDetails"), dict)
                else None
            ),
            events=[
                item for item in payload.get("events", []) if isinstance(item, dict)
            ],
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "targetId": self.target_id,
            "mode": self.mode,
            "cleanInstall": self.clean_install,
            "stage": self.stage,
            "percent": self.percent,
            "stageLabel": self.stage_label,
            "lastLogLine": self.last_log_line,
            "logs": list(self.logs[-200:]),
            "terminalOutput": bounded_terminal_output(self.terminal_output),
            "requiresEphemeralAdministrator": (self.requires_ephemeral_administrator),
            "startedAt": self.started_at,
            "updatedAt": self.updated_at,
            "blockingInputNeeded": self.blocking_input_needed,
            "terminalOutcome": self.terminal_outcome,
            "error": self.error,
            **(
                {"failureDetails": redact_payload(self.failure_details)}
                if self.failure_details is not None
                else {}
            ),
            "events": list(self.events[-200:]),
        }
