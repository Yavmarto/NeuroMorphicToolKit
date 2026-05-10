import requests
from pydantic import BaseModel, Field
from typing import Any


class SimulationClientError(RuntimeError):
    """Raised when simulation-oriented API calls fail."""


class NeuroCnlSimulationRequest(BaseModel):
    spec: str
    backend: str = "nengo"
    mode: str = "validate_only"
    params: dict[str, Any] = Field(default_factory=dict)


class NeuroSimPreviewRequest(BaseModel):
    graph_or_spec: dict[str, Any] | str
    duration_ms: int = 1000


class JobRef(BaseModel):
    job_id: str
    status: str


class SimulationClient:
    def __init__(self, suite_api_base_url: str = "http://127.0.0.1:9000") -> None:
        self.suite_api_base_url = suite_api_base_url.rstrip("/")

    def run_neurocnl_simulation(self, request: NeuroCnlSimulationRequest) -> JobRef:
        """Return a queued job reference for full mode or a local validation-shaped placeholder for validate_only mode."""
        if request.mode == "validate_only":
            return JobRef(job_id="local-validation", status="completed")

        url = f"{self.suite_api_base_url}/api/neurocnl/simulate"
        try:
            response = requests.post(
                url,
                json=request.model_dump(),
                timeout=30,
            )
            response.raise_for_status()
            data = response.json()
            return JobRef(job_id=data.get("job_id", "unknown"), status=data.get("status", "queued"))
        except requests.RequestException as e:
            raise SimulationClientError(f"Failed to run NeuroCNL simulation: {e}") from e

    def run_neurosim_preview(self, request: NeuroSimPreviewRequest) -> dict[str, Any]:
        """POST to /api/neurosim/preview and return parsed JSON."""
        url = f"{self.suite_api_base_url}/api/neurosim/preview"
        try:
            response = requests.post(
                url,
                json=request.model_dump(),
                timeout=30,
            )
            response.raise_for_status()
            return response.json()
        except requests.RequestException as e:
            raise SimulationClientError(f"Failed to run NeuroSim preview: {e}") from e
