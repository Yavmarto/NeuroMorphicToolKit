"""Tests for Studio assistant skill injection."""

from __future__ import annotations

from datetime import UTC, datetime

from suite_api.routers.studio_agent import (
    StudioAgentSession,
    ensure_session_instructions,
)
from suite_api.services.llm_providers.subprocess_cli import _format_cli_prompt
from suite_api.services.studio_assistant_skill import (
    message_has_studio_instructions,
    studio_assistant_instructions,
)


def test_studio_assistant_instructions_include_marker() -> None:
    text = studio_assistant_instructions()
    assert "nmtk-studio-assistant-v1" in text
    assert "step by step" in text


def test_ensure_session_instructions_runs_once() -> None:
    session = StudioAgentSession(
        session_id="s1",
        created_at=datetime.now(tz=UTC),
        updated_at=datetime.now(tz=UTC),
    )
    ensure_session_instructions(session)
    assert session.instructions_bootstrapped is True
    assert message_has_studio_instructions(session.messages)
    count = len(session.messages)
    ensure_session_instructions(session)
    assert len(session.messages) == count


def test_format_cli_prompt_skips_fallback_when_skill_present() -> None:
    prompt = _format_cli_prompt(
        [{"role": "system", "content": studio_assistant_instructions()}],
        tools=None,
    )
    assert prompt.count("You are the NMTK Studio assistant.") == 0
    assert "system:" in prompt
    assert "Respond with JSON only" in prompt
