"""neuro hub — Neurohub Global Registry commands (login / push / pull / search).

Implements the CLI surface from ``.kiro/specs/neurohub-global-registry/design.md``
against the registry's ``/api/v1`` API. Registry URL resolution order:

  1. ``--registry`` flag
  2. ``NEUROHUB_REGISTRY`` environment variable
  3. ``~/.config/neurocli/hub.json``
  4. The Neurohub port from ``nmtk/neuro_toolkit/assets/modules.json``
  5. ``http://localhost:9000`` (final fallback)

Exit codes: 0 = success, 1 = user/input error (HTTP 401/403/409/422), 2 = runtime
/ infrastructure error (HTTP 5xx, network failure, checksum mismatch).
"""

from __future__ import annotations

import hashlib
import json
import os
import stat
import sys
from pathlib import Path
from typing import Any

import httpx
import typer

from neurocli.manifest import ManifestNotFoundError, find_module, load_manifest
from neurocli.output import error_exit, print_result
from neurocli.uri_parser import ArtefactType, URIParseError, parse_uri

hub_app = typer.Typer(help="Neurohub registry: login, push, pull, and search artefacts.")

_CONFIG_PATH = Path.home() / ".config" / "neurocli" / "hub.json"
_FALLBACK_REGISTRY = "http://localhost:9000"

MAX_DESCRIPTION_LEN = 1000
MAX_TAGS = 20

# Canonical download extension per artefact type, used for default pull filenames.
_TYPE_EXTENSION = {
    "snn_model": ".nir",
    "cnl_template": ".cnl",
    "cnlspace": ".cnlspace",
    "dataset": ".zip",
    "hardware_profile": ".json",
    "encoding_preset": ".json",
    "benchmark_baseline": ".json",
    "custom_node": ".py",
    "benchmark_result": ".json",
}


def _load_credentials() -> dict[str, str] | None:
    """Load stored registry credentials, or ``None`` if absent/unreadable."""
    if _CONFIG_PATH.exists():
        try:
            data = json.loads(_CONFIG_PATH.read_text())
            if isinstance(data, dict):
                return {str(k): str(v) for k, v in data.items()}
            return None
        except (json.JSONDecodeError, OSError):
            return None
    return None


def _manifest_registry() -> str | None:
    """Resolve the Neurohub base URL from the launcher manifest, if available."""
    try:
        modules = load_manifest(Path.cwd())
    except (ManifestNotFoundError, OSError, json.JSONDecodeError):
        return None
    entry = find_module(modules, "Neurohub")
    if entry is not None and entry.port is not None:
        return f"http://localhost:{entry.port}"
    return None


def _resolve_registry(flag: str | None) -> str:
    """Resolve the registry base URL following the documented precedence order."""
    if flag:
        return flag.rstrip("/")
    env = os.environ.get("NEUROHUB_REGISTRY")
    if env:
        return env.rstrip("/")
    creds = _load_credentials()
    if creds and "registry" in creds:
        return creds["registry"].rstrip("/")
    manifest_url = _manifest_registry()
    if manifest_url:
        return manifest_url
    return _FALLBACK_REGISTRY


def _auth_headers() -> dict[str, str]:
    """Return the Authorization header from stored credentials, if logged in."""
    creds = _load_credentials()
    if creds and "token" in creds:
        return {"Authorization": f"Bearer {creds['token']}"}
    return {}


def _status_to_exit(status_code: int) -> int:
    """Map an HTTP status code to a CLI exit code (1 = user, 2 = infrastructure)."""
    return 2 if status_code >= 500 else 1


def _request(
    method: str,
    url: str,
    error_msg: str,
    json_mode: bool,
    registry_url: str,
    **kwargs: Any,
) -> httpx.Response:
    """Make an HTTP request and handle connection and HTTP status errors cleanly."""
    try:
        req_func = getattr(httpx, method.lower())
        resp = req_func(url, **kwargs)
        resp.raise_for_status()
        return resp
    except httpx.RequestError:
        error_exit({"error": "registry_unreachable", "registry": registry_url}, json_mode, code=2)
        raise  # Unreachable, error_exit calls sys.exit
    except httpx.HTTPStatusError as exc:
        error_exit(
            {"error": error_msg, "status_code": exc.response.status_code},
            json_mode,
            code=_status_to_exit(exc.response.status_code),
        )
        raise


# ---------------------------------------------------------------------------
# login
# ---------------------------------------------------------------------------


@hub_app.command("login")
def login(
    registry: str | None = typer.Option(None, "--registry", "-r", help="Registry URL"),
    username: str | None = typer.Option(None, "--username", "-u", help="Account username"),
    password: str | None = typer.Option(None, "--password", help="Account password"),
    token: str | None = typer.Option(None, "--token", help="Use an existing JWT directly"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Authenticate with a Neurohub registry and store the JWT credentials."""
    url = _resolve_registry(registry)

    # Direct-token path: store the supplied token without contacting the registry.
    resolved_token = token or os.environ.get("NEUROHUB_TOKEN")
    if resolved_token:
        _write_credentials(url, resolved_token)
        print_result({"status": "ok", "registry": url}, json_mode)
        return

    resolved_user = username or os.environ.get("NEUROHUB_USER")
    resolved_pass = password or os.environ.get("NEUROHUB_PASSWORD")
    if not resolved_user:
        if json_mode:
            error_exit({"error": "missing_username"}, json_mode, code=1)
        resolved_user = typer.prompt("Neurohub username")
    if not resolved_pass:
        if json_mode:
            error_exit({"error": "missing_password"}, json_mode, code=1)
        resolved_pass = typer.prompt("Neurohub password", hide_input=True)

    resp = _request(
        "POST",
        f"{url}/api/v1/auth/login",
        "login_failed",
        json_mode,
        url,
        json={"username": resolved_user, "password": resolved_pass},
        timeout=10.0,
    )

    access_token = resp.json().get("access_token")
    if not access_token:
        error_exit({"error": "no_token_in_response"}, json_mode, code=2)
        return
    _write_credentials(url, access_token)
    print_result({"status": "ok", "registry": url}, json_mode)


def _write_credentials(registry: str, token: str) -> None:
    """Persist credentials to ``~/.config/neurocli/hub.json`` with mode 0o600."""
    _CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
    _CONFIG_PATH.write_text(json.dumps({"registry": registry, "token": token}))
    _CONFIG_PATH.chmod(stat.S_IRUSR | stat.S_IWUSR)


# ---------------------------------------------------------------------------
# push
# ---------------------------------------------------------------------------


@hub_app.command("push")
def push(
    artefact_path: Path = typer.Argument(..., help="Path to the artefact file to upload"),
    type: str = typer.Option(..., "--type", "-t", help="Artefact type"),
    slug: str = typer.Option(..., "--slug", "-s", help="Artefact slug"),
    version: str = typer.Option(..., "--version", "-v", help="Semantic version MAJOR.MINOR.PATCH"),
    description: str | None = typer.Option(None, "--description", "-d"),
    tag: list[str] | None = typer.Option(None, "--tag", help="Tag (repeatable, up to 20)"),
    registry: str | None = typer.Option(None, "--registry", "-r"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Push an artefact to the Neurohub registry and print its canonical URI."""
    if not artefact_path.exists():
        error_exit({"error": "file_not_found", "path": str(artefact_path)}, json_mode, code=1)

    valid_types = {t.value for t in ArtefactType}
    if type not in valid_types:
        error_exit(
            {"error": "invalid_type", "type": type, "valid": sorted(valid_types)},
            json_mode,
            code=1,
        )
    if description is not None and len(description) > MAX_DESCRIPTION_LEN:
        error_exit({"error": "description_too_long", "max": MAX_DESCRIPTION_LEN}, json_mode, code=1)
    tags = tag or []
    if len(tags) > MAX_TAGS:
        error_exit({"error": "too_many_tags", "max": MAX_TAGS}, json_mode, code=1)

    creds = _load_credentials()
    if not creds or "token" not in creds:
        error_exit({"error": "not_logged_in", "hint": "Run `neuro hub login` first"}, json_mode, code=1)
        return

    url = _resolve_registry(registry)
    data: dict[str, str] = {"type": type, "slug": slug, "version": version}
    if description:
        data["description"] = description
    if tags:
        data["tags"] = ",".join(tags)

    with artefact_path.open("rb") as fh:
        resp = _request(
            "POST",
            f"{url}/api/v1/artefacts",
            "push_failed",
            json_mode,
            url,
            data=data,
            files={"file": (artefact_path.name, fh)},
            headers=_auth_headers(),
            timeout=60.0,
        )

    uri = resp.json().get("neurohub_uri", "")
    print_result({"status": "pushed", "uri": uri, "registry": url}, json_mode)


# ---------------------------------------------------------------------------
# pull
# ---------------------------------------------------------------------------


@hub_app.command("pull")
def pull(
    uri: str = typer.Argument(..., help="neurohub:// URI of the artefact"),
    output: Path | None = typer.Option(None, "--output", "-o", help="Output file path"),
    registry: str | None = typer.Option(None, "--registry", "-r"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Pull an artefact, verifying its SHA-256 checksum after download."""
    try:
        parsed = parse_uri(uri)
    except URIParseError as exc:
        error_exit({"error": "invalid_uri", "detail": str(exc)}, json_mode, code=1)
        return

    base = _resolve_registry(registry)
    path = f"/api/v1/artefacts/{parsed.owner}/{parsed.slug}"
    if parsed.version is not None:
        path = f"{path}/{parsed.version}"

    meta_resp = _request(
        "GET",
        f"{base}{path}",
        "artefact_not_found",
        json_mode,
        base,
        headers=_auth_headers(),
        timeout=30.0,
    )

    meta = meta_resp.json()
    expected_sha = str(meta.get("sha256") or "")
    if len(expected_sha) != 64:
        error_exit(
            {
                "error": "missing_checksum",
                "message": "The registry did not provide a valid SHA-256 checksum; no file was downloaded.",
            },
            json_mode,
            code=2,
        )
    resolved_version = meta.get("version", parsed.version or "latest")
    download_url = meta.get("download_url")
    if not download_url:
        error_exit({"error": "no_download_url"}, json_mode, code=2)
        return

    blob_resp = _request(
        "GET",
        f"{base}{download_url}",
        "download_failed",
        json_mode,
        base,
        headers=_auth_headers(),
        timeout=120.0,
        follow_redirects=True,
    )

    blob = blob_resp.content
    ext = _TYPE_EXTENSION.get(parsed.type.value, "")
    dest = output or Path(f"{parsed.slug}@{resolved_version}{ext}")
    dest.write_bytes(blob)

    actual_sha = hashlib.sha256(blob).hexdigest()
    if actual_sha != expected_sha:
        dest.unlink(missing_ok=True)
        msg = {
            "error": "checksum_mismatch",
            "expected": expected_sha,
            "actual": actual_sha,
        }
        if json_mode:
            print(json.dumps(msg, indent=2), file=sys.stderr)
        else:
            print(f"  checksum mismatch: expected {expected_sha}, got {actual_sha}", file=sys.stderr)
        sys.exit(2)

    print_result({"status": "pulled", "path": str(dest), "sha256": actual_sha, "uri": uri}, json_mode)


# ---------------------------------------------------------------------------
# search
# ---------------------------------------------------------------------------


@hub_app.command("search")
def search(
    query: str = typer.Argument(..., help="Search query"),
    type: str | None = typer.Option(None, "--type", "-t", help="Filter by artefact type"),
    hardware: str | None = typer.Option(None, "--hardware", help="Filter by hardware target"),
    limit: int = typer.Option(20, "--limit", "-l", help="Max results (1-100)"),
    registry: str | None = typer.Option(None, "--registry", "-r"),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Search artefacts in the Neurohub registry."""
    capped_limit = max(1, min(limit, 100))
    url = _resolve_registry(registry)
    params: dict[str, str | int] = {"q": query, "page_size": capped_limit}
    if type:
        params["type"] = type
    if hardware:
        params["hardware_target"] = hardware

    resp = _request(
        "GET",
        f"{url}/api/v1/search",
        "search_failed",
        json_mode,
        url,
        params=params,
        headers=_auth_headers(),
        timeout=10.0,
    )

    data = resp.json()
    items = data.get("items", []) if isinstance(data, dict) else data
    if json_mode:
        print_result({"items": items, "search_degraded": data.get("search_degraded", False)}, json_mode)
        return

    if not items:
        print("No results found.")
        return
    print(f"  {'NAME':<24} {'TYPE':<18} {'OWNER':<16} {'VERSION':<10} RATING")
    for item in items:
        print(
            f"  {item.get('slug', ''):<24} {item.get('type', ''):<18} "
            f"{item.get('owner', ''):<16} {item.get('version', ''):<10} "
            f"{item.get('average_rating', 0)}"
        )
