"""Reusable stdlib HTTP transport helpers for the launcher control API."""

from __future__ import annotations

import json
import time
from http import HTTPStatus
from typing import Any, Protocol


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
    handler.send_header("Access-Control-Allow-Origin", "*")
    handler.send_header("Access-Control-Allow-Headers", "Content-Type")
    handler.send_header(
        "Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS"
    )
    handler.end_headers()
    if status != HTTPStatus.NO_CONTENT:
        handler.wfile.write(encoded)


def stream_deployment_sse(handler: JsonHandler, job_id: str) -> None:
    """Stream deployment events with the existing heartbeat and timeout policy."""
    handler.send_response(HTTPStatus.OK)
    handler.send_header("Content-Type", "text/event-stream")
    handler.send_header("Cache-Control", "no-cache")
    handler.send_header("Connection", "keep-alive")
    handler.send_header("Access-Control-Allow-Origin", "*")
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
