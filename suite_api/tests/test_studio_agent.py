"""Regression coverage for Studio assistant agent routes."""

from __future__ import annotations

import json
from collections.abc import Iterator
from typing import Any

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from suite_api.middleware import attach_middleware
from suite_api.routers import studio_agent
from suite_api.routers.studio_agent import router as studio_agent_router
from suite_api.routers.studio_agent_step_map import (
    STUDIO_PIPELINE_STEP_NAMES,
    pipeline_step_for_tool,
    pipeline_steps_from_tool_result,
)
from suite_api.services.llm_providers.base import LlmChatResult, LlmToolCall

# Must stay aligned with kStudioPipelineStepNames in
# nmtk/neuro_toolkit/lib/features/neurocnl/models/studio_pipeline_steps.dart
_DART_STUDIO_PIPELINE_STEP_NAMES: tuple[str, ...] = (
    "selectData",
    "defineModel",
    "defineTrain",
    "defineEval",
    "run",
    "deployHardware",
    "deployReview",
)


@pytest.fixture
def client() -> TestClient:
    app = FastAPI()
    app.include_router(studio_agent_router)
    return TestClient(app, raise_server_exceptions=True)


@pytest.fixture(autouse=True)
def _clear_sessions() -> Iterator[None]:
    studio_agent.reset_sessions_for_tests()
    yield
    studio_agent.reset_sessions_for_tests()


def test_pipeline_step_names_match_dart_canonical() -> None:
    assert STUDIO_PIPELINE_STEP_NAMES == _DART_STUDIO_PIPELINE_STEP_NAMES


def test_step_map_links_validate_cnl_to_define_model() -> None:
    assert pipeline_step_for_tool("validate_cnl") == "defineModel"


def test_step_map_emits_next_action_suggestions() -> None:
    suggestions = pipeline_steps_from_tool_result(
        "validate_cnl",
        {
            "status": "ok",
            "next_actions": [{"action": "submit_simulation", "label": "Run sim"}],
        },
    )
    assert any(item["step"] == "run" for item in suggestions)


def test_session_crud_round_trip(client: TestClient) -> None:
    created = client.post("/api/studio/agent/sessions", json={"workspace_id": "ws-1"})
    assert created.status_code == 200
    session_id = created.json()["session_id"]

    listed = client.get("/api/studio/agent/sessions")
    assert listed.status_code == 200
    assert any(item["session_id"] == session_id for item in listed.json())

    fetched = client.get(f"/api/studio/agent/sessions/{session_id}")
    assert fetched.status_code == 200
    assert fetched.json()["workspace_id"] == "ws-1"

    deleted = client.delete(f"/api/studio/agent/sessions/{session_id}")
    assert deleted.status_code == 204
    assert client.get(f"/api/studio/agent/sessions/{session_id}").status_code == 404


def test_chat_stream_emits_tool_events(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    def fake_run_tool(
        name: str, args: dict[str, Any], ctx: Any
    ) -> dict[str, Any]:
        assert name == "validate_cnl"
        assert args == {"cnl": "network Test {}"}
        return {
            "status": "ok",
            "summary": "Valid CNL.",
            "details": {},
            "artifacts": [],
            "next_actions": [{"action": "submit_simulation", "label": "Run"}],
        }

    monkeypatch.setattr(studio_agent, "run_tool", fake_run_tool)

    session_id = client.post("/api/studio/agent/sessions", json={}).json()["session_id"]
    response = client.post(
        "/api/studio/agent/chat",
        json={
            "session_id": session_id,
            "message": "validate this network",
            "tool_calls": [
                {
                    "name": "validate_cnl",
                    "arguments": {"cnl": "network Test {}"},
                }
            ],
        },
    )
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/event-stream")

    events: list[tuple[str, dict[str, Any]]] = []
    event_name = ""
    for line in response.text.splitlines():
        if line.startswith("event: "):
            event_name = line.removeprefix("event: ").strip()
        elif line.startswith("data: ") and event_name:
            events.append((event_name, json.loads(line.removeprefix("data: "))))
            event_name = ""

    event_types = [name for name, _payload in events]
    assert event_types == [
        "tool_started",
        "tool_finished",
        "step_suggested",
        "step_suggested",
        "done",
    ]
    tool_finished = next(payload for name, payload in events if name == "tool_finished")
    assert tool_finished["result"]["status"] == "ok"
    assert tool_finished["result"]["summary"] == "Valid CNL."


def test_providers_endpoint_lists_registry(client: TestClient) -> None:
    response = client.get("/api/studio/agent/providers")
    assert response.status_code == 200
    body = response.json()
    assert "providers" in body
    assert len(body["providers"]) >= 6
    assert body["mcp_tools_ready"] is True
    assert body["mcp_tool_count"] >= 1
    assert body["probe_host"] == "backend"
    assert "backend server" in body["probe_host_note"]


def test_handler_context_respects_suite_api_url_env(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("NMTK_SUITE_API_URL", "http://suite_api:9000")
    ctx = studio_agent._handler_context()
    assert ctx.config.suite_api_base_url == "http://suite_api:9000"


def test_studio_agent_tool_schemas_cover_all_mcp_tools() -> None:
    from suite_api.services.llm_providers.registry import studio_agent_tool_schemas
    from tools.nmtk_mcp_server.tool_handlers import TOOL_NAMES

    names = {item["function"]["name"] for item in studio_agent_tool_schemas()}
    assert names == set(TOOL_NAMES)


def test_update_active_provider(client: TestClient) -> None:
    response = client.patch(
        "/api/studio/agent/providers/active",
        json={"provider_id": "ollama", "model": "llama3.2"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["active_provider"] == "ollama"
    assert body["active_model"] == "llama3.2"


def test_update_active_provider_rejects_unknown(client: TestClient) -> None:
    response = client.patch(
        "/api/studio/agent/providers/active",
        json={"provider_id": "not-real"},
    )
    assert response.status_code == 400


def test_mcp_server_entry_endpoint(client: TestClient) -> None:
    response = client.get(
        "/api/studio/agent/mcp/server-entry",
        params={"repo_root": "/tmp/nmtk"},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["server_name"] == "nmtk"
    assert body["env"]["NMTK_REPO_ROOT"] == "/tmp/nmtk"


def test_instructions_endpoint(client: TestClient) -> None:
    response = client.get("/api/studio/agent/instructions")
    assert response.status_code == 200
    body = response.json()
    assert "nmtk-studio-assistant-v1" in body["markdown"]


def test_chat_uses_llm_tool_calls(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    async def fake_llm_turn(_session: Any) -> LlmChatResult:
        return LlmChatResult(
            content="Checking CNL.",
            tool_calls=[
                LlmToolCall(
                    name="validate_cnl",
                    arguments={"spec": "network Test {}"},
                )
            ],
        )

    def fake_run_tool(
        name: str, args: dict[str, Any], ctx: Any
    ) -> dict[str, Any]:
        assert name == "validate_cnl"
        return {
            "status": "ok",
            "summary": "Valid.",
            "details": {},
            "artifacts": [],
            "next_actions": [],
        }

    monkeypatch.setattr(studio_agent, "_llm_turn", fake_llm_turn)
    monkeypatch.setattr(studio_agent, "run_tool", fake_run_tool)

    session_id = client.post("/api/studio/agent/sessions", json={}).json()["session_id"]
    response = client.post(
        "/api/studio/agent/chat",
        json={"session_id": session_id, "message": "validate this"},
    )
    assert response.status_code == 200
    assert "tool_started" in response.text
    assert "validate_cnl" in response.text
    assert "Checking CNL." in response.text


def test_chat_accepts_client_assistant_content(
    client: TestClient, monkeypatch: pytest.MonkeyPatch
) -> None:
    def fake_run_tool(
        name: str, args: dict[str, Any], ctx: Any
    ) -> dict[str, Any]:
        return {
            "status": "ok",
            "summary": "Done.",
            "details": {},
            "artifacts": [],
            "next_actions": [],
        }

    monkeypatch.setattr(studio_agent, "run_tool", fake_run_tool)
    session_id = client.post("/api/studio/agent/sessions", json={}).json()["session_id"]
    response = client.post(
        "/api/studio/agent/chat",
        json={
            "session_id": session_id,
            "message": "validate this",
            "assistant_content": "Running local harness.",
            "tool_calls": [
                {
                    "name": "validate_cnl",
                    "arguments": {"spec": "network Test {}"},
                }
            ],
        },
    )
    assert response.status_code == 200
    assert "Running local harness." in response.text
    assert "_llm_turn" not in response.text


def test_handler_context_uses_runtime_config_env(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("NMTK_SUITE_API_URL", "http://suite_api:9000")
    ctx = studio_agent._handler_context()
    assert ctx.config.suite_api_base_url == "http://suite_api:9000"


def test_chat_rejects_unknown_tool(client: TestClient) -> None:
    session_id = client.post("/api/studio/agent/sessions", json={}).json()["session_id"]
    response = client.post(
        "/api/studio/agent/chat",
        json={
            "session_id": session_id,
            "tool_calls": [{"name": "not_a_real_tool", "arguments": {}}],
        },
    )
    assert response.status_code == 400


def _auth_client(monkeypatch: pytest.MonkeyPatch) -> TestClient:
    monkeypatch.delenv("ALLOWED_ORIGINS", raising=False)
    monkeypatch.setenv("NMTK_AUTH_REQUIRED", "1")
    monkeypatch.setenv("NMTK_ADMIN_TOKEN", "studio-agent-token")
    app = FastAPI()
    app.include_router(studio_agent_router)
    attach_middleware(app)
    return TestClient(app, raise_server_exceptions=True)


def test_studio_agent_routes_require_auth_when_enabled(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    client = _auth_client(monkeypatch)
    headers = {"X-NMTK-Admin-Token": "studio-agent-token"}

    unauthorized = client.post("/api/studio/agent/sessions", json={})
    assert unauthorized.status_code == 401
    assert unauthorized.json()["detail"]["code"] == "unauthorized"

    session_id = client.post(
        "/api/studio/agent/sessions", json={}, headers=headers
    ).json()["session_id"]
    client.cookies.clear()
    chat = client.post(
        "/api/studio/agent/chat",
        json={"session_id": session_id, "tool_calls": []},
    )
    assert chat.status_code == 401

    authorized = client.post(
        "/api/studio/agent/chat",
        json={"session_id": session_id, "tool_calls": []},
        headers=headers,
    )
    assert authorized.status_code == 200
