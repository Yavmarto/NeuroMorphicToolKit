"""Manage and inspect the consolidated NMTK backend stack."""

from __future__ import annotations

import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any

import httpx
import typer

from neurocli.output import error_exit, print_result

_PACKAGE_REPO_ROOT = Path(__file__).parent.parent.parent
_CORE_SERVICES = ("suite_api", "launcher-control", "jupyter-server")
_DEFAULT_API_URL = "http://127.0.0.1:9000"


def _repo_root() -> Path:
    root = Path(os.environ.get("NMTK_ROOT", _PACKAGE_REPO_ROOT)).resolve()
    if not (root / "docker-compose.yml").is_file():
        raise FileNotFoundError(f"NMTK checkout not found at {root}; set NMTK_ROOT to the repository root.")
    return root


def _api_url(flag: str | None) -> str:
    return (flag or os.environ.get("NMTK_SUITE_API_URL") or _DEFAULT_API_URL).rstrip("/")


def _require_compose(json_mode: bool) -> None:
    if shutil.which("docker") is None:
        error_exit(
            {
                "error": "docker_not_found",
                "message": "Install Docker with the Compose plugin, then retry.",
            },
            json_mode,
            code=2,
        )
    try:
        subprocess.run(
            ["docker", "compose", "version"],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError as exc:
        error_exit(
            {
                "error": "compose_unavailable",
                "message": "Docker is installed but the Compose plugin is unavailable.",
                "detail": (exc.stderr or exc.stdout or "").strip(),
            },
            json_mode,
            code=2,
        )


def _compose(command: list[str], json_mode: bool, error: str) -> None:
    _require_compose(json_mode)
    try:
        root = _repo_root()
        subprocess.run(
            ["docker", "compose", *command],
            cwd=root,
            check=True,
            capture_output=json_mode,
            text=json_mode,
        )
    except FileNotFoundError as exc:
        error_exit({"error": "checkout_not_found", "detail": str(exc)}, json_mode, code=2)
    except subprocess.CalledProcessError as exc:
        error_exit(
            {
                "error": error,
                "returncode": exc.returncode,
                "detail": ((exc.stderr or exc.stdout or "").strip() if json_mode else ""),
            },
            json_mode,
            code=2,
        )


def status_command(
    api_url: str | None = typer.Option(None, "--api-url", help="Suite API base URL"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Read consolidated module health from Suite API."""
    base_url = _api_url(api_url)
    started = time.monotonic()
    try:
        suite_response = httpx.get(f"{base_url}/api/suite/health", timeout=5.0)
        suite_response.raise_for_status()
        modules_response = httpx.get(f"{base_url}/api/suite/health/modules", timeout=10.0)
        modules_response.raise_for_status()
        suite = suite_response.json()
        modules_payload = modules_response.json()
    except (httpx.HTTPError, ValueError) as exc:
        error_exit(
            {
                "error": "suite_unreachable",
                "api_url": base_url,
                "message": "The NMTK backend is not reachable; run `neuro run` and retry.",
                "detail": str(exc),
            },
            json_mode,
            code=2,
        )

    raw_modules = modules_payload.get("modules", {})
    modules: list[dict[str, Any]] = []
    for module_id, value in sorted(raw_modules.items()):
        detail = value if isinstance(value, dict) else {"status": "offline", "error": "Invalid health payload"}
        modules.append({"id": module_id, **detail})
    result = {
        "status": suite.get("status", "unknown"),
        "service": suite.get("service", "suite_api"),
        "version": suite.get("version", "unknown"),
        "api_url": base_url,
        "latency_ms": round((time.monotonic() - started) * 1000, 1),
        "modules": modules,
    }
    if json_mode:
        print_result(result, True)
    else:
        print(f"Suite API: {result['status']} ({result['version']})")
        print(f"{'Module':<20} {'Status':<12} {'Latency':<12} Error")
        print("-" * 76)
        for module in modules:
            latency = module.get("response_time_ms")
            latency_text = f"{latency} ms" if latency is not None else "-"
            print(
                f"{module['id']:<20} {str(module.get('status', 'unknown')):<12} "
                f"{latency_text:<12} {module.get('error') or ''}"
            )

    if any(module.get("status") != "online" for module in modules):
        raise typer.Exit(code=1)


def install_command(
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Build the canonical local Compose services required by NeuroCLI."""
    if not json_mode:
        print("Building the NMTK Suite API, launcher control, and Jupyter services …")
    _compose(["build", *_CORE_SERVICES], json_mode, "compose_build_failed")
    print_result(
        {"status": "installed", "runtime": "compose", "services": list(_CORE_SERVICES)},
        json_mode,
    )


def run_command(
    wait_timeout: int = typer.Option(240, "--wait-timeout", min=1, help="Seconds to wait for healthy services"),
    api_url: str | None = typer.Option(None, "--api-url", help="Suite API base URL used for final verification"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Start the canonical backend services and wait until Suite API is healthy."""
    if not json_mode:
        print("Starting the NMTK backend services …")
    _compose(
        ["up", "-d", "--wait", "--wait-timeout", str(wait_timeout), *_CORE_SERVICES],
        json_mode,
        "compose_start_failed",
    )
    base_url = _api_url(api_url)
    try:
        response = httpx.get(f"{base_url}/api/suite/health", timeout=10.0)
        response.raise_for_status()
        health = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        error_exit(
            {
                "error": "suite_health_failed",
                "api_url": base_url,
                "message": "Compose started, but Suite API did not pass its health check.",
                "detail": str(exc),
            },
            json_mode,
            code=2,
        )
    print_result(
        {
            "status": "running",
            "runtime": "compose",
            "services": list(_CORE_SERVICES),
            "api_url": base_url,
            "suite": health,
        },
        json_mode,
    )
