import requests
from pydantic import BaseModel, Field
from typing import Any


class DeployabilityClientError(RuntimeError):
    """Raised when deployability boilerplate calls fail."""


class DeployabilityRequest(BaseModel):
    spec: str
    target: str
    options: dict[str, Any] = Field(default_factory=dict)


class DeployabilityResponse(BaseModel):
    target: str
    route: str
    accepted: bool
    raw_response: dict[str, Any] = Field(default_factory=dict)


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
        }

    def check_deployability(self, request: DeployabilityRequest) -> DeployabilityResponse:
        """Call the target-specific route without inventing final production verdict semantics."""
        route = self._target_routes.get(request.target)
        if not route:
            raise DeployabilityClientError(f"Unknown target: {request.target}")

        url = f"{self.suite_api_base_url}{route}"
        try:
            response = requests.post(
                url,
                json={"spec": request.spec, **request.options},
                timeout=30,
            )
            response.raise_for_status()
            data = response.json()
            return DeployabilityResponse(
                target=request.target,
                route=route,
                accepted=data.get("accepted", False),
                raw_response=data,
            )
        except requests.RequestException as e:
            raise DeployabilityClientError(f"Failed to check deployability for {request.target}: {e}") from e

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
