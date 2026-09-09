"""`neuro backend ...` — every backend action the launcher app can perform.

The app and the CLI hit the same two services (launcher-control and Suite API)
over the same authenticated session, so parity is kept by listing the endpoints
once in ROUTES and materialising one command per entry. Adding an endpoint to
the app means adding one line here, not a new command implementation.
"""

from __future__ import annotations

import getpass
import json
import os
import re
from dataclasses import dataclass
from pathlib import Path

import httpx
import typer

from neurocli.output import error_exit, print_result
from neurocli.session import (
    Backend,
    SessionError,
    app_targets,
    keychain_delete,
    keychain_write,
    open_backend,
    resolve_target,
)

_PATH_PARAM = re.compile(r"\{(\w+)\}")


@dataclass(frozen=True)
class Route:
    """One backend endpoint, exposed as `neuro backend <group> <name>`."""

    group: str
    name: str
    method: str
    path: str
    service: str = "launcher"
    summary: str = ""
    stream: bool = False

    @property
    def params(self) -> list[str]:
        return _PATH_PARAM.findall(self.path)


# Mirrors the launcher app's control_api_service.dart plus the Suite API
# endpoints its module screens call. Keep in step with both.
ROUTES: tuple[Route, ...] = (
    # ── modules ────────────────────────────────────────────────────────────
    Route("modules", "list", "GET", "/api/launcher/modules", summary="List every module with install and run state"),
    Route("modules", "show", "GET", "/api/launcher/modules/{module_id}", summary="Show one module"),
    Route("modules", "logs", "GET", "/api/launcher/modules/{module_id}/logs", summary="Read a module's recent log lines"),
    Route("modules", "install", "POST", "/api/launcher/modules/{module_id}/install", summary="Install a module"),
    Route("modules", "start", "POST", "/api/launcher/modules/{module_id}/start", summary="Start a module"),
    Route("modules", "stop", "POST", "/api/launcher/modules/{module_id}/stop", summary="Stop a module"),
    Route("modules", "uninstall", "POST", "/api/launcher/modules/{module_id}/uninstall", summary="Uninstall a module"),
    Route("modules", "update", "POST", "/api/launcher/modules/{module_id}/update", summary="Update a module"),
    Route("modules", "repair", "POST", "/api/launcher/modules/{module_id}/repair", summary="Repair a broken module install"),
    Route("modules", "settings", "PUT", "/api/launcher/modules/{module_id}/settings", summary="Change a module's settings"),
    Route(
        "modules",
        "prepare-akida-runtime",
        "POST",
        "/api/launcher/modules/{module_id}/akida-runtime/prepare",
        summary="Prepare the Akida runtime for a module",
    ),
    # ── launcher itself ────────────────────────────────────────────────────
    Route("launcher", "health", "GET", "/health", summary="Check launcher control is answering"),
    Route("launcher", "doctor", "GET", "/api/launcher/doctor", summary="Run the launcher's self-diagnosis"),
    Route("launcher", "settings", "GET", "/api/launcher/settings", summary="Read launcher settings"),
    Route("launcher", "set-settings", "PUT", "/api/launcher/settings", summary="Write launcher settings"),
    Route("launcher", "logs", "GET", "/api/launcher/logs", summary="Read launcher logs"),
    Route("launcher", "crash-log", "GET", "/api/launcher/crash-log", summary="Read the last crash report"),
    Route("launcher", "activity-log", "GET", "/api/launcher/backend-activity-log", summary="Read backend activity"),
    Route("launcher", "discover-hardware", "POST", "/api/launcher/hardware/discover", summary="Rescan for local hardware"),
    # ── launcher auth ────────────────────────────────────────────────────────
    Route("auth", "login", "POST", "/api/launcher/auth/login", summary="Authenticate with the launcher's admin password"),
    Route("auth", "introspect", "GET", "/api/launcher/auth/introspect", summary="Check whether a bearer session token is still live"),
    # ── workspace ──────────────────────────────────────────────────────────
    Route("workspace", "show", "GET", "/api/launcher/workspace", summary="Read the active workspace"),
    Route("workspace", "set", "PUT", "/api/launcher/workspace", summary="Change the active workspace"),
    Route("workspace", "open-session", "POST", "/api/launcher/workspace/sessions", summary="Open a module session"),
    Route(
        "workspace",
        "close-session",
        "DELETE",
        "/api/launcher/workspace/sessions/{module_id}",
        summary="Close a module session",
    ),
    # ── backend deployment ─────────────────────────────────────────────────
    Route("deployment", "targets", "GET", "/api/launcher/deployment/targets", summary="List deployment targets"),
    Route("deployment", "add-target", "POST", "/api/launcher/deployment/targets", summary="Add a deployment target"),
    Route(
        "deployment",
        "update-target",
        "PUT",
        "/api/launcher/deployment/targets/{target_id}",
        summary="Change a deployment target",
    ),
    Route(
        "deployment",
        "remove-target",
        "DELETE",
        "/api/launcher/deployment/targets/{target_id}",
        summary="Remove a deployment target",
    ),
    Route("deployment", "preflight", "POST", "/api/launcher/deployment/preflight", summary="Check a target before deploying"),
    Route(
        "deployment",
        "bootstrap-remote-user",
        "POST",
        "/api/launcher/deployment/bootstrap-remote-user",
        summary="Create the isolated deploy account on a host",
    ),
    Route("deployment", "deploy", "POST", "/api/launcher/deployment/jobs", summary="Start a deployment job"),
    Route("deployment", "job", "GET", "/api/launcher/deployment/jobs/{job_id}", summary="Show a deployment job"),
    Route(
        "deployment",
        "watch",
        "GET",
        "/api/launcher/deployment/jobs/{job_id}/events",
        summary="Follow a deployment job's live progress",
        stream=True,
    ),
    Route("deployment", "cancel", "POST", "/api/launcher/deployment/jobs/{job_id}/cancel", summary="Cancel a deployment job"),
    Route("deployment", "retry", "POST", "/api/launcher/deployment/jobs/{job_id}/retry", summary="Retry a deployment job"),
    # ── Akida hosts ────────────────────────────────────────────────────────
    Route("akida", "hosts", "GET", "/api/launcher/akida/hosts", summary="List Akida hosts"),
    Route("akida", "add-host", "POST", "/api/launcher/akida/hosts", summary="Add an Akida host"),
    Route("akida", "host", "GET", "/api/launcher/akida/hosts/{host_id}", summary="Show an Akida host"),
    Route("akida", "update-host", "PUT", "/api/launcher/akida/hosts/{host_id}", summary="Change an Akida host"),
    Route("akida", "remove-host", "DELETE", "/api/launcher/akida/hosts/{host_id}", summary="Remove an Akida host"),
    Route("akida", "test", "POST", "/api/launcher/akida/hosts/{host_id}/connectivity-test", summary="Test the connection"),
    Route("akida", "provision", "POST", "/api/launcher/akida/hosts/{host_id}/provision", summary="Provision the host"),
    Route("akida", "repair", "POST", "/api/launcher/akida/hosts/{host_id}/repair", summary="Repair the host runtime"),
    Route(
        "akida",
        "restart-services",
        "POST",
        "/api/launcher/akida/hosts/{host_id}/restart-services",
        summary="Restart the host's services",
    ),
    Route("akida", "preflight", "POST", "/api/launcher/akida/hosts/{host_id}/preflight", summary="Pre-flight the host"),
    Route("akida", "status", "GET", "/api/launcher/akida/hosts/{host_id}/status", summary="Show host status"),
    Route(
        "akida",
        "update-runtime",
        "POST",
        "/api/launcher/akida/hosts/{host_id}/runtime-update-jobs",
        summary="Start a runtime update",
    ),
    Route(
        "akida",
        "runtime-update",
        "GET",
        "/api/launcher/akida/hosts/{host_id}/runtime-update-jobs/{job_id}",
        summary="Show a runtime update job",
    ),
    Route("akida", "map", "POST", "/api/launcher/akida/hosts/{host_id}/map", summary="Map a model onto the device"),
    Route("akida", "run", "POST", "/api/launcher/akida/hosts/{host_id}/run", summary="Run a model on the device"),
    Route("akida", "submit-model", "POST", "/api/launcher/akida/hosts/{host_id}/model-jobs", summary="Submit a model job"),
    Route(
        "akida",
        "model-job",
        "GET",
        "/api/launcher/akida/hosts/{host_id}/model-jobs/{job_id}",
        summary="Show a model job",
    ),
    Route(
        "akida",
        "inference",
        "POST",
        "/api/launcher/akida/hosts/{host_id}/models/{model_id}/inference",
        summary="Run inference on a mapped model",
    ),
    Route(
        "akida",
        "benchmark",
        "POST",
        "/api/launcher/akida/hosts/{host_id}/models/{model_id}/benchmark",
        summary="Benchmark a mapped model",
    ),
    Route(
        "akida",
        "visualize",
        "POST",
        "/api/launcher/akida/hosts/{host_id}/models/{model_id}/visualization",
        summary="Render a model visualisation",
    ),
    # ── PYNQ boards ────────────────────────────────────────────────────────
    Route("pynq", "boards", "GET", "/api/launcher/pynq/boards", summary="List PYNQ boards"),
    Route("pynq", "add-board", "POST", "/api/launcher/pynq/boards", summary="Add a PYNQ board"),
    Route("pynq", "board", "GET", "/api/launcher/pynq/boards/{board_id}", summary="Show a PYNQ board"),
    Route("pynq", "update-board", "PUT", "/api/launcher/pynq/boards/{board_id}", summary="Change a PYNQ board"),
    Route("pynq", "remove-board", "DELETE", "/api/launcher/pynq/boards/{board_id}", summary="Remove a PYNQ board"),
    Route("pynq", "test", "POST", "/api/launcher/pynq/boards/{board_id}/connectivity-test", summary="Test the connection"),
    Route("pynq", "provision", "POST", "/api/launcher/pynq/boards/{board_id}/provision", summary="Provision the board"),
    Route(
        "pynq",
        "install-overlay",
        "POST",
        "/api/launcher/pynq/boards/{board_id}/install-overlay",
        summary="Install an overlay",
    ),
    Route(
        "pynq",
        "restart-runtime",
        "POST",
        "/api/launcher/pynq/boards/{board_id}/restart-runtime",
        summary="Restart the board runtime",
    ),
    Route("pynq", "preflight", "POST", "/api/launcher/pynq/boards/{board_id}/preflight", summary="Pre-flight the board"),
    Route("pynq", "status", "GET", "/api/launcher/pynq/boards/{board_id}/status", summary="Show board status"),
    Route(
        "pynq",
        "runtime-status",
        "GET",
        "/api/launcher/pynq/boards/{board_id}/runtime-status",
        summary="Show the board runtime status",
    ),
    Route("pynq", "deploy", "POST", "/api/launcher/pynq/boards/{board_id}/deploy", summary="Deploy a package to the board"),
    Route("pynq", "verify", "POST", "/api/launcher/pynq/boards/{board_id}/verify", summary="Verify a board deployment"),
    Route("pynq", "run", "POST", "/api/launcher/pynq/boards/{board_id}/run", summary="Run a model on the board"),
    # ── Suite API ──────────────────────────────────────────────────────────
    Route("suite", "health", "GET", "/api/suite/health", service="suite", summary="Suite API health"),
    Route("suite", "modules", "GET", "/api/suite/health/modules", service="suite", summary="Per-module Suite API health"),
    Route("suite", "doctor", "POST", "/api/suite/doctor", service="suite", summary="Run the Suite API doctor"),
    Route(
        "suite",
        "simulate-prosthetic",
        "POST",
        "/api/neurocnl/prosthetic/simulate",
        service="suite",
        summary="Run a prosthetic simulation",
    ),
    # ── Jupyter / environments ─────────────────────────────────────────────
    Route("jupyter", "url", "GET", "/api/jupyter/url", service="suite", summary="Get the notebook server URL"),
    Route("jupyter", "health", "GET", "/api/jupyter/health", service="suite", summary="Notebook server health"),
    Route("jupyter", "doctor", "POST", "/api/jupyter/doctor", service="suite", summary="Diagnose the notebook server"),
    Route("jupyter", "environments", "GET", "/api/jupyter/environments", service="suite", summary="List environments"),
    Route(
        "jupyter",
        "create-environment",
        "POST",
        "/api/jupyter/environments",
        service="suite",
        summary="Create an environment",
    ),
    Route(
        "jupyter",
        "delete-environment",
        "DELETE",
        "/api/jupyter/environments/{slug}",
        service="suite",
        summary="Delete an environment",
    ),
    Route(
        "jupyter",
        "packages",
        "GET",
        "/api/jupyter/environments/{slug}/packages",
        service="suite",
        summary="List installed packages",
    ),
    Route(
        "jupyter",
        "install-package",
        "POST",
        "/api/jupyter/environments/{slug}/packages",
        service="suite",
        summary="Install a package",
    ),
    Route(
        "jupyter",
        "requirements",
        "GET",
        "/api/jupyter/environments/{slug}/requirements",
        service="suite",
        summary="Read an environment's requirements",
    ),
    Route("jupyter", "execute", "POST", "/api/jupyter/executions", service="suite", summary="Run a notebook"),
    Route("jupyter", "job", "GET", "/api/jupyter/jobs/{job_id}", service="suite", summary="Show a notebook job"),
)

backend_app = typer.Typer(
    name="backend",
    help="Connect to the NMTK backend and run any action the app can run.",
    no_args_is_help=True,
)


# ── shared request plumbing ─────────────────────────────────────────────────


def _load_body(data: str | None, data_file: Path | None, json_mode: bool) -> object | None:
    raw = data
    if data_file is not None:
        try:
            raw = data_file.read_text()
        except OSError as exc:
            error_exit({"error": "data_file_unreadable", "detail": str(exc)}, json_mode, code=1)
    if raw is None:
        return None
    try:
        return json.loads(raw)
    except ValueError as exc:
        error_exit({"error": "invalid_json_body", "detail": str(exc)}, json_mode, code=1)


def _load_query(pairs: list[str] | None, json_mode: bool) -> dict[str, str]:
    query: dict[str, str] = {}
    for pair in pairs or []:
        key, sep, value = pair.partition("=")
        if not sep:
            error_exit({"error": "invalid_query", "detail": f"Use key=value, not {pair!r}."}, json_mode, code=1)
        query[key] = value
    return query


def _connect(target: str | None, json_mode: bool) -> Backend:
    try:
        return open_backend(target)
    except SessionError as exc:
        error_exit({"error": "backend_unreachable", "message": str(exc)}, json_mode, code=2)


def _emit(response: httpx.Response, json_mode: bool) -> None:
    try:
        payload = response.json()
    except ValueError:
        payload = {"status_code": response.status_code, "body": response.text}
    if response.status_code >= 400:
        error_exit(
            {"error": "request_failed", "status_code": response.status_code, "response": payload},
            json_mode,
            code=1 if response.status_code < 500 else 2,
        )
    print_result(payload if isinstance(payload, dict | list) else {"result": payload}, json_mode)


def _call(
    backend: Backend,
    method: str,
    path: str,
    service: str,
    body: object | None,
    query: dict[str, str],
    json_mode: bool,
    stream: bool,
) -> None:
    if stream:
        base = backend.urls[service]
        headers = {"X-NMTK-Admin-Token": backend.admin_token} if backend.admin_token else {}
        with httpx.stream(method, f"{base}{path}", headers=headers, params=query, timeout=None) as response:
            if response.status_code >= 400:
                response.read()
                _emit(response, json_mode)
            for line in response.iter_lines():
                if line:
                    print(line, flush=True)
        return
    try:
        response = backend.request(method, path, service=service, body=body, params=query)
    except httpx.HTTPError as exc:
        error_exit({"error": "request_failed", "detail": str(exc)}, json_mode, code=2)
    _emit(response, json_mode)


def _make_command(route: Route):
    params = route.params
    hint = " ".join(f"<{name}>" for name in params)

    def command(
        values: list[str] = typer.Argument(None, metavar=hint or None, help=f"Path values, in order: {', '.join(params)}" if params else "No path values needed."),
        data: str = typer.Option(None, "--data", help="JSON request body."),
        data_file: Path = typer.Option(None, "--data-file", help="File holding the JSON request body."),
        query: list[str] = typer.Option(None, "--query", "-q", help="Query parameter as key=value; repeatable."),
        target: str = typer.Option(None, "--target", help="Which configured backend to use."),
        json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
    ) -> None:
        supplied = list(values or [])
        if len(supplied) != len(params):
            error_exit(
                {
                    "error": "wrong_arguments",
                    "message": f"`{route.group} {route.name}` needs {len(params)} value(s): {hint or '(none)'}.",
                },
                json_mode,
                code=1,
            )
        path = route.path
        for name, value in zip(params, supplied, strict=True):
            path = path.replace("{" + name + "}", value)
        body = _load_body(data, data_file, json_mode)
        parsed_query = _load_query(query, json_mode)
        with _connect(target, json_mode) as backend:
            _call(backend, route.method, path, route.service, body, parsed_query, json_mode, route.stream)

    command.__doc__ = route.summary or f"{route.method} {route.path}"
    return command


def _register() -> None:
    groups: dict[str, typer.Typer] = {}
    for route in ROUTES:
        group = groups.get(route.group)
        if group is None:
            group = groups[route.group] = typer.Typer(no_args_is_help=True, help=f"{route.group} actions")
            backend_app.add_typer(group, name=route.group)
        group.command(route.name)(_make_command(route))


_register()


# ── connection management ───────────────────────────────────────────────────


@backend_app.command("targets")
def targets_command(json_mode: bool = typer.Option(False, "--json", help="Emit JSON output")) -> None:
    """List the backends this machine is configured to reach."""
    found = [
        {
            "id": target.id,
            "name": target.display_name,
            "host": target.host,
            "username": target.username,
            "sshPort": target.ssh_port,
            "authMode": target.auth_mode,
        }
        for target in app_targets()
    ]
    print_result({"targets": found}, json_mode)


@backend_app.command("connect")
def connect_command(
    target: str = typer.Option(None, "--target", help="Which configured backend to use."),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Open a session and confirm the backend answers."""
    with _connect(target, json_mode) as backend:
        try:
            response = backend.request("GET", "/api/launcher/modules")
        except httpx.HTTPError as exc:
            error_exit({"error": "backend_unreachable", "detail": str(exc)}, json_mode, code=2)
        if response.status_code != 200:
            error_exit(
                {"error": "backend_rejected", "status_code": response.status_code},
                json_mode,
                code=2,
            )
        print_result(
            {
                "status": "connected",
                "target": backend.target.id,
                "host": backend.target.host,
                "launcher": backend.urls["launcher"],
                "suite": backend.urls["suite"],
                "jupyter": backend.urls["jupyter"],
            },
            json_mode,
        )


@backend_app.command("api")
def api_command(
    method: str = typer.Argument(..., help="HTTP method, e.g. GET or POST."),
    path: str = typer.Argument(..., help="Endpoint path, e.g. /api/launcher/modules."),
    service: str = typer.Option("launcher", "--service", help="launcher, suite or jupyter."),
    data: str = typer.Option(None, "--data", help="JSON request body."),
    data_file: Path = typer.Option(None, "--data-file", help="File holding the JSON request body."),
    query: list[str] = typer.Option(None, "--query", "-q", help="Query parameter as key=value; repeatable."),
    target: str = typer.Option(None, "--target", help="Which configured backend to use."),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Call any backend endpoint directly — the escape hatch for anything new."""
    if service not in {"launcher", "suite", "jupyter"}:
        error_exit({"error": "unknown_service", "detail": service}, json_mode, code=1)
    body = _load_body(data, data_file, json_mode)
    parsed_query = _load_query(query, json_mode)
    with _connect(target, json_mode) as backend:
        _call(backend, method, path, service, body, parsed_query, json_mode, stream=False)


def login_command(
    target: str = typer.Option(None, "--target", help="Which configured backend to log in to."),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Save a backend's SSH password in the OS keychain for this CLI."""
    try:
        chosen = resolve_target(target)
    except SessionError as exc:
        error_exit({"error": "unknown_target", "message": str(exc)}, json_mode, code=1)
    if chosen.is_local:
        error_exit(
            {"error": "no_credentials_needed", "message": "That backend runs on this machine."},
            json_mode,
            code=1,
        )
    password = os.environ.get("NEUROCLI_SSH_PASSWORD")
    if not password:
        if json_mode:
            error_exit({"error": "missing_password"}, json_mode, code=1)
        password = getpass.getpass(f"SSH password for {chosen.ssh_destination}: ")
    if not password:
        error_exit({"error": "empty_password"}, json_mode, code=1)
    try:
        keychain_write(chosen.keychain_account, password)
    except SessionError as exc:
        error_exit({"error": "keychain_unavailable", "message": str(exc)}, json_mode, code=2)
    print_result({"status": "saved", "target": chosen.id, "stored_in": "os_keychain"}, json_mode)


def logout_command(
    target: str = typer.Option(None, "--target", help="Which configured backend to forget."),
    json_mode: bool = typer.Option(False, "--json", help="Emit JSON output"),
) -> None:
    """Forget a backend's SSH password."""
    try:
        chosen = resolve_target(target)
    except SessionError as exc:
        error_exit({"error": "unknown_target", "message": str(exc)}, json_mode, code=1)
    removed = keychain_delete(chosen.keychain_account)
    print_result({"status": "forgotten" if removed else "nothing_stored", "target": chosen.id}, json_mode)
