"""Tornado REST handlers for the NMTK environment manager.

Mounted under ``<base_url>/nmtk-envs/api/`` by the server extension. The
Jupyter worker is intentionally unauthenticated and network-isolated (see
``jupyter_server_config.py``), and these endpoints are reached server-to-server
from suite_api; XSRF cookie checking is therefore disabled here for parity with
that security model.
"""

from __future__ import annotations

import json
from pathlib import Path
from queue import Empty
import time
from typing import Any, Callable

from jupyter_server.base.handlers import APIHandler  # type: ignore[import-not-found]
from jupyter_server.utils import url_path_join  # type: ignore[import-not-found]
from tornado import web  # type: ignore[import-not-found]

from .jobs import JobRegistry
from .manager import EnvironmentError_, EnvironmentManager

# Must stay >= kernel_runner.py's _WORKER_EXECUTION_TIMEOUT_SECONDS (the outer
# per-job budget) — a per-cell ceiling stricter than the outer job budget kills
# any single slow cell (e.g. a full-dataset eval pass) well before that budget
# is used up.
_CELL_EXECUTION_TIMEOUT_SECONDS = 30 * 60
_CELL_POLL_INTERVAL_SECONDS = 1


class _NmtkHandler(APIHandler):
    """Shared base: injects the manager + job registry, disables XSRF."""

    def initialize(self, manager: EnvironmentManager, jobs: JobRegistry) -> None:  # noqa: D401
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
    except Exception:
        return requested


def _drain_notebook_cell(
    kernel_client: Any,
    msg_id: str,
    cell: Any,
    on_line: Callable[[str], None] | None = None,
) -> None:
    from nbformat.v4 import new_output  # type: ignore[import-not-found]  # noqa: PLC0415

    deadline = time.monotonic() + _CELL_EXECUTION_TIMEOUT_SECONDS
    saw_idle = False
    saw_execute_reply = False

    while not saw_idle:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError(
                f"Notebook cell timed out after {_CELL_EXECUTION_TIMEOUT_SECONDS}s "
                "while waiting for kernel output to go idle."
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
                f"Notebook cell timed out after {_CELL_EXECUTION_TIMEOUT_SECONDS}s "
                "while waiting for the kernel execute reply."
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
    import jupyter_client  # type: ignore[import-not-found]  # noqa: PLC0415
    import nbformat  # type: ignore[import-not-found]  # noqa: PLC0415

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
            (route("environments", slug), EnvironmentHandler, kw),
            (route("environments", slug, "packages"), PackagesHandler, kw),
            (route("environments", slug, "requirements"), RequirementsHandler, kw),
            (route("executions"), ExecutionsHandler, kw),
            (route("jobs", slug), JobHandler, kw),
        ],
    )
    server_app.log.info("[nmtk_env_manager] routes registered under %s", route())
