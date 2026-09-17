"""Shared HTTP client base for NMTK notebook helpers."""
from __future__ import annotations

import os

import requests


class NmtkConnectionError(RuntimeError):
    """Raised when a backend service cannot be reached."""


class NmtkServiceClient:
    """Minimal HTTP client that reads its base URL from an environment variable."""

    def __init__(self, env_var: str, service_name: str, default_url: str) -> None:
        self._env_var = env_var
        self._service_name = service_name
        self._default_url = default_url

    @property
    def base_url(self) -> str:
        return os.environ.get(self._env_var, self._default_url).rstrip("/")

    def _post(self, path: str, json: object, *, timeout: float = 120.0) -> dict:
        url = f"{self.base_url}{path}"
        try:
            resp = requests.post(url, json=json, timeout=timeout)
            resp.raise_for_status()
            return resp.json()
        except requests.ConnectionError as exc:
            raise NmtkConnectionError(
                f"{self._service_name} is not reachable at {self.base_url}. "
                f"Is the container running? ({exc})"
            ) from exc

    def _get(self, path: str, *, timeout: float = 10.0) -> dict:
        url = f"{self.base_url}{path}"
        try:
            resp = requests.get(url, timeout=timeout)
            resp.raise_for_status()
            return resp.json()
        except requests.ConnectionError as exc:
            raise NmtkConnectionError(
                f"{self._service_name} is not reachable at {self.base_url}. "
                f"Is the container running? ({exc})"
            ) from exc
