"""Shared types for desktop LLM provider adapters."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Protocol


@dataclass(frozen=True)
class ProviderProbe:
    """Result of a single provider availability check."""

    provider_id: str
    label: str
    available: bool
    detail: str = ""


@dataclass(frozen=True)
class LlmToolCall:
    name: str
    arguments: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True)
class LlmChatResult:
    content: str | None = None
    tool_calls: list[LlmToolCall] = field(default_factory=list)


class LlmProvider(Protocol):
    provider_id: str
    label: str

    async def probe(self) -> ProviderProbe:
        """Return whether this provider is reachable on the desktop."""

    async def chat(
        self,
        messages: list[dict[str, Any]],
        *,
        tools: list[dict[str, Any]] | None = None,
        model: str | None = None,
    ) -> LlmChatResult:
        """Run one chat turn against the provider."""
