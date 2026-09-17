"""GitHub OAuth Device Flow discovery, start/poll, and capability preflight for Neurohub.

Device Flow needs no client secret and no reachable redirect URI, so Neurohub
still mediates the whole exchange (clients never call GitHub directly): the
device code from GitHub is held server-side, keyed by an opaque session id,
and only the user-facing ``user_code``/``verification_uri`` are handed to the
client. Sessions are ephemeral (in-memory, TTL-bounded) — this is short-lived
handshake state, not the application database Neurohub deliberately does not
have.
"""

from __future__ import annotations

import os
import secrets
import time
from dataclasses import dataclass

import httpx
from fastapi import APIRouter, HTTPException, status
from pydantic import BaseModel

from neurohub.contracts.github_auth_contracts import (
    DeviceCodeStarted,
    DevicePollResult,
    GitHubCapabilityStatus,
    GitHubDeviceFlowConfig,
)

router = APIRouter(prefix="/oauth", tags=["Neurohub OAuth"])

_DEVICE_AUTHORIZATION_URL = "https://github.com/login/device/code"
_TOKEN_URL = "https://github.com/login/oauth/access_token"
_DEFAULT_SCOPES = ["repo", "read:user"]
_SESSION_TTL_SECONDS = 15 * 60


@dataclass
class _PendingDevice:
    device_code: str
    interval: int
    expires_at: float


_pending_sessions: dict[str, _PendingDevice] = {}


def _client_id() -> str:
    client_id = os.environ.get("GITHUB_OAUTH_CLIENT_ID", "")
    if not client_id:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=(
                "Neurohub sign-in is not configured. "
                "The operator must set GITHUB_OAUTH_CLIENT_ID."
            ),
        )
    return client_id


def _prune_expired() -> None:
    now = time.time()
    expired = [key for key, value in _pending_sessions.items() if value.expires_at < now]
    for key in expired:
        _pending_sessions.pop(key, None)


@router.get("/config", response_model=GitHubDeviceFlowConfig)
def oauth_config() -> GitHubDeviceFlowConfig:
    """Return the public Device Flow configuration without exposing a secret."""
    client_id = _client_id()
    scopes = os.environ.get("GITHUB_OAUTH_SCOPES", " ".join(_DEFAULT_SCOPES)).split()
    return GitHubDeviceFlowConfig(client_id=client_id, scopes=scopes)


@router.post("/device/start", response_model=DeviceCodeStarted)
def start_device_authorization() -> DeviceCodeStarted:
    """Start a GitHub device authorization request on the user's behalf."""
    client_id = _client_id()
    scopes = os.environ.get("GITHUB_OAUTH_SCOPES", " ".join(_DEFAULT_SCOPES))
    try:
        response = httpx.post(
            _DEVICE_AUTHORIZATION_URL,
            data={"client_id": client_id, "scope": scopes},
            headers={"Accept": "application/json"},
            timeout=10.0,
        )
        payload = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Neurohub could not reach GitHub to start sign-in. Try again shortly.",
        ) from exc
    if not response.is_success or "device_code" not in payload:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="GitHub rejected the sign-in request. Try again shortly.",
        )

    _prune_expired()
    session_id = secrets.token_urlsafe(32)
    expires_in = int(payload["expires_in"])
    interval = int(payload.get("interval", 5))
    _pending_sessions[session_id] = _PendingDevice(
        device_code=str(payload["device_code"]),
        interval=interval,
        expires_at=time.time() + expires_in,
    )
    return DeviceCodeStarted(
        session_id=session_id,
        user_code=str(payload["user_code"]),
        verification_uri=str(payload["verification_uri"]),
        expires_in=expires_in,
        interval=interval,
    )


class _DevicePollRequest(BaseModel):
    session_id: str


@router.post("/device/poll", response_model=DevicePollResult)
def poll_device_authorization(request: _DevicePollRequest) -> DevicePollResult:
    """Poll GitHub once for a pending device authorization session."""
    pending = _pending_sessions.get(request.session_id)
    if pending is None:
        return DevicePollResult(status="expired")
    if pending.expires_at < time.time():
        _pending_sessions.pop(request.session_id, None)
        return DevicePollResult(status="expired")

    client_id = _client_id()
    try:
        response = httpx.post(
            _TOKEN_URL,
            data={
                "client_id": client_id,
                "device_code": pending.device_code,
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
            },
            headers={"Accept": "application/json"},
            timeout=10.0,
        )
        payload = response.json()
    except (httpx.HTTPError, ValueError) as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Neurohub could not reach GitHub to finish sign-in. Try again shortly.",
        ) from exc

    if "access_token" in payload:
        _pending_sessions.pop(request.session_id, None)
        return DevicePollResult(status="success", access_token=str(payload["access_token"]))

    error = payload.get("error", "authorization_pending")
    if error == "authorization_pending":
        return DevicePollResult(status="pending", interval=pending.interval)
    if error == "slow_down":
        pending.interval += 5
        return DevicePollResult(status="slow_down", interval=pending.interval)
    if error == "expired_token":
        _pending_sessions.pop(request.session_id, None)
        return DevicePollResult(status="expired")
    # access_denied, or anything unrecognized: stop polling rather than loop forever.
    _pending_sessions.pop(request.session_id, None)
    return DevicePollResult(status="denied")


@router.get("/health", response_model=GitHubCapabilityStatus)
def github_health() -> GitHubCapabilityStatus:
    """Check that GitHub itself is reachable."""
    try:
        response = httpx.get("https://api.github.com/zen", timeout=5.0)
        if not response.is_success:
            return GitHubCapabilityStatus(
                status="degraded",
                github="unreachable",
                message="Neurohub cannot reach GitHub right now.",
            )
    except httpx.HTTPError:
        return GitHubCapabilityStatus(
            status="degraded",
            github="unreachable",
            message="Neurohub cannot reach GitHub right now.",
        )
    return GitHubCapabilityStatus(status="ok", github="connected")
