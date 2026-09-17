"""Pure, stateless module-descriptor and environment-check helpers.

Used by module_lifecycle.py (install/update/preflight orchestration) and
suite_api_service.py (PreflightResult). Nothing here depends on `server.py`
or any `LauncherControlState` instance state.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

import tomllib
from packaging.specifiers import SpecifierSet
from packaging.version import InvalidVersion
from packaging.version import parse as parse_version

from .config import REPO_ROOT
from .runtime_shared import _module_root
from .suite_api_service import DEFAULT_SUITE_API_PORT


def _module_install_dir(module: dict[str, Any]) -> Path:
    source_path = module.get("sourcePath") or "."
    return (_module_root(module) / source_path).resolve()


def _module_run_dir(module: dict[str, Any]) -> Path:
    run_path = module.get("runPath") or module.get("sourcePath") or "."
    return (_module_root(module) / run_path).resolve()


def _module_venv_python(module: dict[str, Any]) -> Path:
    """Return the python path, checking .venv (poetry in-project) before venv."""
    install_dir = _module_install_dir(module)
    if os.name == "nt":
        dotenv = install_dir / ".venv" / "Scripts" / "python.exe"
        return (
            dotenv
            if dotenv.exists()
            else install_dir / "venv" / "Scripts" / "python.exe"
        )
    dotenv = install_dir / ".venv" / "bin" / "python"
    return dotenv if dotenv.exists() else install_dir / "venv" / "bin" / "python"


def _module_venv_pip(module: dict[str, Any]) -> Path:
    install_dir = _module_install_dir(module)
    if os.name == "nt":
        dotenv = install_dir / ".venv" / "Scripts" / "pip.exe"
        return (
            dotenv if dotenv.exists() else install_dir / "venv" / "Scripts" / "pip.exe"
        )
    dotenv = install_dir / ".venv" / "bin" / "pip"
    return dotenv if dotenv.exists() else install_dir / "venv" / "bin" / "pip"


def _module_pyproject_path(module: dict[str, Any]) -> Path | None:
    install_dir = _module_install_dir(module)
    module_root = _module_root(module)
    for candidate in (
        install_dir / "pyproject.toml",
        module_root / "pyproject.toml",
    ):
        if candidate.exists():
            return candidate
    return None


def _module_uses_poetry(module: dict[str, Any]) -> bool:
    pyproject_path = _module_pyproject_path(module)
    if pyproject_path is None:
        return False

    try:
        pyproject = tomllib.loads(pyproject_path.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError):
        return False

    build_backend = str(
        pyproject.get("build-system", {}).get("build-backend", "")
    ).strip()
    tool_table = pyproject.get("tool", {})
    return build_backend == "poetry.core.masonry.api" or "poetry" in tool_table


def _poetry_fallback_env_root(module: dict[str, Any]) -> Path:
    module_id = str(module.get("id") or "").strip()
    return REPO_ROOT / ".poetry-envs" / module_id


def _poetry_command() -> str | None:
    found = shutil.which("poetry")
    if found:
        return found
    # Poetry is commonly installed outside the system PATH.
    # Probe well-known locations so the control service works even when
    # launched by Flutter (which inherits a minimal environment).
    candidates = [
        Path.home() / ".local" / "bin" / "poetry",
        Path.home() / ".poetry" / "bin" / "poetry",
        # pipx default bin dir
        Path.home() / ".local" / "pipx" / "venvs" / "poetry" / "bin" / "poetry",
    ]
    for candidate in candidates:
        if candidate.exists() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def _poetry_env_python(module: dict[str, Any]) -> Path | None:
    if not _module_uses_poetry(module):
        return None

    install_dir = _module_install_dir(module)

    # Check in-project .venv first (set by poetry config virtualenvs.in-project true).
    # This is the most reliable path and requires no subprocess call.
    if os.name == "nt":
        inproject_python = install_dir / ".venv" / "Scripts" / "python.exe"
    else:
        inproject_python = install_dir / ".venv" / "bin" / "python"
    if inproject_python.exists():
        return inproject_python

    fallback_env_root = _poetry_fallback_env_root(module)
    if os.name == "nt":
        fallback_python = fallback_env_root / "Scripts" / "python.exe"
    else:
        fallback_python = fallback_env_root / "bin" / "python"
    if fallback_python.exists():
        return fallback_python

    poetry = _poetry_command()
    if poetry is None:
        return None

    result = subprocess.run(
        [poetry, "env", "info", "--path"],
        cwd=install_dir,
        capture_output=True,
        text=True,
        check=False,
    )
    env_path = Path((result.stdout or "").strip())
    if result.returncode != 0 or not env_path:
        return None

    if os.name == "nt":
        python_path = env_path / "Scripts" / "python.exe"
    else:
        python_path = env_path / "bin" / "python"
    return python_path if python_path.exists() else None


def _module_python_path(module: dict[str, Any]) -> Path:
    return _poetry_env_python(module) or _module_venv_python(module)


def _missing_python_message(module: dict[str, Any], python_path: Path) -> str:
    if _module_uses_poetry(module):
        return f"Module python missing at {python_path}"
    return f"Virtualenv python missing at {python_path}"


def _module_environment_exists(module: dict[str, Any]) -> bool:
    return _module_python_path(module).exists()


def _effective_port(module: dict[str, Any]) -> int | None:
    custom = module.get("customPort")
    if isinstance(custom, int):
        return custom
    port = module.get("port")
    return port if isinstance(port, int) else None


def _current_platform_key() -> str:
    if sys.platform.startswith("linux"):
        return "linux"
    if sys.platform.startswith(("win32", "cygwin")):
        return "windows"
    if sys.platform == "darwin":
        return "macos"
    return sys.platform


def _normalize_standalone_cpython(raw: Any) -> dict[str, Any] | None:
    """Validate the pinned interpreter the Akida install script may download.

    All four fields are required: without the checksum the download could not
    be verified, and without the URL there is nothing to fetch. A partial entry
    returns None so provisioning reports "no automatic download is configured"
    — an actionable message — rather than failing mid-install.
    """
    if not isinstance(raw, dict):
        return None
    version = str(raw.get("version") or "").strip()
    url = str(raw.get("url") or "").strip()
    sha256 = str(raw.get("sha256") or "").strip()
    architecture = str(raw.get("architecture") or "x86_64").strip()
    if not version or not url or not sha256 or not architecture:
        return None
    return {
        "version": version,
        "architecture": architecture,
        "url": url,
        "sha256": sha256,
    }


def _normalize_akida_runtime_config(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    return {
        "supportedPlatforms": [
            str(value).strip()
            for value in raw.get("supportedPlatforms", [])
            if str(value).strip()
        ],
        "pythonRange": str(raw.get("pythonRange") or ">=3.10,<3.13").strip(),
        # This rebuild is a whitelist, so any manifest key not named here is
        # dropped before it ever reaches provisioning.
        "standaloneCPython": _normalize_standalone_cpython(
            raw.get("standaloneCPython")
        ),
        "requiredPackages": [
            str(value).strip()
            for value in raw.get("requiredPackages", [])
            if str(value).strip()
        ],
        "docsUrl": str(raw.get("docsUrl") or "").strip(),
        "localModeFallback": str(
            raw.get("localModeFallback") or "simulator_only"
        ).strip(),
    }


def _normalize_akida_runtime_state(raw: Any) -> dict[str, Any] | None:
    if not isinstance(raw, dict):
        return None
    status = str(raw.get("status") or "").strip()
    if not status:
        return None
    return {
        "status": status,
        "message": str(raw.get("message") or "").strip() or None,
        "preparedAt": str(raw.get("preparedAt") or "").strip() or None,
    }


def _version_matches_range(version: str, version_range: str) -> bool:
    try:
        parsed_version = parse_version(version)
        specifiers = SpecifierSet(version_range)
        return parsed_version in specifiers
    except InvalidVersion:
        return False


def _uvicorn_host() -> str:
    host = os.environ.get("NMTK_UVICORN_HOST", "0.0.0.0").strip()
    return host or "0.0.0.0"


def _module_install_strategy(module: dict[str, Any]) -> str:
    strategy = str(module.get("installStrategy", "pip")).strip().lower()
    return strategy or "pip"


def _module_start_strategy(module: dict[str, Any]) -> str:
    if not module.get("uvicornTarget"):
        return "none"
    strategy = str(module.get("startStrategy", "uvicorn")).strip().lower()
    return strategy or "uvicorn"


def _is_externally_managed_service(module: dict[str, Any]) -> bool:
    """Return True for 'none'-strategy modules that live on their own port.

    These are services started outside the launcher (e.g. via Docker Compose)
    rather than monolith modules whose traffic is proxied through suite_api on
    DEFAULT_SUITE_API_PORT.  Jupyter and lava_backend are examples.
    """
    if _module_start_strategy(module) != "none":
        return False
    port = _effective_port(module)
    return port is not None and port != DEFAULT_SUITE_API_PORT


def _external_service_health_url(
    module: dict[str, Any], host: str = "127.0.0.1"
) -> str:
    """Build the health-probe URL for an externally managed service.

    Args:
        module: Module configuration dict.
        host: Hostname or IP to probe. Defaults to 127.0.0.1 for local deployment;
              should be set to the remote hostname when the service runs on a remote host.
    """
    port = _effective_port(module)
    deployment = module.get("deployment") or {}
    probe_host = deployment.get("internalProbeHost") or host
    raw_path = deployment.get("healthPath", "") if isinstance(deployment, dict) else ""
    health_path = str(raw_path).strip() or "/health"
    return f"http://{probe_host}:{port}{health_path}"


def _normalized_import_list(raw: Any) -> list[str]:
    if not isinstance(raw, list):
        return []
    imports: list[str] = []
    for item in raw:
        if isinstance(item, str):
            value = item.strip()
            if value:
                imports.append(value)
    return imports


def _module_required_imports(module: dict[str, Any]) -> list[str]:
    imports = _normalized_import_list(module.get("requiredImports"))
    uvicorn_target = str(module.get("uvicornTarget", "")).strip()
    app_module = uvicorn_target.split(":", 1)[0] if uvicorn_target else ""
    if app_module and app_module not in imports:
        imports.append(app_module)
    return imports


def _module_optional_imports(module: dict[str, Any]) -> list[str]:
    return _normalized_import_list(module.get("optionalImports"))


def _module_install_extras(module: dict[str, Any]) -> list[str]:
    return _normalized_import_list(module.get("installExtras"))


def _candidate_environment_files(module: dict[str, Any]) -> list[Path]:
    module_root = _module_root(module)
    install_dir = _module_install_dir(module)
    candidates = [
        install_dir / "pyproject.toml",
        module_root / "pyproject.toml",
        install_dir / "poetry.lock",
        module_root / "poetry.lock",
        install_dir / "requirements.txt",
        module_root / "requirements.txt",
        module_root / "backend" / "requirements.txt",
        install_dir / "requirements-dev.txt",
        module_root / "requirements-dev.txt",
    ]
    seen: set[Path] = set()
    existing: list[Path] = []
    for candidate in candidates:
        if candidate.exists() and candidate not in seen:
            seen.add(candidate)
            existing.append(candidate)
    return existing
