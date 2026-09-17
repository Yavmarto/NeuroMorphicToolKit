from __future__ import annotations

import requests

from .models import ValidateCnlRequest, ValidateCnlResponse


class NeuroCnlClientError(RuntimeError):
    """Raised when the NeuroCNL API call fails."""


class NeuroCnlClient:
    def __init__(self, base_url: str = "http://127.0.0.1:9000") -> None:
        self.base_url = base_url.rstrip("/")

    def validate_cnl(self, request: ValidateCnlRequest) -> ValidateCnlResponse:
        """POST to /api/neurocnl/validate and return a typed response."""
        url = f"{self.base_url}/api/neurocnl/validate"
        try:
            response = requests.post(
                url,
                json=request.model_dump(),
                headers={"Content-Type": "application/json"},
                timeout=30,
            )
            response.raise_for_status()
        except requests.RequestException as exc:
            raise NeuroCnlClientError(
                f"NeuroCNL validation request failed for {url}: {exc}"
            ) from exc

        try:
            data = response.json()
        except ValueError as exc:
            raise NeuroCnlClientError(
                f"NeuroCNL validation response was not valid JSON: {exc}"
            ) from exc

        try:
            return ValidateCnlResponse.model_validate(data)
        except Exception as exc:
            raise NeuroCnlClientError(
                f"NeuroCNL validation response did not match the expected schema: {exc}"
            ) from exc
