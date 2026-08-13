"""Pure doctor-report helpers: SDK/toolchain preflight checks and rendering.

Imported by ``server.py`` right before ``LauncherControlState`` is defined, so
the ``from .server import ...`` below resolves against the partially
initialized module rather than re-entering it — the names it pulls in must
already be bound in ``server.py`` above that import line.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path
from typing import Any

from .config import REPO_ROOT
from .suite_api_service import _suite_api_env_dir, _suite_api_env_python, _suite_api_pythonpath
from .server import PREFLIGHT_DEGRADED, PREFLIGHT_FAILED, PREFLIGHT_OK


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
    """Advisory check: Studio target SDKs in the suite_api runtime."""
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

    probe_script = (
        "from neurocnl.target_sdk import probe_target_availability; "
        "availability = probe_target_availability(); "
        "required = ('brian2', 'pynn', 'akida', 'lava_sim'); "
        "missing = [name for name in required if not availability.get(name)]; "
        "import sys; "
        "print(','.join(missing)); "
        "sys.exit(0 if not missing else 1)"
    )
    result = subprocess.run(
        [str(venv_python), "-c", probe_script],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=False,
        env={**os.environ, "PYTHONPATH": _suite_api_pythonpath()},
    )
    if result.returncode == 0:
        return {
            "id": check_id,
            "name": check_name,
            "preflightStatus": PREFLIGHT_OK,
            "preflightMessage": "Brian2, PyNN, Akida, and Lava probes are ready",
            "capabilityWarnings": [],
        }

    missing = [part for part in result.stdout.strip().split(",") if part]
    lava_hint = (
        " Start lava-backend (docker compose up) or set NEUROCNL_LAVA_WORKER_URL."
        if "lava_sim" in missing
        else ""
    )
    reinstall_hint = (
        " Reinstall suite_api env: delete "
        f"{env_dir} and restart launcher control."
    )
    return {
        "id": check_id,
        "name": check_name,
        "preflightStatus": PREFLIGHT_DEGRADED,
        "preflightMessage": (
            "Studio target SDKs missing in suite_api: "
            + (", ".join(missing) if missing else "unknown")
            + reinstall_hint
            + lava_hint
        ),
        "capabilityWarnings": [
            f"Setup may show download icons for: {', '.join(missing) if missing else 'framework targets'}"
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
