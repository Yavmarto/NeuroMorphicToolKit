"""Rate limiting configuration for NeuroHub."""

import os

from slowapi import Limiter
from slowapi.util import get_remote_address

# Back counters with the Redis-compatible store at CACHE_URL when configured,
# falling back to in-memory so a Redis outage degrades to allow rather than fail
# (Requirement 8.6). Defaults to pure in-memory when CACHE_URL is unset.
_cache_url = os.environ.get("CACHE_URL")

limiter = Limiter(
    key_func=get_remote_address,
    enabled=True,
    headers_enabled=True,
    storage_uri=_cache_url or "memory://",
    in_memory_fallback_enabled=bool(_cache_url),
)
