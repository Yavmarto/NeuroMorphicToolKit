"""Errors raised while proxying a launcher-managed runtime."""

from __future__ import annotations


class RuntimeRequestError(RuntimeError):
    """A remote runtime request that can be translated to an HTTP response."""

    def __init__(
        self,
        message: str,
        *,
        kind: str,
        url: str,
        status_code: int | None = None,
        response_body: str = "",
    ) -> None:
        super().__init__(message)
        self.kind = kind
        self.url = url
        self.status_code = status_code
        self.response_body = response_body
