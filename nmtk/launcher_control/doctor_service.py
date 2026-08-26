"""Pure doctor-report helpers: SDK/toolchain preflight checks and rendering."""

from __future__ import annotations

import os
import shutil
from pathlib import Path
from typing import Any

from .suite_api_service import (
    _read_suite_api_capability_warnings,
    _suite_api_env_dir,
    _suite_api_env_python,
)
from .state_contracts import PREFLIGHT_DEGRADED, PREFLIGHT_FAILED, PREFLIGHT_OK


def _doctor_prefix(status: str) -> str:
    return (
        "preflight failed"
        if status == PREFLIGHT_FAILED
        else "degraded optional capability"
        if status == PREFLIGHT_DEGRADED
        else "OK"
    )


def _flutter_sdk_check() -> dict[str, Any]:
    flutter = shutil.which("flutter")
    if flutter is None:
        return {
            "id": "flutter-sdk",
            "name": "Flutter SDK",
            "preflightStatus": PREFLIGHT_FAILED,
            "preflightMessage": "Flutter executable not found on PATH",
            "capabilityWarnings": [],
        }

    flutter_path = Path(flutter).resolve()
    cache_dir = flutter_path.parent / "cache"
    engine_stamp = cache_dir / "engine.stamp"

    if not cache_dir.exists():
        return {
            "id": "flutter-sdk",
            "name": "Flutter SDK",
            "preflightStatus": PREFLIGHT_FAILED,
            "preflightMessage": f"Flutter SDK cache directory missing: {cache_dir}",
            "capabilityWarnings": [],
        }

    if not os.access(cache_dir, os.W_OK):
        return {
            "id": "flutter-sdk",
            "name": "Flutter SDK",
            "preflightStatus": PREFLIGHT_FAILED,
            "preflightMessage": f"Flutter SDK cache is not writable: {cache_dir}",
            "capabilityWarnings": [],
        }

    if engine_stamp.exists() and not os.access(engine_stamp, os.W_OK):
        return {
            "id": "flutter-sdk",
            "name": "Flutter SDK",
            "preflightStatus": PREFLIGHT_FAILED,
            "preflightMessage": f"Flutter SDK cache stamp is not writable: {engine_stamp}",
            "capabilityWarnings": [],
        }

    return {
        "id": "flutter-sdk",
        "name": "Flutter SDK",
        "preflightStatus": PREFLIGHT_OK,
        "preflightMessage": f"Flutter SDK cache ready: {cache_dir}",
        "capabilityWarnings": [],
    }


def _global_preflight_checks() -> list[dict[str, Any]]:
    checks = [_studio_framework_sdk_check()]
    # The remote launcher-control container manages backend services only. The
    # Flutter SDK belongs to the desktop app host and is neither installed nor
    # needed in this runtime, so reporting its absence here would make every
    # healthy deployed backend fail doctor.
    if os.environ.get("NMTK_BACKEND_DEPLOYMENT_READY", "").strip().lower() not in {
        "1",
        "true",
        "yes",
    }:
        checks.insert(0, _flutter_sdk_check())
    return checks


def _studio_framework_sdk_check() -> dict[str, Any]:
    """Read cached Studio capability metadata without executing the runtime."""
    check_id = "studio-framework-sdks"
    check_name = "Studio framework SDKs"
    env_dir = _suite_api_env_dir()
    venv_python = _suite_api_env_python(env_dir)
    if not venv_python.exists():
        return {
            "id": check_id,
            "name": check_name,
            "preflightStatus": PREFLIGHT_OK,
            "preflightMessage": "suite_api environment not provisioned yet",
            "capabilityWarnings": [],
        }

    warnings = _read_suite_api_capability_warnings(env_dir)
    if not warnings:
        return {
            "id": check_id,
            "name": check_name,
            "preflightStatus": PREFLIGHT_OK,
            "preflightMessage": "Brian2, PyNN, Akida, and Lava probes are ready",
            "capabilityWarnings": [],
        }

    return {
        "id": check_id,
        "name": check_name,
        "preflightStatus": PREFLIGHT_DEGRADED,
        "preflightMessage": (
            "Suite API reports optional Studio capability limits: "
            + "; ".join(warnings)
        ),
        "capabilityWarnings": [
            "Setup may show download icons for unavailable framework targets."
        ],
    }


def _render_doctor_report(report: dict[str, Any]) -> str:
    summary = (
        "preflight failed"
        if report["fatalCount"] > 0
        else "degraded optional capability"
        if report["degradedCount"] > 0
        else "ok"
    )
    lines = [
        "NMTK launcher doctor",
        f"status={summary}",
        f"fatal={report['fatalCount']} degraded={report['degradedCount']} ok={report['okCount']}",
    ]
    for check in report.get("globalChecks", []):
        lines.append(
            f"{_doctor_prefix(str(check['preflightStatus']))} {check['id']}: "
            f"{check['preflightMessage'] or 'ready'}"
        )
        for warning in check.get("capabilityWarnings", []):
            lines.append(f"  - {warning}")
    for module in report["modules"]:
        lines.append(
            f"{_doctor_prefix(str(module['preflightStatus']))} {module['id']}: "
            f"{module['preflightMessage'] or 'ready'}"
        )
        for warning in module.get("capabilityWarnings", []):
            lines.append(f"  - {warning}")
    return "\n".join(lines)
