"""Typed contracts for launcher-owned backend deployment setup."""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

DEPLOYMENT_TARGET_TYPES = {"local", "remote_host", "kubernetes_cluster"}
DEPLOYMENT_MODES = {"standalone", "docker", "kubernetes"}
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
    return redacted


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
    def from_json(cls, payload: Any) -> "DeploymentCapability":
        if not isinstance(payload, dict):
            return cls()
        supported_modes = tuple(
            mode
            for mode in (str(item).strip() for item in payload.get("supportedModes", []))
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
            startup_timeout_seconds=float(payload.get("startupTimeoutSeconds") or 120.0),
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
    secret_refs: dict[str, str] = field(default_factory=dict)
    last_readiness: str = "unknown"
    last_deployed_version: str = ""
    last_failure_reason: str = ""
    created_at: str = field(default_factory=utc_now_iso)
    updated_at: str = field(default_factory=utc_now_iso)

    @classmethod
    def from_json(cls, payload: dict[str, Any]) -> "DeploymentTarget":
        display_name = str(payload.get("displayName") or payload.get("display_name") or "")
        target_type = str(payload.get("targetType") or payload.get("target_type") or "local")
        mode = str(payload.get("mode") or "standalone")
        auth_mode = str(payload.get("authMode") or payload.get("auth_mode") or "none")
        if target_type not in DEPLOYMENT_TARGET_TYPES:
            raise ValueError(f"Unsupported deployment target type: {target_type}")
        if mode not in DEPLOYMENT_MODES:
            raise ValueError(f"Unsupported deployment mode: {mode}")
        if auth_mode not in DEPLOYMENT_AUTH_MODES:
            raise ValueError(f"Unsupported deployment auth mode: {auth_mode}")
        target_id = str(payload.get("id") or "").strip()
        if not target_id:
            target_id = slugify(display_name or f"{target_type}-{mode}", fallback=str(uuid4()))
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
            install_root=str(payload.get("installRoot") or payload.get("install_root") or ""),
            backend_port=int(payload.get("backendPort") or payload.get("backend_port") or 9000),
            namespace=str(payload.get("namespace") or ""),
            context=str(payload.get("context") or ""),
            api_server=str(payload.get("apiServer") or payload.get("api_server") or ""),
            image_tag=str(payload.get("imageTag") or payload.get("image_tag") or "latest"),
            domain=str(payload.get("domain") or ""),
            secret_refs=dict(payload.get("secretRefs") or payload.get("secret_refs") or {}),
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
            "secretRefs": dict(self.secret_refs),
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
        return "event: progress\ndata: " + json.dumps(self.to_json(), sort_keys=True) + "\n\n"


@dataclass
class DeploymentJob:
    id: str
    target_id: str
    mode: str
    stage: str = "queued"
    percent: float = 0.0
    stage_label: str = "Queued"
    last_log_line: str = ""
    logs: list[str] = field(default_factory=list)
    started_at: str = field(default_factory=utc_now_iso)
    updated_at: str = field(default_factory=utc_now_iso)
    blocking_input_needed: str = ""
    terminal_outcome: str = ""
    error: str = ""
    events: list[dict[str, Any]] = field(default_factory=list)

    @classmethod
    def from_json(cls, payload: dict[str, Any]) -> "DeploymentJob":
        return cls(
            id=str(payload.get("id") or uuid4()),
            target_id=str(payload.get("targetId") or payload.get("target_id") or ""),
            mode=str(payload.get("mode") or "standalone"),
            stage=str(payload.get("stage") or "queued"),
            percent=float(payload.get("percent") or 0.0),
            stage_label=str(payload.get("stageLabel") or "Queued"),
            last_log_line=str(payload.get("lastLogLine") or ""),
            logs=[str(item) for item in payload.get("logs", [])],
            started_at=str(payload.get("startedAt") or utc_now_iso()),
            updated_at=str(payload.get("updatedAt") or utc_now_iso()),
            blocking_input_needed=str(payload.get("blockingInputNeeded") or ""),
            terminal_outcome=str(payload.get("terminalOutcome") or ""),
            error=str(payload.get("error") or ""),
            events=[
                item for item in payload.get("events", []) if isinstance(item, dict)
            ],
        )

    def to_json(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "targetId": self.target_id,
            "mode": self.mode,
            "stage": self.stage,
            "percent": self.percent,
            "stageLabel": self.stage_label,
            "lastLogLine": self.last_log_line,
            "logs": list(self.logs[-200:]),
            "startedAt": self.started_at,
            "updatedAt": self.updated_at,
            "blockingInputNeeded": self.blocking_input_needed,
            "terminalOutcome": self.terminal_outcome,
            "error": self.error,
            "events": list(self.events[-200:]),
        }
