"""Tornado REST handlers for the NMTK environment manager.

Mounted under ``<base_url>/nmtk-envs/api/`` by the server extension. The
Jupyter worker is intentionally unauthenticated and network-isolated (see
``jupyter_server_config.py``), and these endpoints are reached server-to-server
from suite_api; XSRF cookie checking is therefore disabled here for parity with
that security model.
"""

from __future__ import annotations

import json
import subprocess
import time
import uuid
from collections.abc import Callable
from pathlib import Path
from queue import Empty
from typing import Any

from jupyter_server.base.handlers import APIHandler  # type: ignore[import-not-found]
from jupyter_server.utils import url_path_join  # type: ignore[import-not-found]
from tornado import web  # type: ignore[import-not-found]

from .framework_envs import TARGET_TO_KERNEL
from .jobs import JobRegistry
from .manager import EnvironmentError_, EnvironmentManager

# Stall timeout, not a total-duration budget: reset every time the kernel
# emits activity for this cell (see _drain_notebook_cell below). A single
# cell can run arbitrarily long (e.g. a multi-hundred-epoch training loop)
# as long as it keeps producing output; only a truly stuck kernel — no
# activity at all for this many seconds — trips it.
# Must stay >= kernel_runner.py's _WORKER_EXECUTION_TIMEOUT_SECONDS (the outer
# per-job stall budget), which resets on the same "new output" signal.
_CELL_EXECUTION_TIMEOUT_SECONDS = 30 * 60
_CELL_POLL_INTERVAL_SECONDS = 1


class _NmtkHandler(APIHandler):
    """Shared base: injects the manager + job registry, disables XSRF."""

    def initialize(self, manager: EnvironmentManager, jobs: JobRegistry) -> None:
        self.manager = manager
        self.jobs = jobs

    def check_xsrf_cookie(self) -> None:  # server-to-server, unauthenticated by design
        return

    def _body(self) -> dict:
        if not self.request.body:
            return {}
        try:
            return json.loads(self.request.body)
        except json.JSONDecodeError as exc:
            raise web.HTTPError(400, "Invalid JSON body") from exc

    def write_error(self, status_code: int, **kwargs) -> None:
        self.set_header("Content-Type", "application/json")
        message = self._reason
        exc_info = kwargs.get("exc_info")
        if (
            exc_info
            and isinstance(exc_info[1], web.HTTPError)
            and exc_info[1].log_message
        ):
            message = exc_info[1].log_message
        self.finish(json.dumps({"error": message}))


_CAPABILITY_IMPORTS: dict[str, tuple[str, ...]] = {
    "snntorch": ("torch", "snntorch"),
    "snntorch_sim": ("torch", "snntorch"),
    "akida": ("akida",),
    "nengo": ("nengo",),
    "rockpool": ("rockpool",),
    "sinabs": ("sinabs",),
    "brian2": ("brian2",),
    "pynn": ("pyNN",),
    "lava": ("lava",),
    "lava_sim": ("lava",),
}


def _kernel_name_for_capability(capability: str) -> str:
    target = "snntorch_sim" if capability == "snntorch" else capability
    return TARGET_TO_KERNEL.get(target, "neurocnl")


def _probe_kernel(kernel_name: str, imports: tuple[str, ...]) -> None:
    """Start the configured kernel and prove its imports execute there."""
    import jupyter_client  # type: ignore[import-not-found]

    manager = jupyter_client.KernelManager(kernel_name=kernel_name)
    manager.start_kernel()
    client = manager.blocking_client()
    try:
        client.start_channels()
        client.wait_for_ready(timeout=20)
        source = "; ".join(f"import {module}" for module in imports) or "pass"
        msg_id = client.execute(source)
        reply = client.get_shell_msg(timeout=20)
        if reply.get("parent_header", {}).get("msg_id") != msg_id:
            raise RuntimeError("Kernel returned an unrelated execution reply.")
        content = reply.get("content", {})
        if content.get("status") != "ok":
            raise RuntimeError(
                f"{content.get('ename', 'ImportError')}: {content.get('evalue', '')}"
            )
    finally:
        client.stop_channels()
        manager.shutdown_kernel(now=True)


def _doctor_report(
    manager: EnvironmentManager,
    notebook_root: Path,
    capabilities: list[str],
) -> dict[str, Any]:
    """Exercise notebook storage and configured framework kernels."""
    checks: list[dict[str, Any]] = []
    probe_path = notebook_root / f".nmtk-doctor-{uuid.uuid4().hex}"
    try:
        notebook_root.mkdir(parents=True, exist_ok=True)
        probe_path.write_bytes(b"nmtk-health")
        probe_path.unlink()
        checks.append(
            {
                "id": "jupyter-storage",
                "label": "Jupyter notebook storage",
                "status": "ok",
                "detail": "Jupyter can create and remove notebook files.",
                "recovery": "",
                "repairable": False,
                "required": True,
            }
        )
    except OSError:
        checks.append(
            {
                "id": "jupyter-storage",
                "label": "Jupyter notebook storage",
                "status": "failed",
                "detail": "Jupyter's notebook directory is not writable.",
                "recovery": "Restart Jupyter from System Health.",
                "repairable": True,
                "required": True,
            }
        )

    normalized = list(
        dict.fromkeys(item.strip().lower() for item in capabilities if item.strip())
    )
    if "snntorch" not in normalized and "snntorch_sim" not in normalized:
        normalized.insert(0, "snntorch")
    for capability in normalized:
        imports = _CAPABILITY_IMPORTS.get(capability)
        if imports is None:
            checks.append(
                {
                    "id": f"framework-{capability}",
                    "label": capability,
                    "status": "notConfigured",
                    "detail": "This optional framework is not configured on the server.",
                    "recovery": "",
                    "repairable": False,
                    "required": False,
                }
            )
            continue
        kernel_name = _kernel_name_for_capability(capability)
        python = manager._python_for(kernel_name)
        import_source = "; ".join(f"import {module}" for module in imports)
        process = subprocess.run(
            [str(python), "-c", import_source],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
        try:
            if process.returncode != 0:
                raise RuntimeError(process.stderr.strip() or "Framework import failed.")
            _probe_kernel(kernel_name, imports)
            checks.append(
                {
                    "id": f"framework-{capability}",
                    "label": "snnTorch"
                    if capability.startswith("snntorch")
                    else capability,
                    "status": "ok",
                    "detail": f"Kernel '{kernel_name}' starts and imports its framework.",
                    "recovery": "",
                    "repairable": False,
                    "required": capability.startswith("snntorch"),
                }
            )
        except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
            checks.append(
                {
                    "id": f"framework-{capability}",
                    "label": "snnTorch"
                    if capability.startswith("snntorch")
                    else capability,
                    "status": "failed",
                    "detail": f"Kernel '{kernel_name}' failed its import check: {exc}",
                    "recovery": "Reinstall the backend while keeping data.",
                    "repairable": True,
                    "required": capability.startswith("snntorch"),
                }
            )

    overall = (
        "failed"
        if any(check["status"] == "failed" and check["required"] for check in checks)
        else "degraded"
        if any(check["status"] == "failed" for check in checks)
        else "ok"
    )
    return {"overall": overall, "checks": checks}


def _resolve_execute_path(notebook_root: Path, notebook_path: str) -> Path:
    raw = notebook_path.strip()
    if not raw:
        raise ValueError("notebookPath must not be empty")
    root = notebook_root.resolve()
    resolved = (root / raw).resolve()
    try:
        resolved.relative_to(root)
    except ValueError as exc:
        raise ValueError(
            "notebookPath must stay inside the Jupyter notebook directory"
        ) from exc
    if not resolved.exists():
        raise FileNotFoundError(f"Notebook not found: {raw}")
    return resolved


def _resolve_execute_kernel_name(
    notebook_path: Path, requested_kernel_name: str
) -> str:
    requested = requested_kernel_name.strip() or "python3"
    if requested != "python3":
        return requested
    try:
        notebook = json.loads(notebook_path.read_text(encoding="utf-8"))
        kernelspec = notebook.get("metadata", {}).get("kernelspec", {}).get("name", "")
        return kernelspec or requested
    except Exception:  # noqa: BLE001 - invalid notebook falls back to requested kernel
        return requested


def _drain_notebook_cell(
    kernel_client: Any,
    msg_id: str,
    cell: Any,
    on_line: Callable[[str], None] | None = None,
) -> None:
    from nbformat.v4 import (
        new_output,  # type: ignore[import-not-found]
    )

    deadline = time.monotonic() + _CELL_EXECUTION_TIMEOUT_SECONDS
    saw_idle = False
    saw_execute_reply = False

    while not saw_idle:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(
                f"Notebook cell stalled: no kernel activity for "
                f"{_CELL_EXECUTION_TIMEOUT_SECONDS}s while waiting for output to go idle."
            )
        try:
            message = kernel_client.get_iopub_msg(
                timeout=min(_CELL_POLL_INTERVAL_SECONDS, remaining)
            )
        except Empty:
            continue
        parent_id = message.get("parent_header", {}).get("msg_id", "")
        if parent_id != msg_id:
            continue
        deadline = time.monotonic() + _CELL_EXECUTION_TIMEOUT_SECONDS
        msg_type = message.get("msg_type", "")
        content = message.get("content", {})
        if msg_type == "status" and content.get("execution_state") == "idle":
            saw_idle = True
            continue
        if msg_type == "execute_input":
            cell.execution_count = content.get("execution_count")
            continue
        if msg_type == "stream":
            text = str(content.get("text", ""))
            cell.outputs.append(
                new_output(
                    output_type="stream",
                    name=content.get("name", "stdout"),
                    text=text,
                )
            )
            if content.get("name") == "stdout" and on_line is not None:
                for line in text.splitlines():
                    on_line(line)
            continue
        if msg_type == "display_data":
            cell.outputs.append(
                new_output(
                    output_type="display_data",
                    data=content.get("data", {}),
                    metadata=content.get("metadata", {}),
                )
            )
            continue
        if msg_type == "execute_result":
            cell.outputs.append(
                new_output(
                    output_type="execute_result",
                    data=content.get("data", {}),
                    metadata=content.get("metadata", {}),
                    execution_count=content.get("execution_count"),
                )
            )
            continue
        if msg_type == "error":
            traceback = [str(line) for line in content.get("traceback", [])]
            cell.outputs.append(
                new_output(
                    output_type="error",
                    ename=content.get("ename", "Error"),
                    evalue=content.get("evalue", ""),
                    traceback=traceback,
                )
            )
            raise RuntimeError(
                f"{content.get('ename', 'Error')}: {content.get('evalue', '')}\n"
                + "\n".join(traceback)
            )

    while not saw_execute_reply:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(
                f"Notebook cell stalled: no kernel activity for "
                f"{_CELL_EXECUTION_TIMEOUT_SECONDS}s while waiting for the execute reply."
            )
        try:
            message = kernel_client.get_shell_msg(
                timeout=min(_CELL_POLL_INTERVAL_SECONDS, remaining)
            )
        except Empty:
            continue
        parent_id = message.get("parent_header", {}).get("msg_id", "")
        if parent_id != msg_id or message.get("msg_type") != "execute_reply":
            continue
        deadline = time.monotonic() + _CELL_EXECUTION_TIMEOUT_SECONDS
        content = message.get("content", {})
        status = content.get("status")
        if status == "error":
            raise RuntimeError(
                f"{content.get('ename', 'Error')}: {content.get('evalue', '')}"
            )
        saw_execute_reply = True


def _execute_notebook_job(
    notebook_root: Path,
    notebook_path: str,
    kernel_name: str,
    on_line: Callable[[str], None] | None = None,
    register_kernel: Callable[[Any], None] | None = None,
) -> dict[str, Any]:
    resolved_path = _resolve_execute_path(notebook_root, notebook_path)
    resolved_kernel = _resolve_execute_kernel_name(resolved_path, kernel_name)
    output: list[str] = []
    import jupyter_client  # type: ignore[import-not-found]
    import nbformat  # type: ignore[import-not-found]

    def _record_output_line(line: str) -> None:
        output.append(line)
        if on_line is not None:
            on_line(line)

    notebook = nbformat.read(resolved_path, as_version=4)
    kernel_manager = jupyter_client.KernelManager(kernel_name=resolved_kernel)
    # Regression fix: without an explicit cwd, the kernel subprocess inherits
    # this worker process's own working directory, not the notebook's. Any
    # relative path a generated notebook uses (weights.npz, ./data, etc.)
    # then silently resolves against the wrong directory — either failing
    # outright or, worse, loading an unrelated file that happens to exist
    # there. Always run the kernel from the notebook's own directory.
    kernel_manager.start_kernel(cwd=str(resolved_path.parent))
    if register_kernel is not None:
        register_kernel(kernel_manager)
    kernel_client = kernel_manager.blocking_client()
    kernel_client.start_channels()
    try:
        kernel_client.wait_for_ready(timeout=60)
        for cell in notebook.cells:
            if cell.cell_type != "code":
                continue
            cell.outputs = []
            cell.execution_count = None
            msg_id = kernel_client.execute(cell.source)
            try:
                _drain_notebook_cell(
                    kernel_client,
                    msg_id,
                    cell,
                    _record_output_line,
                )
            finally:
                nbformat.write(notebook, resolved_path)
    finally:
        kernel_client.stop_channels()
        kernel_manager.shutdown_kernel(now=True)
    return {
        "notebookPath": notebook_path,
        "kernelName": resolved_kernel,
        "returncode": 0,
        "output": output,
    }


class EnvironmentsHandler(_NmtkHandler):
    def get(self) -> None:
        self.finish(json.dumps({"environments": self.manager.list_environments()}))

    def post(self) -> None:
        body = self._body()
        display_name = body.get("displayName", "")
        # Presence of requirements switches create → import.
        if "requirements" in body:
            requirements = body.get("requirements", "")
            job_id = self.jobs.submit(
                "import",
                lambda: self.manager.import_requirements(display_name, requirements),
            )
        else:
            job_id = self.jobs.submit(
                "create",
                lambda: self.manager.create_environment(display_name),
            )
        self.set_status(202)
        self.finish(json.dumps({"jobId": job_id}))


class DoctorHandler(_NmtkHandler):
    def post(self) -> None:
        body = self._body()
        raw_capabilities = body.get("capabilities", ["snntorch"])
        capabilities = (
            [str(item) for item in raw_capabilities]
            if isinstance(raw_capabilities, list)
            else ["snntorch"]
        )
        notebook_root = Path(
            self.settings.get("server_root_dir") or self.contents_manager.root_dir
        )
        self.finish(
            json.dumps(_doctor_report(self.manager, notebook_root, capabilities))
        )


class EnvironmentHandler(_NmtkHandler):
    def delete(self, slug: str) -> None:
        try:
            self.manager.delete_environment(slug)
        except EnvironmentError_ as exc:
            raise web.HTTPError(exc.status_code, str(exc)) from exc
        self.set_status(204)
        self.finish()


class PackagesHandler(_NmtkHandler):
    def get(self, slug: str) -> None:
        try:
            packages = self.manager.list_packages(slug)
        except EnvironmentError_ as exc:
            raise web.HTTPError(exc.status_code, str(exc)) from exc
        self.finish(json.dumps({"packages": packages}))

    def post(self, slug: str) -> None:
        body = self._body()
        action = body.get("action", "install")
        packages = body.get("packages", [])
        if action == "install":
            job_id = self.jobs.submit(
                "install", lambda: self.manager.install_packages(slug, packages)
            )
        elif action == "uninstall":
            job_id = self.jobs.submit(
                "uninstall", lambda: self.manager.uninstall_packages(slug, packages)
            )
        else:
            raise web.HTTPError(400, f"Unknown action '{action}'")
        self.set_status(202)
        self.finish(json.dumps({"jobId": job_id}))


class RequirementsHandler(_NmtkHandler):
    def get(self, slug: str) -> None:
        mode = self.get_query_argument("mode", "delta")
        try:
            body = self.manager.export_requirements(slug, mode=mode)
        except EnvironmentError_ as exc:
            raise web.HTTPError(exc.status_code, str(exc)) from exc
        self.set_header("Content-Type", "text/plain; charset=utf-8")
        self.finish(body)


class JobHandler(_NmtkHandler):
    def get(self, job_id: str) -> None:
        job = self.jobs.get(job_id)
        if job is None:
            raise web.HTTPError(404, f"Job '{job_id}' not found")
        self.finish(json.dumps(job))

    def delete(self, job_id: str) -> None:
        if not self.jobs.cancel(job_id):
            raise web.HTTPError(404, f"Job '{job_id}' not found")
        self.set_status(204)
        self.finish()


class ExecutionsHandler(_NmtkHandler):
    def post(self) -> None:
        body = self._body()
        notebook_path = str(body.get("notebookPath", ""))
        kernel_name = str(body.get("kernelName", "python3"))
        notebook_root = Path(
            self.settings.get("server_root_dir") or self.contents_manager.root_dir
        )
        job_id = self.jobs.create("execute")
        self.jobs.run(
            job_id,
            lambda: _execute_notebook_job(
                notebook_root,
                notebook_path,
                kernel_name,
                lambda line: self.jobs.append_output(job_id, line),
                lambda km: self.jobs.register_kernel(job_id, km),
            ),
        )
        self.set_status(202)
        self.finish(json.dumps({"jobId": job_id}))


def register_handlers(server_app) -> None:
    """Attach the env-manager routes to the running Jupyter Server."""
    web_app = server_app.web_app
    base_url = web_app.settings["base_url"]
    manager = EnvironmentManager()
    jobs = JobRegistry()
    kw = {"manager": manager, "jobs": jobs}

    def route(*parts: str) -> str:
        return url_path_join(base_url, "nmtk-envs", "api", *parts)

    slug = r"([^/]+)"
    web_app.add_handlers(
        ".*$",
        [
            (route("environments"), EnvironmentsHandler, kw),
            (route("doctor"), DoctorHandler, kw),
            (route("environments", slug), EnvironmentHandler, kw),
            (route("environments", slug, "packages"), PackagesHandler, kw),
            (route("environments", slug, "requirements"), RequirementsHandler, kw),
            (route("executions"), ExecutionsHandler, kw),
            (route("jobs", slug), JobHandler, kw),
        ],
    )
    server_app.log.info("[nmtk_env_manager] routes registered under %s", route())
