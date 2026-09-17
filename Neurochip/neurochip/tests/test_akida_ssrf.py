"""Tests for Akida remote_server SSRF guard in validate_remote_url."""

import os
from unittest.mock import patch

import pytest
from fastapi import HTTPException

from neurochip.app.services.akida_router_support import validate_remote_url


def _call(url: str, allowed_hosts: str = "") -> None:
    """Call validate_remote_url with a patched NEUROCHIP_AKIDA_ALLOWED_HOSTS env var."""
    with patch.dict("os.environ", {"NEUROCHIP_AKIDA_ALLOWED_HOSTS": allowed_hosts}, clear=False):
        validate_remote_url(url)


# ---------------------------------------------------------------------------
# No allowlist configured — all remote dispatch must be blocked
# ---------------------------------------------------------------------------


def test_remote_dispatch_blocked_without_allowlist() -> None:
    """Any URL must be rejected when NEUROCHIP_AKIDA_ALLOWED_HOSTS is unset."""
    env = {k: v for k, v in os.environ.items() if k != "NEUROCHIP_AKIDA_ALLOWED_HOSTS"}
    with patch.dict("os.environ", env, clear=True):
        with pytest.raises(HTTPException) as exc_info:
            validate_remote_url("http://akida-server.example.com/deploy")
    assert exc_info.value.status_code == 403
    detail = exc_info.value.detail
    assert isinstance(detail, dict)
    assert detail["error"] == "remote_dispatch_not_configured"


def test_remote_dispatch_blocked_with_empty_allowlist() -> None:
    """Empty NEUROCHIP_AKIDA_ALLOWED_HOSTS string must also block dispatch."""
    with pytest.raises(HTTPException) as exc_info:
        _call("http://akida-server.example.com/deploy", allowed_hosts="")
    assert exc_info.value.status_code == 403
    detail = exc_info.value.detail
    assert isinstance(detail, dict)
    assert detail["error"] == "remote_dispatch_not_configured"


# ---------------------------------------------------------------------------
# Allowlist configured — only listed hosts pass
# ---------------------------------------------------------------------------


def test_allowlisted_hostname_passes() -> None:
    """Host in NEUROCHIP_AKIDA_ALLOWED_HOSTS must pass validation."""
    _call("http://akida-server.internal/deploy", allowed_hosts="akida-server.internal")


def test_non_allowlisted_hostname_blocked() -> None:
    """Host not in the allowlist must be rejected."""
    with pytest.raises(HTTPException) as exc_info:
        _call("http://other-server.internal/deploy", allowed_hosts="akida-server.internal")
    assert exc_info.value.status_code == 403
    detail = exc_info.value.detail
    assert isinstance(detail, dict)
    assert detail["error"] == "host_not_allowed"


# ---------------------------------------------------------------------------
# IP-based SSRF blocks (allowlist configured, but target is a private IP)
# ---------------------------------------------------------------------------


@pytest.mark.parametrize(
    "ip",
    [
        "198.51.100.1",
        "192.0.2.1",
        "198.51.100.1",
        "127.0.0.1",
        "169.254.1.1",
        "0.0.0.1",
    ],
)
def test_private_ipv4_blocked(ip: str) -> None:
    """Private/loopback/link-local IPv4 addresses must be blocked even when allowlisted."""
    with pytest.raises(HTTPException) as exc_info:
        _call(f"http://{ip}/deploy", allowed_hosts=ip)
    assert exc_info.value.status_code == 403
    detail = exc_info.value.detail
    assert isinstance(detail, dict)
    assert detail["error"] == "ssrf_blocked"


@pytest.mark.parametrize(
    "ip",
    [
        "::1",
        "fc00::1",
        "fd12:3456:789a::1",
    ],
)
def test_private_ipv6_blocked(ip: str) -> None:
    """Private/loopback IPv6 addresses must be blocked even when allowlisted."""
    with pytest.raises(HTTPException) as exc_info:
        _call(f"http://[{ip}]/deploy", allowed_hosts=ip)
    assert exc_info.value.status_code == 403
    detail = exc_info.value.detail
    assert isinstance(detail, dict)
    assert detail["error"] == "ssrf_blocked"


# ---------------------------------------------------------------------------
# Scheme validation
# ---------------------------------------------------------------------------


def test_invalid_scheme_rejected() -> None:
    """Non-HTTP/HTTPS schemes must return 422."""
    with pytest.raises(HTTPException) as exc_info:
        _call("ftp://akida-server.internal/deploy", allowed_hosts="akida-server.internal")
    assert exc_info.value.status_code == 422
    detail = exc_info.value.detail
    assert isinstance(detail, dict)
    assert detail["error"] == "invalid_url"
