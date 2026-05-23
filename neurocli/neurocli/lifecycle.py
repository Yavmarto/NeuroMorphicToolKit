"""neuro install / run / status — module lifecycle commands."""

from __future__ import annotations

import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any, Optional

import httpx
import typer

from neurocli.manifest import ManifestNotFoundError, find_module, load_manifest
from neurocli.output import error_exit, print_result

_REPO_ROOT = Path(__file__).parent.parent.parent  # neurocli/ -> repo root


# ---------------------------------------------------------------------------
# status
# ---------------------------------------------------------------------------


def status_command(
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Check health status of all NMTK modules."""
    try:
        modules = load_manifest(_REPO_ROOT)
    except ManifestNotFoundError as exc:
        error_exit({"error": "manifest_not_found", "detail": str(exc)}, json_mode, code=2)

    results: list[dict[str, Any]] = []
    for m in modules:
        if m.port is None:
            results.append({"id": m.id, "name": m.name, "status": "no-port", "port": None, "latency_ms": None})
            continue
        url = f"http://localhost:{m.port}{m.health_path}"
        t0 = time.monotonic()
        try:
            resp = httpx.get(url, timeout=2.0)
            latency = round((time.monotonic() - t0) * 1000, 1)
            status = "healthy" if resp.status_code < 400 else "unhealthy"
        except Exception:
            latency = None
            status = "unreachable"
        results.append({"id": m.id, "name": m.name, "status": status, "port": m.port, "latency_ms": latency})

    if json_mode:
        print_result({"modules": results}, json_mode)
    else:
        print(f"{'Module':<20} {'Status':<14} {'Port':<8} {'Latency'}")
        print("-" * 58)
        for r in results:
            lat = f"{r['latency_ms']} ms" if r["latency_ms"] is not None else "-"
            port = str(r["port"]) if r["port"] else "-"
            print(f"{r['name']:<20} {r['status']:<14} {port:<8} {lat}")


# ---------------------------------------------------------------------------
# install
# ---------------------------------------------------------------------------


def install_command(
    module_id: str = typer.Argument(..., help="Module ID from modules.json"),
    extras: Optional[str] = typer.Option(None, "--extras", help="Comma-separated extras (e.g. training,lava)"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Install an NMTK module via pip/uv."""
    try:
        modules = load_manifest(_REPO_ROOT)
    except ManifestNotFoundError as exc:
        error_exit({"error": "manifest_not_found", "detail": str(exc)}, json_mode, code=2)

    module = find_module(modules, module_id)
    if module is None:
        error_exit(
            {"error": "unknown_module", "module": module_id, "available": [m.id for m in modules]},
            json_mode,
            code=1,
        )

    install_path = (_REPO_ROOT / module.install_path).resolve()  # type: ignore[union-attr]
    all_extras = list(module.install_extras)  # type: ignore[union-attr]
    if extras:
        all_extras.extend(e.strip() for e in extras.split(",") if e.strip())

    extras_str = f"[{','.join(all_extras)}]" if all_extras else ""
    target = f"{install_path}{extras_str}"

    # Prefer uv, fall back to pip
    pip_cmd = "uv" if shutil.which("uv") else "pip"
    cmd: list[str]
    if pip_cmd == "uv":
        cmd = ["uv", "pip", "install", "-e", target]
    else:
        cmd = [sys.executable, "-m", "pip", "install", "-e", target]

    if not json_mode:
        print(f"Installing {module_id} from {install_path} …")

    try:
        subprocess.run(cmd, check=True)  # noqa: S603
    except subprocess.CalledProcessError as exc:
        error_exit({"error": "install_failed", "module": module_id, "returncode": exc.returncode}, json_mode, code=2)

    if json_mode:
        print_result({"status": "installed", "module": module_id}, json_mode)
    else:
        print(f"✓ {module_id} installed.")


# ---------------------------------------------------------------------------
# run
# ---------------------------------------------------------------------------


def run_command(
    module_id: str = typer.Argument(..., help="Module ID from modules.json"),
    port: Optional[int] = typer.Option(None, "--port", help="Override port from manifest"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Start an NMTK module backend via uvicorn."""
    try:
        modules = load_manifest(_REPO_ROOT)
    except ManifestNotFoundError as exc:
        error_exit({"error": "manifest_not_found", "detail": str(exc)}, json_mode, code=2)

    module = find_module(modules, module_id)
    if module is None:
        error_exit(
            {"error": "unknown_module", "module": module_id, "available": [m.id for m in modules]},
            json_mode,
            code=1,
        )

    if not module.uvicorn_target:  # type: ignore[union-attr]
        error_exit({"error": "no_uvicorn_target", "module": module_id}, json_mode, code=1)

    effective_port = port or module.port or 8000  # type: ignore[union-attr]
    cmd = [
        "uvicorn",
        module.uvicorn_target,  # type: ignore[union-attr]
        "--host", "0.0.0.0",
        "--port", str(effective_port),
    ]

    if not json_mode:
        print(f"Starting {module_id} on port {effective_port} …")
    subprocess.run(cmd, check=False)  # noqa: S603
