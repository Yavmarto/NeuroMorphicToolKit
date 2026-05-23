"""neuro hub — Neurohub registry commands (login / push / pull / search).

Registry URL resolution order:
  1. --registry flag
  2. NEUROHUB_REGISTRY environment variable
  3. ~/.config/neurocli/hub.json
  4. http://localhost:8005 (Neurohub default from manifest)
"""

from __future__ import annotations

import json
import os
import stat
from pathlib import Path
from typing import Optional

import httpx
import typer

from neurocli.output import error_exit, print_result

hub_app = typer.Typer(help="Neurohub registry: login, push, pull, and search artefacts.")

_CONFIG_PATH = Path.home() / ".config" / "neurocli" / "hub.json"
_DEFAULT_REGISTRY = "http://localhost:8005"


def _load_credentials() -> dict[str, str] | None:
    if _CONFIG_PATH.exists():
        try:
            data = json.loads(_CONFIG_PATH.read_text())
            if isinstance(data, dict):
                return {str(k): str(v) for k, v in data.items()}
            return None
        except (json.JSONDecodeError, OSError):
            return None
    return None


def _resolve_registry(flag: str | None) -> str:
    if flag:
        return flag
    env = os.environ.get("NEUROHUB_REGISTRY")
    if env:
        return env
    creds = _load_credentials()
    if creds and "registry" in creds:
        return creds["registry"]
    return _DEFAULT_REGISTRY


# ---------------------------------------------------------------------------
# login
# ---------------------------------------------------------------------------


@hub_app.command("login")  # type: ignore[untyped-decorator]
def login(
    registry: Optional[str] = typer.Option(None, "--registry", "-r", help="Registry URL"),
    token: Optional[str] = typer.Option(None, "--token", help="JWT token (or set NEUROHUB_TOKEN)"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Authenticate with a Neurohub registry and store credentials."""
    url = _resolve_registry(registry)

    resolved_token = token or os.environ.get("NEUROHUB_TOKEN")
    if not resolved_token:
        if json_mode:
            error_exit({"error": "missing_token", "hint": "Pass --token or set NEUROHUB_TOKEN"}, json_mode, code=1)
        resolved_token = typer.prompt("Neurohub token", hide_input=True)

    _CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    payload = {"registry": url, "token": resolved_token}
    _CONFIG_PATH.write_text(json.dumps(payload))
    _CONFIG_PATH.chmod(stat.S_IRUSR | stat.S_IWUSR)  # 0o600

    print_result({"status": "ok", "registry": url}, json_mode)


# ---------------------------------------------------------------------------
# push
# ---------------------------------------------------------------------------


@hub_app.command("push")  # type: ignore[untyped-decorator]
def push(
    artefact_path: Path = typer.Argument(..., help="Path to artefact file to upload"),
    registry: Optional[str] = typer.Option(None, "--registry", "-r"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Push an artefact to the Neurohub registry."""
    if not artefact_path.exists():
        error_exit({"error": "file_not_found", "path": str(artefact_path)}, json_mode, code=1)

    creds = _load_credentials()
    if not creds or "token" not in creds:
        error_exit({"error": "not_logged_in", "hint": "Run `neuro hub login` first"}, json_mode, code=1)
        return  # unreachable but satisfies mypy

    url = _resolve_registry(registry)
    endpoint = f"{url}/api/v1/artefacts"
    headers = {"Authorization": f"Bearer {creds['token']}"}

    try:
        with artefact_path.open("rb") as fh:
            resp = httpx.post(endpoint, files={"file": fh}, headers=headers, timeout=30.0)
        resp.raise_for_status()
        print_result({"status": "pushed", "artefact": str(artefact_path), "registry": url}, json_mode)
    except httpx.ConnectError:
        error_exit({"error": "registry_unreachable", "registry": url}, json_mode, code=2)
    except httpx.HTTPStatusError as exc:
        error_exit({"error": "push_failed", "status_code": exc.response.status_code}, json_mode, code=2)


# ---------------------------------------------------------------------------
# pull
# ---------------------------------------------------------------------------


@hub_app.command("pull")  # type: ignore[untyped-decorator]
def pull(
    uri: str = typer.Argument(..., help="neurohub:// URI of the artefact"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Pull an artefact from the Neurohub registry (stub)."""
    if not uri.startswith("neurohub://"):
        error_exit({"error": "invalid_uri", "hint": "URI must start with neurohub://"}, json_mode, code=1)
    # Stub — full implementation follows the neurohub-global-registry spec
    print_result({"status": "not_implemented", "uri": uri}, json_mode)


# ---------------------------------------------------------------------------
# search
# ---------------------------------------------------------------------------


@hub_app.command("search")  # type: ignore[untyped-decorator]
def search(
    query: str = typer.Argument(..., help="Search query"),
    registry: Optional[str] = typer.Option(None, "--registry", "-r"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Search artefacts in the Neurohub registry."""
    url = _resolve_registry(registry)
    endpoint = f"{url}/api/v1/artefacts/search"

    creds = _load_credentials()
    headers = {"Authorization": f"Bearer {creds['token']}"} if creds and "token" in creds else {}

    try:
        resp = httpx.get(endpoint, params={"q": query}, headers=headers, timeout=10.0)
        resp.raise_for_status()
        data = resp.json()
        results = data.get("results", data) if isinstance(data, dict) else data
        if json_mode:
            print_result({"results": results}, json_mode)
        else:
            if not results:
                print("No results found.")
            else:
                for item in results:
                    print(f"  {item}")
    except httpx.ConnectError:
        error_exit({"error": "registry_unreachable", "registry": url}, json_mode, code=2)
    except httpx.HTTPStatusError as exc:
        error_exit({"error": "search_failed", "status_code": exc.response.status_code}, json_mode, code=2)
