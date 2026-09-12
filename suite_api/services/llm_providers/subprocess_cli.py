"""Desktop CLI harness adapters (claude, codex, cursor-agent, opencode)."""

from __future__ import annotations

import asyncio
import json
from dataclasses import dataclass
from typing import Any

from suite_api.services.llm_providers.base import (
    LlmChatResult,
    LlmToolCall,
    ProviderProbe,
)
from suite_api.services.llm_providers.detection import find_executable

_CLI_JSON_HINT = (
    'Respond with JSON only: {"content":"assistant text","tool_calls":'
    '[{"name":"tool_name","arguments":{}}]}. '
    "Use an empty tool_calls array when no tool is needed."
)


@dataclass(frozen=True)
class CliHarnessSpec:
    provider_id: str
    label: str
    binary: str
    prefix_args: tuple[str, ...] = ()
    suffix_args: tuple[str, ...] = ()


CLI_HARNESSES: tuple[CliHarnessSpec, ...] = (
    CliHarnessSpec("claude", "Claude Code", "claude", ("--print",)),
    CliHarnessSpec("codex", "Codex", "codex", ("exec",)),
    CliHarnessSpec("cursor-agent", "Cursor Agent", "cursor-agent", ()),
    CliHarnessSpec("opencode", "OpenCode", "opencode", ()),
    CliHarnessSpec(
        "antigravity",
        "Antigravity CLI",
        "agy",
        ("-p",),
        ("--output-format", "json"),
    ),
)


class SubprocessCliProvider:
    """Run a local CLI harness with argv list execution (no shell)."""

    def __init__(self, spec: CliHarnessSpec) -> None:
        self.spec = spec
        self.provider_id = spec.provider_id
        self.label = spec.label
        self._resolved_binary: str | None = None

    def _binary_path(self) -> str | None:
        if self._resolved_binary is None:
            self._resolved_binary = find_executable(self.spec.binary)
        return self._resolved_binary

    async def probe(self) -> ProviderProbe:
        binary = self._binary_path()
        if binary:
            return ProviderProbe(
                provider_id=self.provider_id,
                label=self.label,
                available=True,
                detail=binary,
            )
        return ProviderProbe(
            provider_id=self.provider_id,
            label=self.label,
            available=False,
            detail=f"{self.spec.binary} not on PATH",
        )

    async def chat(
        self,
        messages: list[dict[str, Any]],
        *,
        tools: list[dict[str, Any]] | None = None,
        model: str | None = None,
    ) -> LlmChatResult:
        binary = self._binary_path()
        if binary is None:
            raise RuntimeError(f"{self.spec.binary} is not available on PATH.")

        prompt = _format_cli_prompt(messages, tools=tools)
        argv = [binary, *self.spec.prefix_args, prompt, *self.spec.suffix_args]
        process = await asyncio.create_subprocess_exec(
            *argv,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(process.communicate(), timeout=180.0)
        if process.returncode != 0:
            detail = stderr.decode("utf-8", errors="replace").strip()
            msg = f"{self.spec.binary} exited {process.returncode}"
            raise RuntimeError(f"{msg}: {detail or 'no stderr'}")
        return _parse_cli_response(stdout.decode("utf-8", errors="replace"))


def _format_cli_prompt(
    messages: list[dict[str, Any]],
    *,
    tools: list[dict[str, Any]] | None,
) -> str:
    from suite_api.services.studio_assistant_skill import (
        message_has_studio_instructions,
    )

    lines: list[str] = []
    if not message_has_studio_instructions(messages):
        lines.append(
            "You are the NMTK Studio assistant. "
            "Use MCP tools step by step; do not batch-apply workspace state."
        )
    for message in messages:
        role = message.get("role", "user")
        content = message.get("content")
        if role == "tool":
            lines.append(f"tool({message.get('tool')}): {json.dumps(content)}")
            continue
        if isinstance(content, str) and content.strip():
            lines.append(f"{role}: {content}")
    if tools:
        lines.append("Available tools:")
        for tool in tools:
            fn = tool.get("function") or tool
            lines.append(f"- {fn.get('name')}: {fn.get('description', '')}")
    lines.append(_CLI_JSON_HINT)
    lines.append("assistant:")
    return "\n".join(lines)


def _parse_cli_response(text: str) -> LlmChatResult:
    candidate = text.strip()
    if candidate.startswith("```"):
        candidate = candidate.strip("`")
        if candidate.startswith("json"):
            candidate = candidate[4:].strip()
    try:
        payload = json.loads(candidate)
    except json.JSONDecodeError:
        return LlmChatResult(content=text.strip())

    if isinstance(payload.get("content"), str):
        content = payload["content"]
    elif isinstance(payload.get("response"), str):
        content = payload["response"]
    else:
        content = text.strip()

    raw_calls = payload.get("tool_calls")
    if raw_calls is None and isinstance(payload.get("message"), dict):
        raw_calls = payload["message"].get("tool_calls")
    tool_calls = [
        LlmToolCall(
            name=str(call.get("name", "")),
            arguments=(
                call.get("arguments")
                if isinstance(call.get("arguments"), dict)
                else {}
            ),
        )
        for call in raw_calls or []
        if call.get("name")
    ]
    return LlmChatResult(
        content=content if isinstance(content, str) else text.strip(),
        tool_calls=tool_calls,
    )
