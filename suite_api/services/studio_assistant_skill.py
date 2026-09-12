"""Studio assistant skill text — injected once per chat session."""

from __future__ import annotations

_INSTRUCTIONS_MARKER = "nmtk-studio-assistant-v1"


def studio_assistant_instructions() -> str:
    """Return the NMTK Studio assistant skill injected at session start."""
    return f"""[{_INSTRUCTIONS_MARKER}]
You are the NMTK Studio assistant for NeuroCNL network authoring.

Goals:
- Use NMTK MCP tools to validate CNL, check suite health, and advance the
  Studio pipeline step by step.
- Never batch-apply a full workspace state; propose one tool step at a time
  and wait for results.
- Prefer validate_cnl before simulation or deployability checks when the user
  is authoring a network.

When a tool is needed, include it in tool_calls. Otherwise reply with guidance only.
"""


def instructions_marker() -> str:
    return _INSTRUCTIONS_MARKER


def message_has_studio_instructions(messages: list[dict]) -> bool:
    marker = _INSTRUCTIONS_MARKER
    return any(
        message.get("role") == "system"
        and marker in str(message.get("content", ""))
        for message in messages
    )
