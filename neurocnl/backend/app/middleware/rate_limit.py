"""Shared rate limiter instance (slowapi)."""

from fastapi import Request
from slowapi import Limiter
from slowapi.util import get_remote_address


def get_client_ip(request: Request) -> str:
    """Resolve the client IP, honoring X-Forwarded-For for proxy and test isolation."""
    forwarded = request.headers.get("X-Forwarded-For")
    if isinstance(forwarded, str) and forwarded:
        return forwarded.split(",", maxsplit=1)[0].strip()

    remote_address = get_remote_address(request)
    if isinstance(remote_address, str) and remote_address:
        return remote_address

    return "unknown"


limiter = Limiter(key_func=get_client_ip, headers_enabled=True)
