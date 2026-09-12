"""Studio assistant agent routes backed by NMTK MCP tool handlers."""

from __future__ import annotations

import json
import uuid
from collections.abc import AsyncIterator
from datetime import UTC, datetime
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from suite_api.routers.studio_agent_step_map import pipeline_steps_from_tool_result
from suite_api.services.llm_providers import (
    LlmChatResult,
    all_providers,
    resolve_active_provider,
    studio_agent_tool_schemas,
)
from tools.nmtk_mcp_server.runtime_config import RuntimeConfig
from tools.nmtk_mcp_server.tool_handlers import TOOL_NAMES, ToolHandlerContext, run_tool

router = APIRouter(prefix="/api/studio/agent", tags=["studio-agent"])

# ponytail: in-process session store; upgrade to persisted store if multi-worker.
_sessions: dict[str, StudioAgentSession] = {}


class StudioAgentSession(BaseModel):
    session_id: str
    workspace_id: str | None = None
    created_at: datetime
    updated_at: datetime
    messages: list[dict[str, Any]] = Field(default_factory=list)
    instructions_bootstrapped: bool = False


class CreateSessionRequest(BaseModel):
    workspace_id: str | None = None


class ToolCall(BaseModel):
    name: str
    arguments: dict[str, Any] = Field(default_factory=dict)


class ChatRequest(BaseModel):
    session_id: str
    message: str | None = None
    tool_calls: list[ToolCall] = Field(default_factory=list)
    assistant_content: str | None = None


def _now() -> datetime:
    return datetime.now(tz=UTC)


def _handler_context() -> ToolHandlerContext:
    return ToolHandlerContext(RuntimeConfig.from_env())


def _sse_event(event: str, payload: dict[str, Any]) -> str:
    return f"event: {event}\ndata: {json.dumps(payload, separators=(',', ':'))}\n\n"


def ensure_session_instructions(session: StudioAgentSession) -> None:
    """Inject the NMTK Studio skill once per assistant session."""
    if session.instructions_bootstrapped:
        return
    from suite_api.services.studio_assistant_skill import studio_assistant_instructions

    session.messages.insert(
        0,
        {"role": "system", "content": studio_assistant_instructions()},
    )
    session.instructions_bootstrapped = True


async def _llm_turn(session: StudioAgentSession) -> LlmChatResult | None:
    from suite_api.services.llm_providers.registry import get_active_model

    provider = await resolve_active_provider()
    if provider is None:
        return None
    return await provider.chat(
        session.messages,
        tools=studio_agent_tool_schemas(),
        model=get_active_model(),
    )


async def _chat_stream(
    session: StudioAgentSession,
    request: ChatRequest,
) -> AsyncIterator[str]:
    if request.message:
        session.messages.append({"role": "user", "content": request.message})

    tool_calls = list(request.tool_calls)
    if request.assistant_content:
        session.messages.append(
            {"role": "assistant", "content": request.assistant_content}
        )
        yield _sse_event("assistant_delta", {"text": request.assistant_content})

    if request.message and not tool_calls:
        ensure_session_instructions(session)
        try:
            llm_result = await _llm_turn(session)
        except (OSError, RuntimeError, ValueError, httpx.HTTPError) as exc:
            yield _sse_event(
                "assistant_delta",
                {"text": f"Studio assistant could not reach a local LLM: {exc}"},
            )
            llm_result = None
        if llm_result is not None:
            if llm_result.content:
                session.messages.append(
                    {"role": "assistant", "content": llm_result.content}
                )
                yield _sse_event("assistant_delta", {"text": llm_result.content})
            tool_calls = [
                ToolCall(name=call.name, arguments=call.arguments)
                for call in llm_result.tool_calls
            ]
        elif not tool_calls:
            yield _sse_event(
                "assistant_delta",
                {
                    "text": (
                        "No local LLM harness is available. "
                        "Start Ollama or install a CLI harness."
                    )
                },
            )

    ctx = _handler_context()
    for call in tool_calls:
        yield _sse_event(
            "tool_started",
            {"tool": call.name, "arguments": call.arguments},
        )
        try:
            result = run_tool(call.name, call.arguments, ctx)
        except (KeyError, TypeError, ValueError) as exc:
            result = {
                "status": "error",
                "summary": f"{call.name} failed.",
                "details": {"error": str(exc)},
                "artifacts": [],
                "next_actions": [],
            }

        yield _sse_event(
            "tool_finished",
            {"tool": call.name, "result": result},
        )
        for suggestion in pipeline_steps_from_tool_result(call.name, result):
            yield _sse_event("step_suggested", suggestion)

        session.messages.append(
            {
                "role": "tool",
                "tool": call.name,
                "content": result,
            }
        )

    session.updated_at = _now()
    yield _sse_event("done", {"session_id": request.session_id})


class ActiveProviderRequest(BaseModel):
    provider_id: str | None = None
    model: str | None = None


@router.get("/providers")
async def list_providers() -> dict[str, Any]:
    from suite_api.services.llm_providers import probe_all
    from suite_api.services.llm_providers.registry import (
        get_active_model,
        get_active_provider_id,
    )

    probes = await probe_all()
    active = await resolve_active_provider()
    from suite_api.services.mcp_config import enrich_provider_probe

    return {
        "active_provider": active.provider_id if active else get_active_provider_id(),
        "active_model": get_active_model(),
        "mcp_tools_ready": True,
        "mcp_tool_count": len(TOOL_NAMES),
        "probe_host": "backend",
        "probe_host_note": (
            "LLM providers are detected on the connected backend server, "
            "not on this desktop."
        ),
        "providers": [enrich_provider_probe(probe.__dict__) for probe in probes],
    }


@router.patch("/providers/active")
async def update_active_provider(body: ActiveProviderRequest) -> dict[str, Any]:
    from suite_api.services.llm_providers.registry import set_active_provider

    if body.provider_id:
        known = {provider.provider_id for provider in all_providers()}
        if body.provider_id not in known:
            raise HTTPException(
                status_code=400,
                detail=f"Unknown provider: {body.provider_id}",
            )
    set_active_provider(body.provider_id, model=body.model)
    return await list_providers()


@router.get("/mcp/server-entry")
def mcp_server_entry(repo_root: str | None = None) -> dict[str, Any]:
    from suite_api.services.mcp_config import build_mcp_server_entry

    return build_mcp_server_entry(RuntimeConfig.from_env(), repo_root=repo_root)


@router.get("/instructions")
def studio_assistant_instructions_route() -> dict[str, str]:
    from suite_api.services.studio_assistant_skill import studio_assistant_instructions

    return {"markdown": studio_assistant_instructions()}


@router.post("/sessions", response_model=StudioAgentSession)
def create_session(body: CreateSessionRequest) -> StudioAgentSession:
    now = _now()
    session = StudioAgentSession(
        session_id=str(uuid.uuid4()),
        workspace_id=body.workspace_id,
        created_at=now,
        updated_at=now,
    )
    _sessions[session.session_id] = session
    return session


@router.get("/sessions", response_model=list[StudioAgentSession])
def list_sessions() -> list[StudioAgentSession]:
    return sorted(_sessions.values(), key=lambda item: item.created_at)


@router.get("/sessions/{session_id}", response_model=StudioAgentSession)
def get_session(session_id: str) -> StudioAgentSession:
    session = _sessions.get(session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found.")
    return session


@router.delete("/sessions/{session_id}", status_code=204)
def delete_session(session_id: str) -> None:
    if _sessions.pop(session_id, None) is None:
        raise HTTPException(status_code=404, detail="Session not found.")


@router.post("/chat")
async def chat(request: ChatRequest) -> StreamingResponse:
    session = _sessions.get(request.session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="Session not found.")
    for call in request.tool_calls:
        if call.name not in TOOL_NAMES:
            raise HTTPException(
                status_code=400,
                detail=f"Unknown tool: {call.name}",
            )
    return StreamingResponse(
        _chat_stream(session, request),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


def reset_sessions_for_tests() -> None:
    """Clear the in-process session store (tests only)."""
    _sessions.clear()
