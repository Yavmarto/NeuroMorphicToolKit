"""Ollama localhost API adapter."""

from __future__ import annotations

from typing import Any

import httpx

from suite_api.services.llm_providers.base import (
    LlmChatResult,
    LlmToolCall,
    ProviderProbe,
)
from suite_api.services.llm_providers.detection import probe_tcp_url


class OllamaProvider:
    provider_id = "ollama"
    label = "Ollama"

    def __init__(
        self,
        base_url: str = "http://127.0.0.1:11434",
        default_model: str = "llama3.2",
    ) -> None:
        self.base_url = base_url.rstrip("/")
        self.default_model = default_model

    async def probe(self) -> ProviderProbe:
        reachable = probe_tcp_url(self.base_url)
        return ProviderProbe(
            provider_id=self.provider_id,
            label=self.label,
            available=reachable,
            detail=self.base_url if reachable else f"No listener at {self.base_url}",
        )

    async def chat(
        self,
        messages: list[dict[str, Any]],
        *,
        tools: list[dict[str, Any]] | None = None,
        model: str | None = None,
    ) -> LlmChatResult:
        payload: dict[str, Any] = {
            "model": model or self.default_model,
            "messages": messages,
            "stream": False,
        }
        if tools:
            payload["tools"] = tools
        async with httpx.AsyncClient(timeout=120.0) as client:
            response = await client.post(f"{self.base_url}/api/chat", json=payload)
            response.raise_for_status()
            body = response.json()
        message = body.get("message") or {}
        tool_calls = [
            LlmToolCall(
                name=str(call.get("function", {}).get("name", "")),
                arguments=_coerce_arguments(call.get("function", {}).get("arguments")),
            )
            for call in message.get("tool_calls") or []
            if call.get("function", {}).get("name")
        ]
        content = message.get("content")
        return LlmChatResult(
            content=content if isinstance(content, str) else None,
            tool_calls=tool_calls,
        )


def _coerce_arguments(raw: Any) -> dict[str, Any]:
    if isinstance(raw, dict):
        return raw
    if isinstance(raw, str) and raw.strip():
        import json

        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError:
            return {}
        return parsed if isinstance(parsed, dict) else {}
    return {}
