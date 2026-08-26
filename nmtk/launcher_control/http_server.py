"""HTTP transport and routing for launcher control."""

from __future__ import annotations

import hmac
import json
import logging
import os
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse
from uuid import uuid4

from .http_transport import (
    RequestBodyTooLarge,
    read_json_body,
    send_json,
    stream_deployment_sse,
)
from .runtime_errors import RuntimeRequestError

LOGGER = logging.getLogger(__name__)


class LauncherControlHandler(BaseHTTPRequestHandler):
    """HTTP adapter exposing launcher control state over a JSON API."""

    server: Any

    def do_OPTIONS(self) -> None:
        self._send_json(HTTPStatus.NO_CONTENT, {})

    def do_GET(self) -> None:
        self._dispatch("GET")

    def do_POST(self) -> None:
        self._dispatch("POST")

    def do_PUT(self) -> None:
        self._dispatch("PUT")

    def do_DELETE(self) -> None:
        self._dispatch("DELETE")

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _dispatch(self, method: str) -> None:
        self._request_id = str(self.headers.get("X-Request-ID", "")).strip() or str(
            uuid4()
        )
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        query = parse_qs(parsed.query)
        try:
            if path != "/health" and not self._is_authorized():
                self._send_error(
                    HTTPStatus.UNAUTHORIZED,
                    code="unauthorized",
                    message="Administrator authentication required.",
                )
                return
            body = self._read_body()
            if method == "GET" and path == "/health":
                self._send_json(
                    HTTPStatus.OK,
                    {
                        "status": "ok",
                    },
                )
                return

            if method == "GET" and path == "/api/launcher/modules":
                refresh_updates = query.get("refreshUpdates", ["0"])[0].lower() in {
                    "1",
                    "true",
                    "yes",
                }
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.serialize_modules(
                        refresh_updates=refresh_updates,
                    ),
                )
                return

            if method == "GET" and path == "/api/launcher/doctor":
                self._send_json(HTTPStatus.OK, self.server.state.doctor_report())
                return

            if method == "GET" and path == "/api/launcher/settings":
                self._send_json(HTTPStatus.OK, self.server.state.get_settings())
                return

            if method == "PUT" and path == "/api/launcher/settings":
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.update_settings(body or {}),
                )
                return

            if method == "GET" and path == "/api/launcher/workspace":
                self._send_json(HTTPStatus.OK, self.server.state.get_workspace())
                return

            if method == "PUT" and path == "/api/launcher/workspace":
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.update_workspace(body or {}),
                )
                return

            if method == "POST" and path == "/api/launcher/workspace/sessions":
                self._send_json(
                    HTTPStatus.CREATED,
                    self.server.state.create_workspace_session(body or {}),
                )
                return

            if method == "POST" and path == "/api/launcher/hardware/discover":
                # Purge stale auto-discovered hosts, reset the discovery flag, and
                # start a fresh probe thread.  Useful for hot-plugged hardware.
                self.server.state._purge_auto_discovered_hosts()
                with self.server.state._hardware_discovery_lock:
                    self.server.state._hardware_discovery_done = False
                threading.Thread(
                    target=self.server.state._auto_discover_local_hardware,
                    daemon=True,
                    name="launcher-hardware-rediscover",
                ).start()
                self._send_json(HTTPStatus.ACCEPTED, {"status": "discovery_started"})
                return

            if method == "GET" and path == "/api/launcher/akida/hosts":
                self._send_json(HTTPStatus.OK, self.server.state.list_akida_hosts())
                return

            if method == "POST" and path == "/api/launcher/akida/hosts":
                self._send_json(
                    HTTPStatus.CREATED,
                    self.server.state.create_akida_host(body or {}),
                )
                return

            if method == "GET" and path == "/api/launcher/pynq/boards":
                self._send_json(HTTPStatus.OK, self.server.state.list_pynq_boards())
                return

            if method == "POST" and path == "/api/launcher/pynq/boards":
                self._send_json(
                    HTTPStatus.CREATED,
                    self.server.state.create_pynq_board(body or {}),
                )
                return

            if method == "GET" and path == "/api/launcher/deployment/targets":
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.list_deployment_targets(),
                )
                return

            if method == "POST" and path == "/api/launcher/deployment/targets":
                self._send_json(
                    HTTPStatus.CREATED,
                    self.server.state.create_deployment_target(body or {}),
                )
                return

            if method == "POST" and path == "/api/launcher/deployment/preflight":
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.deployment_preflight(body or {}),
                )
                return

            if (
                method == "POST"
                and path == "/api/launcher/deployment/bootstrap-remote-user"
            ):
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.bootstrap_remote_deploy_user(body or {}),
                )
                return

            if method == "POST" and path == "/api/launcher/deployment/jobs":
                self._send_json(
                    HTTPStatus.ACCEPTED,
                    self.server.state.create_deployment_job(body or {}),
                )
                return

            segments = [segment for segment in path.split("/") if segment]
            if len(segments) >= 5 and segments[:4] == [
                "api",
                "launcher",
                "deployment",
                "targets",
            ]:
                target_id = segments[4]
                if len(segments) == 5 and method == "PUT":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.update_deployment_target(
                            target_id, body or {}
                        ),
                    )
                    return
                if len(segments) == 5 and method == "DELETE":
                    self.server.state.delete_deployment_target(target_id)
                    self._send_json(HTTPStatus.NO_CONTENT, {})
                    return

            if len(segments) >= 5 and segments[:4] == [
                "api",
                "launcher",
                "deployment",
                "jobs",
            ]:
                job_id = segments[4]
                if len(segments) == 5 and method == "GET":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.get_deployment_job(job_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "events" and method == "GET":
                    self._send_deployment_sse(job_id)
                    return
                if len(segments) == 6 and segments[5] == "cancel" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.cancel_deployment_job(job_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "retry" and method == "POST":
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.retry_deployment_job(job_id),
                    )
                    return

            if len(segments) >= 5 and segments[:4] == [
                "api",
                "launcher",
                "akida",
                "hosts",
            ]:
                host_id = segments[4]
                if len(segments) == 5 and method == "GET":
                    self._send_json(
                        HTTPStatus.OK, self.server.state.get_akida_host(host_id)
                    )
                    return
                if len(segments) == 5 and method == "PUT":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.update_akida_host(host_id, body or {}),
                    )
                    return
                if len(segments) == 5 and method == "DELETE":
                    self.server.state.delete_akida_host(host_id)
                    self._send_json(HTTPStatus.NO_CONTENT, {})
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "connectivity-test"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.test_akida_host_connection(host_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "provision"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.provision_akida_host(host_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "repair" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.repair_akida_host(host_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "restart-services"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.restart_akida_host_services(host_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "preflight"
                    and method == "GET"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.fetch_akida_host_preflight(host_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "status" and method == "GET":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.fetch_akida_host_status(host_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "runtime-update-jobs"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.create_akida_runtime_update_job(host_id),
                    )
                    return
                if (
                    len(segments) == 7
                    and segments[5] == "runtime-update-jobs"
                    and method == "GET"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.get_akida_runtime_update_job(
                            host_id,
                            segments[6],
                        ),
                    )
                    return
                if len(segments) == 6 and segments[5] == "map" and method == "POST":
                    bit_width_raw = query.get("bit_width", ["4"])[0]
                    try:
                        bit_width = int(bit_width_raw)
                    except (TypeError, ValueError):
                        raise ValueError("bit_width must be an integer")
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_akida_map(
                            host_id,
                            body or {},
                            bit_width=bit_width,
                        ),
                    )
                    return
                if len(segments) == 6 and segments[5] == "run" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_akida_run(host_id, body or {}),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "model-jobs"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.proxy_akida_model_job(host_id, body or {}),
                    )
                    return
                if (
                    len(segments) == 7
                    and segments[5] == "model-jobs"
                    and method == "GET"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_akida_model_job_status(
                            host_id, segments[6]
                        ),
                    )
                    return
                if (
                    len(segments) == 8
                    and segments[5] == "models"
                    and segments[7] == "inference"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_akida_model_inference(
                            host_id, segments[6], body or {}
                        ),
                    )
                    return
                if (
                    len(segments) == 8
                    and segments[5] == "models"
                    and segments[7] == "benchmark"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.proxy_akida_model_benchmark(
                            host_id, segments[6]
                        ),
                    )
                    return
                if (
                    len(segments) == 8
                    and segments[5] == "models"
                    and segments[7] == "visualization"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_akida_model_visualization(
                            host_id, segments[6], body or {}
                        ),
                    )
                    return

            if len(segments) >= 5 and segments[:4] == [
                "api",
                "launcher",
                "pynq",
                "boards",
            ]:
                board_id = segments[4]
                if len(segments) == 5 and method == "GET":
                    self._send_json(
                        HTTPStatus.OK, self.server.state.get_pynq_board(board_id)
                    )
                    return
                if len(segments) == 5 and method == "PUT":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.update_pynq_board(board_id, body or {}),
                    )
                    return
                if len(segments) == 5 and method == "DELETE":
                    self.server.state.delete_pynq_board(board_id)
                    self._send_json(HTTPStatus.NO_CONTENT, {})
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "connectivity-test"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.test_pynq_board_connection(board_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "provision"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.provision_pynq_board(board_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "install-overlay"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.install_pynq_overlay_assets(board_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "restart-runtime"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.restart_pynq_runtime(board_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "preflight"
                    and method == "GET"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.fetch_pynq_board_preflight(board_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "status" and method == "GET":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.fetch_pynq_board_status(board_id),
                    )
                    return
                if len(segments) == 6 and segments[5] == "deploy" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_pynq_deploy(board_id, body or {}),
                    )
                    return
                if len(segments) == 6 and segments[5] == "verify" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_pynq_verify(board_id, body or {}),
                    )
                    return
                if len(segments) == 6 and segments[5] == "run" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_pynq_run(board_id, body or {}),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[5] == "runtime-status"
                    and method == "GET"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.proxy_pynq_runtime_status(board_id),
                    )
                    return

            if len(segments) == 5 and segments[:4] == [
                "api",
                "launcher",
                "workspace",
                "sessions",
            ]:
                module_id = segments[4]
                if method == "DELETE":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.delete_workspace_session(module_id),
                    )
                    return

            if method == "GET" and path == "/api/launcher/logs":
                filter_error = query.get("filter", [""])[0].lower() == "error"
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.get_all_logs(filter_error=filter_error),
                )
                return

            if method == "GET" and path == "/api/launcher/crash-log":
                self._send_json(
                    HTTPStatus.OK,
                    self.server.state.get_crash_log_lines(),
                )
                return

            if method == "GET" and path == "/api/launcher/backend-activity-log":
                filter_error = query.get("filter", [""])[0].lower() == "error"
                lines = self.server.state.get_backend_activity_log_lines()["lines"]
                if filter_error:
                    lines = [
                        line
                        for line in lines
                        if any(
                            token in line.lower()
                            for token in ("error", "exception", "failed")
                        )
                        or "-> 4" in line
                        or "-> 5" in line
                    ]
                self._send_json(HTTPStatus.OK, {"lines": lines})
                return

            if len(segments) >= 4 and segments[:3] == ["api", "launcher", "modules"]:
                module_id = segments[3]
                if len(segments) == 4 and method == "GET":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.serialize_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "logs" and method == "GET":
                    self._send_json(
                        HTTPStatus.OK, self.server.state.get_logs(module_id)
                    )
                    return
                if len(segments) == 5 and segments[4] == "install" and method == "POST":
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.install_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "start" and method == "POST":
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.start_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "stop" and method == "POST":
                    self._send_json(
                        HTTPStatus.OK, self.server.state.stop_module(module_id)
                    )
                    return
                if (
                    len(segments) == 5
                    and segments[4] == "uninstall"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.uninstall_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "update" and method == "POST":
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.update_module(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "repair" and method == "POST":
                    self._send_json(
                        HTTPStatus.ACCEPTED,
                        self.server.state.repair_module(module_id),
                    )
                    return
                if (
                    len(segments) == 6
                    and segments[4] == "akida-runtime"
                    and segments[5] == "prepare"
                    and method == "POST"
                ):
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.prepare_akida_runtime(module_id),
                    )
                    return
                if len(segments) == 5 and segments[4] == "settings" and method == "PUT":
                    self._send_json(
                        HTTPStatus.OK,
                        self.server.state.update_module_settings(module_id, body or {}),
                    )
                    return

            self._send_error(
                HTTPStatus.NOT_FOUND,
                code="not_found",
                message="The requested launcher route does not exist.",
            )
        except RequestBodyTooLarge as exc:
            self._send_error(
                HTTPStatus.REQUEST_ENTITY_TOO_LARGE,
                code="request_too_large",
                message=str(exc),
            )
        except KeyError as exc:
            self._send_error(
                HTTPStatus.NOT_FOUND,
                code="resource_not_found",
                message=str(exc).strip("'"),
            )
        except ValueError as exc:
            self._send_error(
                HTTPStatus.BAD_REQUEST,
                code="invalid_request",
                message=str(exc),
            )
        except RuntimeRequestError as exc:
            status = (
                HTTPStatus.GATEWAY_TIMEOUT
                if exc.kind == "timeout"
                else HTTPStatus.BAD_GATEWAY
            )
            if exc.status_code is not None:
                try:
                    status = HTTPStatus(exc.status_code)
                except ValueError:
                    status = HTTPStatus.BAD_GATEWAY
            code = "runtime_timeout" if exc.kind == "timeout" else "runtime_failed"
            message = (
                "The hardware runtime did not respond in time."
                if exc.kind == "timeout"
                else "The hardware runtime could not complete the request."
            )
            if exc.response_body:
                try:
                    runtime_payload = json.loads(exc.response_body)
                    runtime_detail = runtime_payload.get("detail", {})
                    if isinstance(runtime_detail, dict):
                        candidate_code = runtime_detail.get(
                            "code", runtime_detail.get("error_code")
                        )
                        if (
                            isinstance(candidate_code, str)
                            and candidate_code.replace("_", "")
                            .replace("-", "")
                            .isalnum()
                        ):
                            code = candidate_code.lower()
                except (AttributeError, json.JSONDecodeError):
                    pass
            LOGGER.warning(
                "runtime_request_failed request_id=%s method=%s path=%s kind=%s",
                self._request_id,
                method,
                path,
                exc.kind,
            )
            self._send_error(status, code=code, message=message, retryable=True)
        except Exception:
            LOGGER.exception(
                "launcher_request_failed request_id=%s method=%s path=%s",
                self._request_id,
                method,
                path,
            )
            self._send_error(
                HTTPStatus.INTERNAL_SERVER_ERROR,
                code="internal_error",
                message="An internal launcher error occurred.",
            )

    def _read_body(self) -> dict[str, Any] | None:
        return read_json_body(self)

    def _is_authorized(self) -> bool:
        required = os.environ.get("NMTK_AUTH_REQUIRED", "").strip().lower() in {
            "1",
            "true",
            "yes",
        }
        if not required:
            return True
        secret_file = os.environ.get("NMTK_ADMIN_TOKEN_FILE", "").strip()
        try:
            expected = (
                Path(secret_file).read_text(encoding="utf-8").strip()
                if secret_file
                else os.environ.get("NMTK_ADMIN_TOKEN", "").strip()
            )
        except OSError:
            return False
        authorization = str(self.headers.get("Authorization", "")).strip()
        scheme, _, credential = authorization.partition(" ")
        bearer_token = credential.strip() if scheme.lower() == "bearer" else ""
        provided = self.headers.get("X-NMTK-Admin-Token", "") or bearer_token
        return bool(expected and provided and hmac.compare_digest(expected, provided))

    def _send_json(self, status: HTTPStatus, payload: Any) -> None:
        send_json(self, status, payload)

    def _send_error(
        self,
        status: HTTPStatus,
        *,
        code: str,
        message: str,
        retryable: bool = False,
    ) -> None:
        self._send_json(
            status,
            {
                "detail": {
                    "code": code,
                    "message": message,
                    "request_id": self._request_id,
                    "retryable": retryable,
                }
            },
        )

    def _send_deployment_sse(self, job_id: str) -> None:
        stream_deployment_sse(self, job_id)
