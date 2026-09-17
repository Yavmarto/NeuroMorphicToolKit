"""Helpers for reading PYNQ runtime install-mode metadata."""

from __future__ import annotations

import importlib.metadata
import importlib.util
import json
import os
from pathlib import Path
from typing import Any

INSTALL_STATUS_PATH_ENV = "NEUROCHIP_PYNQ_INSTALL_STATUS_PATH"
INSTALL_MODE_ENV = "NEUROCHIP_PYNQ_INSTALL_MODE"
DEFAULT_INSTALL_STATUS_FILENAME = "install-status.json"


def install_status_path() -> Path:
    """Resolve the runtime install-status file path."""
    raw_path = os.getenv(INSTALL_STATUS_PATH_ENV, "").strip()
    if raw_path:
        return Path(raw_path)
    return Path.cwd() / DEFAULT_INSTALL_STATUS_FILENAME


def _runtime_package_details() -> dict[str, str]:
    details: dict[str, str] = {}
    try:
        details["currentAgentVersion"] = importlib.metadata.version("neurochip")
    except importlib.metadata.PackageNotFoundError:
        pass

    spec = importlib.util.find_spec("neurochip")
    origin = getattr(spec, "origin", None)
    if isinstance(origin, str) and origin.strip():
        details["currentPackagePath"] = origin
    return details


def read_install_status() -> dict[str, Any]:
    """Read the current board-local install mode metadata if available."""
    path = install_status_path()
    payload: dict[str, Any] = {}
    if path.exists():
        try:
            decoded = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            decoded = {}
        if isinstance(decoded, dict):
            payload.update(decoded)

    install_mode = (
        str(os.getenv(INSTALL_MODE_ENV) or payload.get("installMode") or "unknown").strip()
        or "unknown"
    )
    payload["installMode"] = install_mode
    payload["autoStartSupported"] = install_mode == "systemd"
    payload["statusPath"] = str(path)
    payload.update(_runtime_package_details())
    return payload
