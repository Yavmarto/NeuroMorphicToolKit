from __future__ import annotations

import os

from fastapi import HTTPException, Request, WebSocket, status
from fastapi.security import APIKeyHeader, APIKeyQuery

API_KEY_NAME = "X-API-Key"
API_KEY_QUERY_NAME = "api_key"

api_key_header = APIKeyHeader(name=API_KEY_NAME, auto_error=False)
api_key_query = APIKeyQuery(name=API_KEY_QUERY_NAME, auto_error=False)


def is_auth_enabled() -> bool:
    """Check if authentication is enabled via environment variable."""
    return os.environ.get("NEUROSENSE_AUTH_ENABLED", "false").lower() == "true"


def get_expected_api_key() -> str:
    """Get the expected API key from environment variable."""
    return os.environ.get("NEUROSENSE_API_KEY", "debug-key")


# We can define a dependency that wraps the header and query extraction explicitly
# and avoids `Security(api_key_header)` which fails inside websocket contexts.
# But we still want Swagger UI to display the auth.
# A common workaround is to use the security schema classes directly.


async def get_api_key(
    request: Request = None,
    websocket: WebSocket = None,
) -> str | None:
    """FastAPI dependency to validate API key from header or query param."""

    # Extract key manually to safely support WebSockets
    api_key = None
    if request is not None:
        api_key = request.headers.get(API_KEY_NAME) or request.query_params.get(API_KEY_QUERY_NAME)
    if api_key is None and websocket is not None:
        api_key = websocket.headers.get(API_KEY_NAME.lower()) or websocket.query_params.get(
            API_KEY_QUERY_NAME
        )

    if not is_auth_enabled():
        return api_key

    import secrets

    if api_key is None or not secrets.compare_digest(api_key, get_expected_api_key()):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Could not validate credentials",
        )
    return api_key
