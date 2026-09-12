"""PATH and localhost probing helpers — no shell injection."""

from __future__ import annotations

import shutil
import socket
from urllib.parse import urlparse


def find_executable(name: str) -> str | None:
    """Resolve a CLI binary on PATH."""
    return shutil.which(name)


def probe_tcp_url(url: str, timeout: float = 0.35) -> bool:
    """Return True when a TCP port on localhost accepts a connection."""
    parsed = urlparse(url)
    host = parsed.hostname or "127.0.0.1"
    if host not in {"127.0.0.1", "localhost", "::1"}:
        return False
    port = parsed.port
    if port is None:
        port = 443 if parsed.scheme == "https" else 80
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False
