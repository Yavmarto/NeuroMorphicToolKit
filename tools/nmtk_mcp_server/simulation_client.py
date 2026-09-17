from __future__ import annotations

from enum import StrEnum
from typing import Any

import requests
from pydantic import BaseModel, ConfigDict, Field


class SimulationClientError(RuntimeError):
    """Raised when simulation job submission or polling fails."""


class SimulationJobStatus(StrEnum):
    queued = "queued"
    running = "running"
    complete = "complete"
    failed = "failed"


class SimulationRequest(BaseModel):
    spec: str
    params: dict[str, Any] = Field(default_factory=dict)
    duration: float = 1.0
    dt: float = 0.001
    backend: str = "nengo"


class SimulationJobResponse(BaseModel):
    model_config = ConfigDict(extra="allow")

    job_id: str
    status: SimulationJobStatus
    result: Any | None = None
    error: Any | None = None
    request_id: str | None = None


class SimulationClient:
    def __init__(self, suite_api_base_url: str = "http://127.0.0.1:9000") -> None:
        self.suite_api_base_url = suite_api_base_url.rstrip("/")

    def submit_simulation(self, request: SimulationRequest) -> SimulationJobResponse:
        """Submit a NeuroCNL simulation job through suite_api."""
        url = f"{self.suite_api_base_url}/api/neurocnl/simulate"
        try:
            response = requests.post(
                url,
                json=request.model_dump(),
                headers={"Content-Type": "application/json"},
                timeout=30,
            )
            response.raise_for_status()
        except requests.RequestException as exc:
            raise SimulationClientError(
                f"Simulation submission failed for {url}: {exc}"
            ) from exc

        return _parse_job_response(response, context="Simulation submission")

    def poll_job(self, job_id: str) -> SimulationJobResponse:
        """Poll a NeuroCNL simulation job through suite_api."""
        url = f"{self.suite_api_base_url}/api/neurocnl/jobs/{job_id}"
        try:
            response = requests.get(url, timeout=10)
            response.raise_for_status()
        except requests.RequestException as exc:
            raise SimulationClientError(
                f"Simulation job polling failed for {url}: {exc}"
            ) from exc

        return _parse_job_response(response, context="Simulation job polling")


def _parse_job_response(
    response: requests.Response,
    *,
    context: str,
) -> SimulationJobResponse:
    try:
        data = response.json()
    except ValueError as exc:
        raise SimulationClientError(f"{context} response was not valid JSON: {exc}") from exc

    if not isinstance(data, dict):
        raise SimulationClientError(
            f"{context} response did not return a JSON object: {type(data).__name__}"
        )

    try:
        return SimulationJobResponse.model_validate(data)
    except Exception as exc:
        raise SimulationClientError(
            f"{context} response did not match the expected schema: {exc}"
        ) from exc
