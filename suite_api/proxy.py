"""Generic HTTP reverse-proxy helper for suite_api workers.

Usage in a domain router:
    from suite_api.proxy import proxy_to_worker
    from suite_api.config import settings

    @router.api_route("/api/neurosense/devices", methods=["GET", "POST", "DELETE"])
    async def proxy_devices(request: Request) -> Response:
        return await proxy_to_worker(request, settings.neurosense_hw_worker_url)
"""
import logging

import httpx
from fastapi import Request
from fastapi.responses import JSONResponse, Response

logger = logging.getLogger("suite_api.proxy")

# Hop-by-hop headers that must not be forwarded
_HOP_BY_HOP = frozenset(
    {
        "connection",
        "keep-alive",
        "proxy-authenticate",
        "proxy-authorization",
        "te",
        "trailers",
        "transfer-encoding",
        "upgrade",
    }
)


def _forward_headers(request: Request) -> dict[str, str]:
    """Build headers to forward, stripping hop-by-hop headers."""
    return {
        k: v
        for k, v in request.headers.items()
        if k.lower() not in _HOP_BY_HOP
    }


async def proxy_to_worker(
    request: Request,
    worker_base_url: str,
    *,
    timeout: float = 30.0,
) -> Response:
    """Forward an HTTP request to a worker service.

    Returns the worker's response unchanged. If the worker is unreachable,
    returns HTTP 503 with a JSON body rather than a 500/connection-error.

    Args:
        request:         The incoming FastAPI request.
        worker_base_url: Base URL of the worker (e.g. http://localhost:8004).
        timeout:         httpx request timeout in seconds.
    """
    target_url = f"{worker_base_url.rstrip('/')}{request.url.path}"
    if request.url.query:
        target_url = f"{target_url}?{request.url.query}"

    headers = _forward_headers(request)
    body = await request.body()

    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            resp = await client.request(
                method=request.method,
                url=target_url,
                headers=headers,
                content=body,
            )
    except (httpx.ConnectError, httpx.ConnectTimeout, httpx.RemoteProtocolError) as exc:
        logger.warning(
            "Worker %s unreachable for %s %s: %s",
            worker_base_url,
            request.method,
            request.url.path,
            exc,
        )
        return JSONResponse(
            status_code=503,
            content={
                "detail": f"Worker at {worker_base_url} is not running.",
                "worker_url": worker_base_url,
            },
        )
    except httpx.TimeoutException as exc:
        logger.warning("Worker %s timeout: %s", worker_base_url, exc)
        return JSONResponse(
            status_code=503,
            content={"detail": f"Worker at {worker_base_url} timed out.", "worker_url": worker_base_url},
        )

    # Forward the worker response, stripping hop-by-hop headers
    response_headers = {
        k: v
        for k, v in resp.headers.items()
        if k.lower() not in _HOP_BY_HOP and k.lower() != "content-length"
    }
    return Response(
        content=resp.content,
        status_code=resp.status_code,
        headers=response_headers,
        media_type=resp.headers.get("content-type"),
    )
