"""Reusable stdlib HTTP transport helpers for the launcher control API."""

from __future__ import annotations

import json
import os
import time
import uuid
from http import HTTPStatus
from typing import Any, Protocol

MAX_JSON_BODY_BYTES = 48 * 1024 * 1024


def _cors_origin(handler: JsonHandler) -> str | None:
    origin = str(handler.headers.get("Origin", "")).strip()
    if not origin:
        return None
    allowed = {
        item.strip()
        for item in os.environ.get("NMTK_ALLOWED_ORIGINS", "").split(",")
        if item.strip()
    }
    return origin if origin in allowed else None


class RequestBodyTooLarge(ValueError):
    """Raised before buffering an oversized launcher request body."""


class JsonHandler(Protocol):
    headers: Any
    rfile: Any
    wfile: Any
    server: Any

    def send_response(self, code: int) -> None: ...

    def send_header(self, keyword: str, value: str) -> None: ...

    def end_headers(self) -> None: ...


def read_json_body(handler: JsonHandler) -> dict[str, Any] | None:
    """Read an object JSON request body; preserve the legacy empty-body policy."""
    length = int(handler.headers.get("Content-Length", "0"))
    if length <= 0:
        return None
    if length > MAX_JSON_BODY_BYTES:
        raise RequestBodyTooLarge("Request body exceeds the 48 MB launcher limit")
    raw = handler.rfile.read(length)
    if not raw:
        return None
    try:
        payload = json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, dict) else None


def send_json(handler: JsonHandler, status: HTTPStatus, payload: Any) -> None:
    """Send the launcher API's stable JSON and CORS response envelope."""
    encoded = json.dumps(payload).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(encoded)))
    handler.send_header("X-Request-Id", _request_id(handler))
    allowed_origin = _cors_origin(handler)
    if allowed_origin:
        handler.send_header("Access-Control-Allow-Origin", allowed_origin)
        handler.send_header("Vary", "Origin")
    handler.send_header(
        "Access-Control-Allow-Headers",
        "Authorization, Content-Type, X-NMTK-Admin-Token, X-Request-ID",
    )
    handler.send_header(
        "Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS"
    )
    handler.end_headers()
    if status != HTTPStatus.NO_CONTENT:
        handler.wfile.write(encoded)


def _request_id(handler: JsonHandler) -> str:
    """Return one request correlation ID without trusting blank input."""
    existing = str(getattr(handler, "_request_id", "")).strip()
    if existing:
        return existing
    incoming = str(handler.headers.get("X-Request-ID", "")).strip()
    generated = incoming or str(uuid.uuid4())
    handler._request_id = generated
    return generated


def stream_deployment_sse(handler: JsonHandler, job_id: str) -> None:
    """Stream deployment events with the existing heartbeat and timeout policy."""
    handler.send_response(HTTPStatus.OK)
    handler.send_header("Content-Type", "text/event-stream")
    handler.send_header("Cache-Control", "no-cache")
    handler.send_header("Connection", "keep-alive")
    allowed_origin = _cors_origin(handler)
    if allowed_origin:
        handler.send_header("Access-Control-Allow-Origin", allowed_origin)
        handler.send_header("Vary", "Origin")
    handler.end_headers()
    sent = 0
    deadline = time.monotonic() + 60.0
    while time.monotonic() < deadline:
        events = handler.server.state.deployment_job_events(job_id)
        for event in events[sent:]:
            handler.wfile.write(event.encode("utf-8"))
            handler.wfile.flush()
        sent = len(events)
        job = handler.server.state.get_deployment_job(job_id)
        if str(job.get("stage") or "") in {"completed", "failed", "cancelled"}:
            break
        handler.wfile.write(b"event: heartbeat\ndata: {}\n\n")
        handler.wfile.flush()
        time.sleep(2.0)
