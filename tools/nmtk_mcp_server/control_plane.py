from __future__ import annotations

import requests

from .control_plane_models import (
    LauncherDoctorResponse,
    LauncherDoctorSummary,
    SuiteHealthResponse,
)


class ControlPlaneClientError(RuntimeError):
    """Raised when a control-plane API call fails."""


class ControlPlaneClient:
    def __init__(
        self,
        suite_api_base_url: str = "http://127.0.0.1:9000",
        launcher_base_url: str = "http://127.0.0.1:8765",
    ) -> None:
        self.suite_api_base_url = suite_api_base_url.rstrip("/")
        self.launcher_base_url = launcher_base_url.rstrip("/")

    def suite_health(self) -> SuiteHealthResponse:
        """GET /api/suite/health and return a typed response."""
        url = f"{self.suite_api_base_url}/api/suite/health"
        try:
            response = requests.get(url, timeout=10)
            response.raise_for_status()
        except requests.RequestException as exc:
            raise ControlPlaneClientError(
                f"Suite health request failed for {url}: {exc}"
            ) from exc

        try:
            return SuiteHealthResponse.model_validate(response.json())
        except ValueError as exc:
            raise ControlPlaneClientError(
                f"Suite health response was not valid JSON: {exc}"
            ) from exc
        except Exception as exc:
            raise ControlPlaneClientError(
                f"Suite health response did not match the expected schema: {exc}"
            ) from exc

    def doctor(self) -> LauncherDoctorSummary:
        """GET /api/launcher/doctor and return a typed summary plus raw report."""
        url = f"{self.launcher_base_url}/api/launcher/doctor"
        try:
            response = requests.get(url, timeout=10)
            response.raise_for_status()
        except requests.RequestException as exc:
            raise ControlPlaneClientError(
                f"Launcher doctor request failed for {url}: {exc}"
            ) from exc

        try:
            report = LauncherDoctorResponse.model_validate(response.json())
        except ValueError as exc:
            raise ControlPlaneClientError(
                f"Launcher doctor response was not valid JSON: {exc}"
            ) from exc
        except Exception as exc:
            raise ControlPlaneClientError(
                f"Launcher doctor response did not match the expected schema: {exc}"
            ) from exc

        return classify_doctor_report(report)


def classify_doctor_report(report: LauncherDoctorResponse) -> LauncherDoctorSummary:
    """Map launcher doctor counters into explicit MCP-facing status semantics."""
    if report.fatalCount > 0:
        status = "preflight_failed"
        blocking = True
    elif report.degradedCount > 0:
        status = "degraded_optional_capability"
        blocking = False
    else:
        status = "ok"
        blocking = False

    return LauncherDoctorSummary(
        status=status,
        blocking=blocking,
        fatal_count=report.fatalCount,
        degraded_count=report.degradedCount,
        ok_count=report.okCount,
        report=report,
    )
