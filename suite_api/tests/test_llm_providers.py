"""Coverage for desktop LLM provider registry."""

from __future__ import annotations

import json
from collections.abc import Iterator
from typing import Any

import pytest

from suite_api.services.llm_providers.detection import find_executable, probe_tcp_url
from suite_api.services.llm_providers.ollama import OllamaProvider
from suite_api.services.llm_providers.registry import (
    probe_all,
    reset_providers_for_tests,
    resolve_active_provider,
)
from suite_api.services.llm_providers.subprocess_cli import (
    SubprocessCliProvider,
    _parse_cli_response,
)
from suite_api.services.llm_providers.subprocess_cli import CLI_HARNESSES


@pytest.fixture(autouse=True)
def _reset_registry() -> Iterator[None]:
    reset_providers_for_tests()
    yield
    reset_providers_for_tests()


def test_probe_tcp_url_reports_closed_port() -> None:
    assert probe_tcp_url("http://127.0.0.1:9") is False


@pytest.mark.asyncio
async def test_ollama_chat_parses_tool_calls(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    provider = OllamaProvider(base_url="http://127.0.0.1:11434")

    class FakeResponse:
        def raise_for_status(self) -> None:
            return None

        def json(self) -> dict[str, Any]:
            return {
                "message": {
                    "role": "assistant",
                    "content": "I'll validate that.",
                    "tool_calls": [
                        {
                            "function": {
                                "name": "validate_cnl",
                                "arguments": json.dumps({"spec": "network T {}"}),
                            }
                        }
                    ],
                }
            }

    class FakeClient:
        def __init__(self, *args: Any, **kwargs: Any) -> None:
            pass

        async def __aenter__(self) -> FakeClient:
            return self

        async def __aexit__(self, *args: Any) -> None:
            return None

        async def post(self, url: str, json: dict[str, Any]) -> FakeResponse:
            assert url.endswith("/api/chat")
            assert json["messages"][-1]["content"] == "validate my network"
            return FakeResponse()

    monkeypatch.setattr(
        "suite_api.services.llm_providers.ollama.httpx.AsyncClient",
        FakeClient,
    )

    result = await provider.chat(
        [{"role": "user", "content": "validate my network"}],
        tools=[{"type": "function", "function": {"name": "validate_cnl"}}],
    )
    assert result.content == "I'll validate that."
    assert result.tool_calls[0].name == "validate_cnl"
    assert result.tool_calls[0].arguments == {"spec": "network T {}"}


def test_parse_cli_response_handles_json_envelope() -> None:
    result = _parse_cli_response(
        '{"content":"hello","tool_calls":[{"name":"suite_health","arguments":{}}]}'
    )
    assert result.content == "hello"
    assert result.tool_calls[0].name == "suite_health"


@pytest.mark.asyncio
async def test_subprocess_cli_provider_runs_argv_list(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    spec = next(item for item in CLI_HARNESSES if item.provider_id == "claude")
    provider = SubprocessCliProvider(spec)
    monkeypatch.setattr(
        "suite_api.services.llm_providers.subprocess_cli.find_executable",
        lambda _name: "/usr/bin/claude",
    )

    captured: dict[str, Any] = {}

    class FakeProcess:
        returncode = 0

        async def communicate(self) -> tuple[bytes, bytes]:
            return (
                b'{"content":"ok","tool_calls":[]}',
                b"",
            )

    async def fake_exec(*argv: str, **_kwargs: Any) -> FakeProcess:
        captured["argv"] = argv
        return FakeProcess()

    monkeypatch.setattr(
        "suite_api.services.llm_providers.subprocess_cli.asyncio.create_subprocess_exec",
        fake_exec,
    )

    result = await provider.chat([{"role": "user", "content": "hi"}])
    assert result.content == "ok"
    assert captured["argv"][0] == "/usr/bin/claude"
    assert captured["argv"][1] == "--print"


@pytest.mark.asyncio
async def test_antigravity_cli_provider_uses_json_output_flag(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    spec = next(item for item in CLI_HARNESSES if item.provider_id == "antigravity")
    provider = SubprocessCliProvider(spec)
    monkeypatch.setattr(
        "suite_api.services.llm_providers.subprocess_cli.find_executable",
        lambda _name: "/usr/bin/agy",
    )

    captured: dict[str, Any] = {}

    class FakeProcess:
        returncode = 0

        async def communicate(self) -> tuple[bytes, bytes]:
            return (b'{"content":"ok","tool_calls":[]}', b"")

    async def fake_exec(*argv: str, **_kwargs: Any) -> FakeProcess:
        captured["argv"] = argv
        return FakeProcess()

    monkeypatch.setattr(
        "suite_api.services.llm_providers.subprocess_cli.asyncio.create_subprocess_exec",
        fake_exec,
    )

    await provider.chat([{"role": "user", "content": "hi"}])
    assert captured["argv"][-2:] == ("--output-format", "json")


@pytest.mark.asyncio
async def test_resolve_active_provider_prefers_override(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from suite_api import config as config_module

    monkeypatch.setattr(config_module.settings, "studio_llm_provider", "claude")
    monkeypatch.setattr(
        "suite_api.services.llm_providers.detection.probe_tcp_url",
        lambda *_args, **_kwargs: False,
    )
    monkeypatch.setattr(
        "suite_api.services.llm_providers.subprocess_cli.find_executable",
        lambda name: "/bin/claude" if name == "claude" else None,
    )

    provider = await resolve_active_provider()
    assert provider is not None
    assert provider.provider_id == "claude"


@pytest.mark.asyncio
async def test_probe_all_lists_known_providers() -> None:
    probes = await probe_all()
    provider_ids = {probe.provider_id for probe in probes}
    assert provider_ids == {
        "ollama",
        "lmstudio",
        "claude",
        "codex",
        "cursor-agent",
        "opencode",
        "antigravity",
    }


def test_find_executable_returns_none_for_missing_binary() -> None:
    assert find_executable("definitely-not-a-real-binary-name-xyz") is None
