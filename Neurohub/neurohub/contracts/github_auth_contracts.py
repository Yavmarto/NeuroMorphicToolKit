"""Public OAuth Device Flow and capability contracts for Neurohub's GitHub provider."""

from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, HttpUrl


class GitHubDeviceFlowConfig(BaseModel):
    """Public configuration needed to start GitHub's OAuth Device Flow.

    Device Flow needs no client secret and no reachable redirect URI, so this
    is safe to hand to any client without an operator-hosted callback.
    """

    provider: str = "neurohub"
    device_authorization_endpoint: HttpUrl = HttpUrl("https://github.com/login/device/code")
    token_endpoint: HttpUrl = HttpUrl("https://github.com/login/oauth/access_token")
    client_id: str
    scopes: list[str]


class DeviceCodeStarted(BaseModel):
    """Response to starting a device authorization request."""

    session_id: str
    user_code: str
    verification_uri: str
    expires_in: int
    interval: int


class DevicePollResult(BaseModel):
    """One poll outcome for a pending device authorization session."""

    status: Literal["pending", "slow_down", "expired", "denied", "success"]
    access_token: str | None = None
    interval: int | None = None


class GitHubCapabilityStatus(BaseModel):
    """Operator-facing status for GitHub reachability."""

    status: str
    github: str
    message: str | None = None
