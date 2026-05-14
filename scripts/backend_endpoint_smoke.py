#!/usr/bin/env python3
"""Lightweight backend endpoint smoke helper for NMTK agents."""

from __future__ import annotations

import argparse
import io
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[1]
MODULES_MANIFEST = REPO_ROOT / "nmtk" / "neuro_toolkit" / "assets" / "modules.json"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_TIMEOUT_SECONDS = 5.0
STARTUP_TIMEOUT_SECONDS = 20.0

NEUROCNL_SMOKE_SPEC = (
    "The sensory neuron MUST fire ONLY IF membrane potential exceeds 0.5\n"
    "The motor neuron MUST emit a spike ONLY IF membrane potential exceeds 0.7\n"
    "The connection from sensory neuron to motor neuron MUST have WITH synaptic weight of 2.0"
)


class SmokeError(RuntimeError):
    """Raised when the helper cannot complete a smoke-test operation."""


@dataclass(frozen=True)
class ModuleSpec:
    """Runnable backend details from the launcher module manifest."""

    id: str
    name: str
    port: int | None
    install_path: str
    source_path: str
    run_path: str
    start_strategy: str
    uvicorn_target: str

    @classmethod
    def from_manifest(cls, raw: dict[str, Any]) -> "ModuleSpec":
        uvicorn_target = str(raw.get("uvicornTarget") or "").strip()
        start_strategy = str(raw.get("startStrategy") or "").strip().lower()
        if not start_strategy:
            start_strategy = "uvicorn" if uvicorn_target else "none"
        port = raw.get("port")
        return cls(
            id=str(raw.get("id") or "").strip(),
            name=str(raw.get("name") or raw.get("id") or "").strip(),
            port=port if isinstance(port, int) else None,
            install_path=str(raw.get("installPath") or raw.get("directory") or "").strip(),
            source_path=str(raw.get("sourcePath") or ".").strip() or ".",
            run_path=str(raw.get("runPath") or raw.get("sourcePath") or ".").strip() or ".",
            start_strategy=start_strategy,
            uvicorn_target=uvicorn_target,
        )

    @property
    def runnable(self) -> bool:
        return (
            bool(self.id)
            and self.port is not None
            and self.start_strategy == "uvicorn"
            and bool(self.uvicorn_target)
        )


@dataclass(frozen=True)
class HttpResponse:
    """HTTP response captured without third-party dependencies."""

    status: int
    body: bytes
    headers: dict[str, str]

    @property
    def text(self) -> str:
        return self.body.decode("utf-8", errors="replace")

    def json(self) -> Any:
        return json.loads(self.text)


@dataclass
class StartedBackend:
    """Process handle for a backend started by this helper."""

    process: subprocess.Popen[Any]
    log_handle: io.TextIOWrapper
    log_path: Path

    def stop(self) -> None:
        if self.process.poll() is None:
            self.process.terminate()
            try:
                self.process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.process.kill()
                self.process.wait(timeout=5)
        self.log_handle.close()


def load_manifest(manifest_path: Path = MODULES_MANIFEST) -> list[ModuleSpec]:
    try:
        raw = json.loads(manifest_path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SmokeError(f"Manifest not found: {manifest_path}") from exc
    except json.JSONDecodeError as exc:
        raise SmokeError(f"Manifest is not valid JSON: {manifest_path}") from exc
    if not isinstance(raw, list):
        raise SmokeError(f"Manifest must contain a list of modules: {manifest_path}")
    modules = [ModuleSpec.from_manifest(item) for item in raw if isinstance(item, dict)]
    return [module for module in modules if module.id]


def runnable_modules(modules: Iterable[ModuleSpec]) -> list[ModuleSpec]:
    return [module for module in modules if module.runnable]


def find_module(module_id: str, modules: Iterable[ModuleSpec]) -> ModuleSpec:
    normalized = module_id.strip().lower()
    for module in modules:
        if module.id.lower() == normalized:
            return module
    known = ", ".join(module.id for module in runnable_modules(modules))
    raise SmokeError(f"Unknown module '{module_id}'. Runnable modules: {known}")


def module_root(module: ModuleSpec, repo_root: Path = REPO_ROOT) -> Path:
    return (repo_root / module.install_path).resolve()


def module_install_dir(module: ModuleSpec, repo_root: Path = REPO_ROOT) -> Path:
    return (module_root(module, repo_root) / module.source_path).resolve()


def module_run_dir(module: ModuleSpec, repo_root: Path = REPO_ROOT) -> Path:
    return (module_root(module, repo_root) / module.run_path).resolve()


def module_python_path(module: ModuleSpec, repo_root: Path = REPO_ROOT) -> Path:
    install_dir = module_install_dir(module, repo_root)
    if os.name == "nt":
        in_project = install_dir / ".venv" / "Scripts" / "python.exe"
        fallback = install_dir / "venv" / "Scripts" / "python.exe"
    else:
        in_project = install_dir / ".venv" / "bin" / "python"
        fallback = install_dir / "venv" / "bin" / "python"
    return in_project if in_project.exists() else fallback


def module_base_url(module: ModuleSpec, host: str = DEFAULT_HOST) -> str:
    if module.port is None:
        raise SmokeError(f"Module '{module.id}' does not define a port")
    return f"http://{host}:{module.port}"


def build_uvicorn_command(
    module: ModuleSpec,
    repo_root: Path = REPO_ROOT,
    host: str = DEFAULT_HOST,
    log_level: str = "info",
) -> tuple[list[str], Path]:
    if not module.runnable:
        raise SmokeError(f"Module '{module.id}' does not define a runnable uvicorn backend")
    python_path = module_python_path(module, repo_root)
    if not python_path.exists():
        raise SmokeError(f"Module python missing at {python_path}")
    run_dir = module_run_dir(module, repo_root)
    command = [
        str(python_path),
        "-m",
        "uvicorn",
        module.uvicorn_target,
        "--host",
        host,
        "--port",
        str(module.port),
        "--log-level",
        log_level,
    ]
    return command, run_dir


def is_port_open(host: str, port: int, timeout: float = 0.25) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


def parse_json_arg(raw: str | None) -> Any:
    if raw is None:
        return None
    source = raw
    if raw.startswith("@"):
        path = Path(raw[1:])
        try:
            source = path.read_text(encoding="utf-8")
        except OSError as exc:
            raise SmokeError(f"Could not read JSON body file: {path}") from exc
    try:
        return json.loads(source)
    except json.JSONDecodeError as exc:
        raise SmokeError(f"Invalid JSON body: {exc}") from exc


def parse_statuses(values: Iterable[str] | None) -> set[int]:
    statuses: set[int] = set()
    for value in values or []:
        for part in value.split(","):
            part = part.strip()
            if not part:
                continue
            try:
                statuses.add(int(part))
            except ValueError as exc:
                raise SmokeError(f"Invalid HTTP status code: {part}") from exc
    return statuses


def http_request(
    url: str,
    *,
    method: str = "GET",
    payload: Any = None,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
    opener: Callable[..., Any] = urllib.request.urlopen,
) -> HttpResponse:
    data: bytes | None = None
    headers: dict[str, str] = {"Accept": "application/json"}
    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(
        url,
        data=data,
        headers=headers,
        method=method.upper(),
    )
    try:
        with opener(request, timeout=timeout) as response:
            response_headers = {
                str(key): str(value) for key, value in getattr(response, "headers", {}).items()
            }
            return HttpResponse(
                status=int(getattr(response, "status", response.getcode())),
                body=response.read(),
                headers=response_headers,
            )
    except urllib.error.HTTPError as exc:
        return HttpResponse(
            status=int(exc.code),
            body=exc.read(),
            headers={str(key): str(value) for key, value in exc.headers.items()},
        )
    except (urllib.error.URLError, TimeoutError, socket.timeout) as exc:
        raise SmokeError(f"Request failed for {url}: {exc}") from exc


def require_success(
    response: HttpResponse,
    url: str,
    *,
    allow_statuses: set[int] | None = None,
) -> None:
    allowed = allow_statuses or set()
    if 200 <= response.status < 300 or response.status in allowed:
        return
    snippet = response.text.replace("\n", " ")[:500]
    raise SmokeError(f"{url} returned HTTP {response.status}: {snippet}")


def _health_ok(response: HttpResponse) -> bool:
    return 200 <= response.status < 300 or response.status == 503


def print_response(response: HttpResponse) -> None:
    print(f"HTTP {response.status}")
    if not response.body:
        return
    try:
        parsed = response.json()
    except json.JSONDecodeError:
        print(response.text)
        return
    print(json.dumps(parsed, indent=2, sort_keys=True))


def command_list(modules: list[ModuleSpec], repo_root: Path) -> int:
    print("module\tport\tuvicorn target\trun dir")
    for module in runnable_modules(modules):
        run_dir = module_run_dir(module, repo_root)
        print(f"{module.id}\t{module.port}\t{module.uvicorn_target}\t{run_dir}")
    return 0


def probe_health(module: ModuleSpec, timeout: float = DEFAULT_TIMEOUT_SECONDS) -> HttpResponse:
    url = f"{module_base_url(module)}/health"
    response = http_request(url, timeout=timeout)
    if not _health_ok(response):
        require_success(response, url)
    return response


def command_health(
    modules: list[ModuleSpec],
    module_id: str,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> int:
    selected = runnable_modules(modules) if module_id == "all" else [find_module(module_id, modules)]
    failed = False
    for module in selected:
        try:
            response = probe_health(module, timeout=timeout)
        except SmokeError as exc:
            failed = True
            print(f"{module.id}: failed: {exc}")
            continue
        label = "degraded optional capability" if response.status == 503 else "ok"
        print(f"{module.id}: {label} HTTP {response.status} {module_base_url(module)}/health")
    return 1 if failed else 0


def summarize_openapi(payload: Any) -> str:
    if not isinstance(payload, dict):
        raise SmokeError("OpenAPI response is not a JSON object")
    info = payload.get("info") if isinstance(payload.get("info"), dict) else {}
    title = str(info.get("title") or "unknown API")
    version = str(info.get("version") or "unknown version")
    paths = payload.get("paths") if isinstance(payload.get("paths"), dict) else {}
    method_count = 0
    for operations in paths.values():
        if isinstance(operations, dict):
            method_count += sum(1 for key in operations if key.upper() in {"GET", "POST", "PUT", "PATCH", "DELETE"})
    return f"{title} ({version}): {len(paths)} paths, {method_count} operations"


def command_openapi(
    modules: list[ModuleSpec],
    module_id: str,
    timeout: float = DEFAULT_TIMEOUT_SECONDS,
) -> int:
    module = find_module(module_id, modules)
    url = f"{module_base_url(module)}/openapi.json"
    response = http_request(url, timeout=timeout)
    require_success(response, url)
    print(summarize_openapi(response.json()))
    return 0


def command_call(args: argparse.Namespace, modules: list[ModuleSpec]) -> int:
    module = find_module(args.module, modules)
    path = args.path if args.path.startswith("/") else f"/{args.path}"
    url = f"{module_base_url(module)}{path}"
    payload = parse_json_arg(args.json_body)
    response = http_request(url, method=args.method, payload=payload, timeout=args.timeout)
    print_response(response)
    require_success(response, url, allow_statuses=parse_statuses(args.allow_status))
    return 0


def start_backend(module: ModuleSpec, repo_root: Path) -> StartedBackend:
    if module.port is None:
        raise SmokeError(f"Module '{module.id}' does not define a port")
    if is_port_open(DEFAULT_HOST, module.port):
        raise SmokeError(
            f"Port {module.port} is already in use. Reuse the running service with "
            "health/openapi/call, or stop it explicitly before using --start."
        )
    command, run_dir = build_uvicorn_command(module, repo_root)
    log_path = Path(tempfile.gettempdir()) / f"nmtk-backend-smoke-{module.id}.log"
    log_handle = log_path.open("w", encoding="utf-8")
    process = subprocess.Popen(
        command,
        cwd=run_dir,
        stdin=subprocess.DEVNULL,
        stdout=log_handle,
        stderr=subprocess.STDOUT,
        text=True,
    )
    print(f"Started {module.id} pid={process.pid}; log={log_path}")
    return StartedBackend(process=process, log_handle=log_handle, log_path=log_path)


def wait_for_health(module: ModuleSpec, process: subprocess.Popen[Any] | None = None) -> HttpResponse:
    deadline = time.monotonic() + STARTUP_TIMEOUT_SECONDS
    last_error = "timed out"
    while time.monotonic() < deadline:
        if process is not None and process.poll() is not None:
            raise SmokeError(f"Process exited with code {process.returncode}")
        try:
            response = probe_health(module, timeout=1.0)
            if _health_ok(response):
                return response
        except SmokeError as exc:
            last_error = str(exc)
        time.sleep(0.5)
    raise SmokeError(f"Timed out waiting for {module_base_url(module)}/health: {last_error}")


def run_neurocnl_examples(module: ModuleSpec) -> None:
    parse_url = f"{module_base_url(module)}/api/parse"
    parse_response = http_request(parse_url, method="POST", payload={"spec": NEUROCNL_SMOKE_SPEC})
    require_success(parse_response, parse_url)
    parse_payload = parse_response.json()
    if parse_payload.get("errors") != 0:
        raise SmokeError(f"NeuroCNL parse smoke returned errors: {parse_response.text}")
    print("neurocnl parse: ok")

    validate_url = f"{module_base_url(module)}/api/validate"
    validate_response = http_request(
        validate_url,
        method="POST",
        payload={"spec": NEUROCNL_SMOKE_SPEC},
    )
    require_success(validate_response, validate_url)
    validate_payload = validate_response.json()
    if validate_payload.get("overall") is not True:
        raise SmokeError(f"NeuroCNL validate smoke did not pass: {validate_response.text}")
    print("neurocnl validate: ok")


def _check_training_modules() -> None:
    """Try to import torch and snntorch and report their availability.

    Called during neurocnl smoke testing to surface whether the optional
    training extras (installed via ``pip install -e ".[training]"``) are
    present in the active environment.
    """
    for mod_name in ("torch", "snntorch"):
        try:
            __import__(mod_name)
            print(f"training module: {mod_name} available")
        except ImportError:
            print(f"training module: {mod_name} NOT available (optional)")


def command_smoke(args: argparse.Namespace, modules: list[ModuleSpec], repo_root: Path) -> int:
    module = find_module(args.module, modules)
    started: StartedBackend | None = None
    try:
        if args.start:
            started = start_backend(module, repo_root)
            health_response = wait_for_health(module, started.process)
        else:
            health_response = probe_health(module)
        health_label = "degraded optional capability" if health_response.status == 503 else "ok"
        print(f"health: {health_label} HTTP {health_response.status}")

        openapi_url = f"{module_base_url(module)}/openapi.json"
        openapi_response = http_request(openapi_url)
        require_success(openapi_response, openapi_url)
        print(f"openapi: {summarize_openapi(openapi_response.json())}")

        if module.id.lower() == "neurocnl":
            run_neurocnl_examples(module)
            _check_training_modules()

        if started is not None and args.keep_running:
            print(f"Leaving {module.id} running on {module_base_url(module)}")
            started.log_handle.close()
            return 0
        return 0
    finally:
        if started is not None and not args.keep_running:
            started.stop()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Probe NMTK backend modules through manifest-defined ports.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=MODULES_MANIFEST,
        help="Path to the launcher modules manifest.",
    )
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=REPO_ROOT,
        help="Path to the NeuroMorphicToolKit repository root.",
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("list", help="List runnable manifest modules.")

    health = subparsers.add_parser("health", help="Probe /health for one module or all modules.")
    health.add_argument("--module", required=True, help="Module id, or 'all'.")
    health.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)

    openapi = subparsers.add_parser("openapi", help="Fetch and summarize /openapi.json.")
    openapi.add_argument("--module", required=True, help="Module id.")
    openapi.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)

    call = subparsers.add_parser("call", help="Call an arbitrary endpoint.")
    call.add_argument("--module", required=True, help="Module id.")
    call.add_argument("--method", default="GET", help="HTTP method.")
    call.add_argument("--path", required=True, help="Endpoint path, for example /api/parse.")
    call.add_argument(
        "--json",
        dest="json_body",
        help="Inline JSON request body, or @path/to/body.json.",
    )
    call.add_argument(
        "--allow-status",
        action="append",
        help="Expected non-2xx status code. Repeat or pass comma-separated values.",
    )
    call.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT_SECONDS)

    smoke = subparsers.add_parser("smoke", help="Run health/OpenAPI and known smoke calls.")
    smoke.add_argument("--module", required=True, help="Module id.")
    smoke.add_argument("--start", action="store_true", help="Start the module before probing.")
    smoke.add_argument(
        "--keep-running",
        action="store_true",
        help="Leave a backend started with --start running after smoke checks pass.",
    )

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        modules = load_manifest(args.manifest)
        repo_root = args.repo_root.resolve()
        if args.command == "list":
            return command_list(modules, repo_root)
        if args.command == "health":
            return command_health(modules, args.module, timeout=args.timeout)
        if args.command == "openapi":
            return command_openapi(modules, args.module, timeout=args.timeout)
        if args.command == "call":
            return command_call(args, modules)
        if args.command == "smoke":
            return command_smoke(args, modules, repo_root)
    except SmokeError as exc:
        print(f"backend_endpoint_smoke: {exc}", file=sys.stderr)
        return 1
    parser.error(f"Unhandled command: {args.command}")
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
