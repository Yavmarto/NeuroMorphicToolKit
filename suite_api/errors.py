"""Stable, client-safe error responses for the Suite API boundary."""

from __future__ import annotations

import uuid
from typing import TypedDict

from fastapi import Request
from fastapi.responses import JSONResponse


class ErrorDetail(TypedDict):
    """Public error detail shared by Suite API routes and proxies."""

    code: str
    message: str
    request_id: str
    retryable: bool


def request_id_for(request: Request) -> str:
    """Return the correlation ID assigned by middleware, or create a safe fallback."""
    request_id = getattr(request.state, "request_id", "")
    if isinstance(request_id, str) and request_id:
        return request_id
    incoming = request.headers.get("X-Request-ID", "").strip()
    return incoming or str(uuid.uuid4())


def error_response(
    request: Request,
    *,
    status_code: int,
    code: str,
    message: str,
    retryable: bool,
) -> JSONResponse:
    """Build the public error envelope without exposing internal details."""
    return JSONResponse(
        status_code=status_code,
        content={
            "detail": ErrorDetail(
                code=code,
                message=message,
                request_id=request_id_for(request),
                retryable=retryable,
            )
        },
    )
