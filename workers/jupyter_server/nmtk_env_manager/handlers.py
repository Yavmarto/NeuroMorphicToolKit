"""Tornado REST handlers for the NMTK environment manager.

Mounted under ``<base_url>/nmtk-envs/api/`` by the server extension. The
Jupyter worker is intentionally unauthenticated and network-isolated (see
``jupyter_server_config.py``), and these endpoints are reached server-to-server
from suite_api; XSRF cookie checking is therefore disabled here for parity with
that security model.
"""
from __future__ import annotations

import json

from jupyter_server.base.handlers import APIHandler
from jupyter_server.utils import url_path_join
from tornado import web

from .jobs import JobRegistry
from .manager import EnvironmentError_, EnvironmentManager


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
        if exc_info and isinstance(exc_info[1], web.HTTPError) and exc_info[1].log_message:
            message = exc_info[1].log_message
        self.finish(json.dumps({"error": message}))


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
            job_id = self.jobs.submit("install", lambda: self.manager.install_packages(slug, packages))
        elif action == "uninstall":
            job_id = self.jobs.submit("uninstall", lambda: self.manager.uninstall_packages(slug, packages))
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
            (route("jobs", slug), JobHandler, kw),
        ],
    )
    server_app.log.info("[nmtk_env_manager] routes registered under %s", route())
