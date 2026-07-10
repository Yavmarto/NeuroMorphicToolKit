"""Pure, stateless helpers shared by the PYNQ and Akida transport/provisioning
modules (and by the module-lifecycle orchestration in server.py).

Nothing here depends on ``server.py`` or any ``LauncherControlState`` — that
is what lets the hardware-specific modules import these directly instead of
reaching back into the façade module.
"""

from __future__ import annotations

import hashlib
import json
import os
import socket
import tempfile
import urllib.error
from collections.abc import Callable
from pathlib import Path
from typing import Any

from .config import MODULES_MANIFEST, REPO_ROOT


def _read_json_file(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return default


def _write_json_file(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")


def _module_root(module: dict[str, Any]) -> Path:
    install_path = module.get("installPath") or module.get("directory") or ""
    return (REPO_ROOT / install_path).resolve()


def _neurochip_module_root() -> Path:
    manifest = _read_json_file(MODULES_MANIFEST, [])
    if isinstance(manifest, list):
        for raw in manifest:
            if (
                isinstance(raw, dict)
                and str(raw.get("id") or "").strip() == "Neurochip"
            ):
                return _module_root(raw)
    return (REPO_ROOT / "Neurochip").resolve()


def _build_password_askpass_env(
    *,
    password: str,
    env_key: str,
    prefix: str,
) -> tuple[dict[str, str], Callable[[], None]]:
    askpass_handle = tempfile.NamedTemporaryFile(
        mode="w",
        encoding="utf-8",
        prefix=prefix,
        delete=False,
    )
    askpass_handle.write("#!/bin/sh\n")
    askpass_handle.write(f"printf '%s\\n' \"${env_key}\"\n")
    askpass_handle.close()
    os.chmod(askpass_handle.name, 0o700)

    env = os.environ.copy()
    env[env_key] = password
    env["SSH_ASKPASS"] = askpass_handle.name
    env["SSH_ASKPASS_REQUIRE"] = "force"
    env.setdefault("DISPLAY", "nmtk-launcher-control:0")

    def _cleanup_askpass() -> None:
        try:
            os.unlink(askpass_handle.name)
        except FileNotFoundError:
            return None

    return env, _cleanup_askpass


def _runtime_request_error_kind(exc: Exception) -> str:
    if isinstance(exc, (TimeoutError, socket.timeout)):
        return "timeout"
    if isinstance(exc, urllib.error.URLError) and isinstance(
        exc.reason, (TimeoutError, socket.timeout)
    ):
        return "timeout"
    return "unreachable"


def _hash_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        while True:
            chunk = handle.read(65536)
            if not chunk:
                break
            digest.update(chunk)
    return digest.hexdigest()
