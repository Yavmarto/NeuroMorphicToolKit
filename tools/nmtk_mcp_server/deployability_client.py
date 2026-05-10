from __future__ import annotations

from typing import Any

import requests
from pydantic import BaseModel, Field


class DeployabilityClientError(RuntimeError):
    """Raised when deployability checks fail or return unexpected data."""


class DeployabilityRequest(BaseModel):
    spec: str
    target: str
    options: dict[str, Any] = Field(default_factory=dict)


class DeployabilityResponse(BaseModel):
    target: str
    route: str
    outcome: str
    warnings: list[str] = Field(default_factory=list)
    rejections: list[str] = Field(default_factory=list)
    raw_response: dict[str, Any] = Field(default_factory=dict)
    payload: dict[str, Any] | None = None
    network_summary: dict[str, Any] | None = None
    topology_verdict: str | None = None
    akida_version: str | None = None


class NeurochipHandoff(BaseModel):
    target: str
    spec: str
    readiness_summary: dict[str, Any] = Field(default_factory=dict)
    artifacts: list[dict[str, Any]] = Field(default_factory=list)


class DeployabilityClient:
    def __init__(self, suite_api_base_url: str = "http://127.0.0.1:9000") -> None:
        self.suite_api_base_url = suite_api_base_url.rstrip("/")
        self._target_routes = {
            "teensy": "/api/neurocnl/deploy/teensy/network",
            "pynq": "/api/neurocnl/deploy/pynq/network",
            "akida": "/api/neurocnl/deploy/akida/network",
        }

    def check_deployability(
        self, request: DeployabilityRequest
    ) -> DeployabilityResponse:
        """Call the target-specific route and preserve its authoritative verdict."""
        target = request.target.strip().lower()
        route = self._target_routes.get(target)
        if route is None:
            raise DeployabilityClientError(f"Unknown target: {request.target}")

        url = f"{self.suite_api_base_url}{route}"
        try:
            response = requests.post(
                url,
                json={"spec": request.spec, **request.options},
                headers={"Content-Type": "application/json"},
                timeout=30,
            )
        except requests.RequestException as exc:
            raise DeployabilityClientError(
                f"Deployability request failed for {target} at {url}: {exc}"
            ) from exc

        if response.status_code == 422:
            return self._handle_invalid_request(response, target=target, route=route)

        try:
            response.raise_for_status()
        except requests.RequestException as exc:
            raise DeployabilityClientError(
                f"Deployability request failed for {target} at {url}: {exc}"
            ) from exc

        try:
            data = response.json()
        except ValueError as exc:
            raise DeployabilityClientError(
                f"Deployability response was not valid JSON for {target}: {exc}"
            ) from exc

        if not isinstance(data, dict):
            raise DeployabilityClientError(
                f"Deployability response did not return a JSON object for {target}"
            )

        return self._parse_success_response(data, target=target, route=route)

    def prepare_neurochip_handoff(
        self,
        spec: str,
        target: str,
        readiness_summary: dict[str, Any] | None = None,
    ) -> NeurochipHandoff:
        """Create a typed handoff payload without device execution."""
        return NeurochipHandoff(
            target=target,
            spec=spec,
            readiness_summary=readiness_summary or {},
            artifacts=[],
        )

    def _handle_invalid_request(
        self,
        response: requests.Response,
        *,
        target: str,
        route: str,
    ) -> DeployabilityResponse:
        try:
            data = response.json()
        except ValueError as exc:
            raise DeployabilityClientError(
                f"Deployability error response was not valid JSON for {target}: {exc}"
            ) from exc

        detail = data.get("detail")
        if not isinstance(detail, dict):
            raise DeployabilityClientError(
                f"Deployability error response did not match the expected schema for {target}"
            )

        if detail.get("error") != "not_deployable":
            raise DeployabilityClientError(
                f"Deployability request was rejected for {target}: {detail}"
            )

        return DeployabilityResponse(
            target=target,
            route=route,
            outcome="not_deployable",
            warnings=_string_list(detail.get("warnings")),
            rejections=_string_list(detail.get("rejection_reasons")),
            raw_response=data,
        )

    def _parse_success_response(
        self,
        data: dict[str, Any],
        *,
        target: str,
        route: str,
    ) -> DeployabilityResponse:
        if target == "teensy":
            outcome = str(data.get("verdict") or "unknown")
            return DeployabilityResponse(
                target=target,
                route=route,
                outcome=outcome,
                warnings=_string_list(data.get("warnings")),
                rejections=_string_list(data.get("rejection_reasons")),
                raw_response=data,
                payload=_dict_or_none(data.get("payload")),
            )

        if target == "pynq":
            outcome = str(data.get("support_state") or "unknown")
            return DeployabilityResponse(
                target=target,
                route=route,
                outcome=outcome,
                warnings=_string_list(data.get("warnings")),
                rejections=_string_list(data.get("rejections")),
                raw_response=data,
                payload=_dict_or_none(data.get("deploy_payload")),
                network_summary=_dict_or_none(data.get("network_summary")),
            )

        outcome = str(data.get("support_state") or "unknown")
        return DeployabilityResponse(
            target=target,
            route=route,
            outcome=outcome,
            warnings=_string_list(data.get("warnings")),
            rejections=_string_list(data.get("rejections")),
            raw_response=data,
            payload=_dict_or_none(data.get("mapped_network")),
            network_summary=_dict_or_none(data.get("network_summary")),
            topology_verdict=_string_or_none(data.get("topology_verdict")),
            akida_version=_string_or_none(data.get("akida_version")),
        )


def _string_list(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    return [str(item) for item in value]


def _dict_or_none(value: Any) -> dict[str, Any] | None:
    return value if isinstance(value, dict) else None


def _string_or_none(value: Any) -> str | None:
    return str(value) if value is not None else None
