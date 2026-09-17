"""Akida runtime request orchestration separated from launcher state."""

from __future__ import annotations

from typing import Any, Protocol

from .hardware_models import _akida_host_state_for_status


class AkidaRuntimeProxyOwnerProtocol(Protocol):
    """State compatibility surface required by runtime proxy orchestration."""

    def _get_akida_host(self, host_id: str) -> dict[str, Any]: ...

    def _emit_akida_terminal_log(
        self, host: dict[str, Any], message: str, *, stderr: bool = False
    ) -> None: ...

    def _akida_json_request(
        self,
        host: dict[str, Any],
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        *,
        allow_recovery: bool = True,
        timeout: float = 15.0,
    ) -> dict[str, Any]: ...

    def _update_akida_host_fields(
        self, host_id: str, **fields: Any
    ) -> dict[str, Any]: ...


class AkidaRuntimeProxyService:
    """Validate and forward runtime operations for a selected Akida host."""

    def __init__(self, owner: AkidaRuntimeProxyOwnerProtocol) -> None:
        self._owner = owner

    def map(
        self,
        host_id: str,
        payload: dict[str, Any],
        *,
        bit_width: int = 4,
    ) -> dict[str, Any]:
        host = self._owner._get_akida_host(host_id)
        self._owner._emit_akida_terminal_log(
            host, f"proxying runtime map request (bit_width={bit_width})"
        )
        status = self._owner._akida_json_request(
            host,
            "POST",
            f"/api/neurochip/akida/map?bit_width={bit_width}",
            payload,
        )
        self._owner._emit_akida_terminal_log(
            host,
            "runtime map completed with target "
            f"{str(status.get('runtime_target') or 'unknown').strip() or 'unknown'}",
        )
        self._owner._update_akida_host_fields(
            host_id,
            state=_akida_host_state_for_status(host, status),
            lastStatus=status,
        )
        return status

    def run(self, host_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        host = self._owner._get_akida_host(host_id)
        self._owner._emit_akida_terminal_log(host, "proxying runtime inference request")
        result = self._owner._akida_json_request(
            host, "POST", "/api/neurochip/akida/inference", payload
        )
        self._owner._emit_akida_terminal_log(
            host,
            "runtime inference completed on "
            f"{str(result.get('runtime_target') or 'unknown').strip() or 'unknown'}",
        )
        return result

    def submit_model_job(self, host_id: str, payload: dict[str, Any]) -> dict[str, Any]:
        encoded = payload.get("bundleBase64")
        if not isinstance(encoded, str) or not encoded:
            raise ValueError("bundleBase64 is required")
        if len(encoded) > 45 * 1024 * 1024:
            raise ValueError("Encoded model bundle exceeds the 45 MB proxy limit")
        host = self._owner._get_akida_host(host_id)
        self._owner._emit_akida_terminal_log(
            host, "submitting Akida model conversion job"
        )
        return self._owner._akida_json_request(
            host,
            "POST",
            "/api/neurochip/akida/model-jobs",
            payload,
            timeout=300.0,
        )

    def model_job_status(self, host_id: str, job_id: str) -> dict[str, Any]:
        host = self._owner._get_akida_host(host_id)
        return self._owner._akida_json_request(
            host, "GET", f"/api/neurochip/akida/model-jobs/{job_id}"
        )

    def model_inference(
        self, host_id: str, model_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        host = self._owner._get_akida_host(host_id)
        return self._owner._akida_json_request(
            host,
            "POST",
            f"/api/neurochip/akida/models/{model_id}/inference",
            payload,
        )

    def model_benchmark(self, host_id: str, model_id: str) -> dict[str, Any]:
        host = self._owner._get_akida_host(host_id)
        self._owner._emit_akida_terminal_log(host, "starting Akida benchmark run")
        return self._owner._akida_json_request(
            host,
            "POST",
            f"/api/neurochip/akida/models/{model_id}/benchmark",
            {},
        )

    def model_visualization(
        self, host_id: str, model_id: str, payload: dict[str, Any]
    ) -> dict[str, Any]:
        host = self._owner._get_akida_host(host_id)
        return self._owner._akida_json_request(
            host,
            "POST",
            f"/api/neurochip/akida/models/{model_id}/visualization",
            payload,
            timeout=300.0,
        )


__all__ = ["AkidaRuntimeProxyOwnerProtocol", "AkidaRuntimeProxyService"]
