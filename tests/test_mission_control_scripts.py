from __future__ import annotations

import json
import time
from collections import deque
from pathlib import Path
from typing import Any

import pytest
import requests
import scripts.mission_control_create_task as mc_create
import scripts.mission_control_work as mc_work


class FakeResponse:
    def __init__(self, payload: dict[str, Any] | None = None, status_code: int = 200) -> None:
        self._payload = payload or {}
        self.status_code = status_code
        self.text = json.dumps(self._payload)

    def json(self) -> dict[str, Any]:
        return self._payload

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise requests.HTTPError(f"HTTP {self.status_code}: {self.text}")


class FakeSession:
    def __init__(self) -> None:
        self.calls: list[dict[str, Any]] = []
        self._handlers: dict[str, Any] = {}

    def on(self, method: str, handler: Any) -> None:
        self._handlers[method] = handler

    def _dispatch(self, method: str, url: str, **kwargs: Any) -> FakeResponse:
        self.calls.append({"method": method, "url": url, "kwargs": kwargs})
        handler = self._handlers.get(method)
        if handler is None:
            raise AssertionError(f"No handler for {method.upper()} {url}")
        return handler(url, **kwargs)

    def get(self, url: str, **kwargs: Any) -> FakeResponse:
        return self._dispatch("get", url, **kwargs)

    def post(self, url: str, **kwargs: Any) -> FakeResponse:
        return self._dispatch("post", url, **kwargs)

    def put(self, url: str, **kwargs: Any) -> FakeResponse:
        return self._dispatch("put", url, **kwargs)

    def delete(self, url: str, **kwargs: Any) -> FakeResponse:
        return self._dispatch("delete", url, **kwargs)

    def close(self) -> None:
        return None


class FakeStdout:
    def __init__(self, lines: list[str] | None = None) -> None:
        self._lines = deque(lines or [])

    def readline(self) -> str:
        if not self._lines:
            return ""
        return self._lines.popleft()

    def close(self) -> None:
        return None


class FakeProcess:
    def __init__(self, poll_values: list[int | None], lines: list[str] | None = None) -> None:
        self._poll_values = deque(poll_values)
        self.returncode: int | None = None
        self.stdout = FakeStdout(lines)
        self.pid = 4321

    def poll(self) -> int | None:
        if self._poll_values:
            result = self._poll_values.popleft()
            if result is not None:
                self.returncode = result
            return result
        return self.returncode

    def wait(self, timeout: float | None = None) -> int:
        if self.returncode is None:
            self.returncode = 0
        return self.returncode

    def kill(self) -> None:
        self.returncode = -9

    def force_exit(self, returncode: int) -> None:
        self._poll_values.clear()
        self.returncode = returncode


class FakePopenFactory:
    def __init__(self, processes: list[FakeProcess]) -> None:
        self._processes = deque(processes)
        self.calls: list[dict[str, Any]] = []

    def __call__(self, command: str, **kwargs: Any) -> FakeProcess:
        self.calls.append({"command": command, "kwargs": kwargs})
        if not self._processes:
            raise AssertionError("No fake processes left to return")
        return self._processes.popleft()


def agent_config() -> list[mc_work.AgentConfig]:
    return [
        mc_work.AgentConfig(
            agent_name="codex-worker",
            tool_name="codex",
            role="coder",
            description_prefix="",
            command_template="codex exec --full-auto {description}",
        )
    ]


def connect_payload() -> dict[str, Any]:
    return {
        "connection_id": "123e4567-e89b-12d3-a456-426614174000",
        "agent_id": 11,
        "agent_name": "codex-worker",
        "status": "connected",
        "heartbeat_url": "/api/agents/11/heartbeat",
        "sse_url": "/api/events",
        "token_report_url": "/api/tokens",
    }


def call_payloads(session: FakeSession, method: str, suffix: str) -> list[dict[str, Any]]:
    return [
        call
        for call in session.calls
        if call["method"] == method and call["url"].endswith(suffix)
    ]


def test_register_agents_uses_server_returned_connection_data() -> None:
    session = FakeSession()
    session.on("post", lambda url, **kwargs: FakeResponse(connect_payload()))
    worker = mc_work.MissionControlWorker(
        server_url="https://mc.example",
        api_key="secret",
        agent_configs=agent_config(),
        session=session,
    )

    worker.register_agents()

    assert len(worker.runtime_states) == 1
    state = worker.runtime_states[0]
    assert state.agent_id == 11
    assert state.connection_id == "123e4567-e89b-12d3-a456-426614174000"
    assert state.heartbeat_url == "https://mc.example/api/agents/11/heartbeat"
    assert state.registered_agent_name == "codex-worker"


def test_tick_uses_queue_polling_with_agent_name_and_without_connection_header(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    session = FakeSession()
    popen_factory = FakePopenFactory([FakeProcess([None, None], ["running\n"])])
    monkeypatch.setattr(mc_work.subprocess, "Popen", popen_factory)

    def post_handler(url: str, **kwargs: Any) -> FakeResponse:
        if url.endswith("/api/connect"):
            return FakeResponse(connect_payload())
        return FakeResponse({"comment": {"id": 1}}, status_code=201)

    def get_handler(url: str, **kwargs: Any) -> FakeResponse:
        if url.endswith("/api/agents/11/heartbeat"):
            return FakeResponse({})
        if url.endswith("/api/tasks/queue"):
            return FakeResponse(
                {
                    "reason": "assigned",
                    "task": {"id": 44, "description": "Investigate issue"},
                }
            )
        raise AssertionError(f"Unexpected GET {url}")

    session.on("post", post_handler)
    session.on("get", get_handler)
    session.on("put", lambda url, **kwargs: FakeResponse({"task": kwargs["json"]}))
    worker = mc_work.MissionControlWorker(
        server_url="https://mc.example",
        api_key="secret",
        agent_configs=agent_config(),
        session=session,
    )

    worker.register_agents()
    worker.tick()

    queue_calls = call_payloads(session, "get", "/api/tasks/queue")
    assert len(queue_calls) == 1
    queue_headers = queue_calls[0]["kwargs"]["headers"]
    assert queue_headers["x-agent-name"] == "codex-worker"
    assert "x-connection-id" not in queue_headers

    update_calls = call_payloads(session, "put", "/api/tasks/44")
    assert len(update_calls) == 1
    update_payload = update_calls[0]["kwargs"]["json"]
    assert update_payload == {
        "status": "in_progress",
        "assigned_to": "codex-worker",
    }
    assert "result" not in update_payload
    assert worker.runtime_states[0].active_run is not None


def test_heartbeat_continues_while_process_is_running(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    session = FakeSession()
    popen_factory = FakePopenFactory([FakeProcess([None, None, None], ["still running\n"])])
    monkeypatch.setattr(mc_work.subprocess, "Popen", popen_factory)

    queue_responses = deque(
        [
            FakeResponse(
                {
                    "reason": "assigned",
                    "task": {"id": 77, "description": "Long running task"},
                }
            )
        ]
    )

    def post_handler(url: str, **kwargs: Any) -> FakeResponse:
        if url.endswith("/api/connect"):
            return FakeResponse(connect_payload())
        return FakeResponse({"comment": {"id": 1}}, status_code=201)

    def get_handler(url: str, **kwargs: Any) -> FakeResponse:
        if url.endswith("/api/agents/11/heartbeat"):
            return FakeResponse({})
        if url.endswith("/api/tasks/queue"):
            if not queue_responses:
                raise AssertionError("Queue should not be polled again while process is active")
            return queue_responses.popleft()
        raise AssertionError(f"Unexpected GET {url}")

    session.on("post", post_handler)
    session.on("get", get_handler)
    session.on("put", lambda url, **kwargs: FakeResponse({"task": kwargs["json"]}))
    worker = mc_work.MissionControlWorker(
        server_url="https://mc.example",
        api_key="secret",
        agent_configs=agent_config(),
        session=session,
    )

    worker.register_agents()
    worker.tick()
    state = worker.runtime_states[0]
    state.last_heartbeat_monotonic = time.monotonic() - mc_work.HEARTBEAT_INTERVAL_SECONDS - 1

    queue_call_count = len(call_payloads(session, "get", "/api/tasks/queue"))
    heartbeat_call_count = len(call_payloads(session, "get", "/api/agents/11/heartbeat"))

    worker.tick()

    assert len(call_payloads(session, "get", "/api/tasks/queue")) == queue_call_count
    assert len(call_payloads(session, "get", "/api/agents/11/heartbeat")) == heartbeat_call_count + 1


def test_completed_run_posts_comment_and_metadata_without_result(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    session = FakeSession()
    popen_factory = FakePopenFactory([FakeProcess([0], ["done 1\n", "done 2\n"])])
    monkeypatch.setattr(mc_work.subprocess, "Popen", popen_factory)

    queue_responses = deque(
        [
            FakeResponse(
                {
                    "reason": "assigned",
                    "task": {"id": 51, "description": "Finish task"},
                }
            )
        ]
    )

    def post_handler(url: str, **kwargs: Any) -> FakeResponse:
        if url.endswith("/api/connect"):
            return FakeResponse(connect_payload())
        if url.endswith("/comments"):
            return FakeResponse({"comment": {"id": 9}}, status_code=201)
        raise AssertionError(f"Unexpected POST {url}")

    def get_handler(url: str, **kwargs: Any) -> FakeResponse:
        if url.endswith("/api/agents/11/heartbeat"):
            return FakeResponse({})
        if url.endswith("/api/tasks/queue"):
            if queue_responses:
                return queue_responses.popleft()
            return FakeResponse({"reason": "no_tasks_available", "task": None})
        if url.endswith("/api/tasks/51"):
            return FakeResponse({"task": {"id": 51, "metadata": {"preserve": True}}})
        raise AssertionError(f"Unexpected GET {url}")

    session.on("post", post_handler)
    session.on("get", get_handler)
    session.on("put", lambda url, **kwargs: FakeResponse({"task": kwargs["json"]}))
    worker = mc_work.MissionControlWorker(
        server_url="https://mc.example",
        api_key="secret",
        agent_configs=agent_config(),
        session=session,
    )

    worker.register_agents()
    worker.tick()
    worker.tick()

    update_calls = call_payloads(session, "put", "/api/tasks/51")
    assert len(update_calls) == 2
    completion_payload = update_calls[-1]["kwargs"]["json"]
    assert completion_payload["status"] == "done"
    assert completion_payload["assigned_to"] == "codex-worker"
    assert completion_payload["metadata"]["preserve"] is True
    assert completion_payload["metadata"]["mission_control_worker"]["status"] == "done"
    assert "result" not in completion_payload

    comment_calls = call_payloads(session, "post", "/api/tasks/51/comments")
    assert len(comment_calls) == 1
    assert "completed" in comment_calls[0]["kwargs"]["json"]["content"]

    for call in session.calls:
        headers = call["kwargs"].get("headers", {})
        assert "x-connection-id" not in headers


def test_failed_run_returns_task_to_assigned_and_posts_failure_comment(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    session = FakeSession()
    popen_factory = FakePopenFactory([FakeProcess([23], ["bad\n"])])
    monkeypatch.setattr(mc_work.subprocess, "Popen", popen_factory)

    queue_responses = deque(
        [
            FakeResponse(
                {
                    "reason": "continue_current",
                    "task": {"id": 63, "description": "Retry task"},
                }
            )
        ]
    )

    def post_handler(url: str, **kwargs: Any) -> FakeResponse:
        if url.endswith("/api/connect"):
            return FakeResponse(connect_payload())
        if url.endswith("/comments"):
            return FakeResponse({"comment": {"id": 9}}, status_code=201)
        raise AssertionError(f"Unexpected POST {url}")

    def get_handler(url: str, **kwargs: Any) -> FakeResponse:
        if url.endswith("/api/agents/11/heartbeat"):
            return FakeResponse({})
        if url.endswith("/api/tasks/queue"):
            if queue_responses:
                return queue_responses.popleft()
            return FakeResponse({"reason": "no_tasks_available", "task": None})
        if url.endswith("/api/tasks/63"):
            return FakeResponse({"task": {"id": 63, "metadata": {"preserve": True}}})
        raise AssertionError(f"Unexpected GET {url}")

    session.on("post", post_handler)
    session.on("get", get_handler)
    session.on("put", lambda url, **kwargs: FakeResponse({"task": kwargs["json"]}))
    worker = mc_work.MissionControlWorker(
        server_url="https://mc.example",
        api_key="secret",
        agent_configs=agent_config(),
        session=session,
    )

    worker.register_agents()
    worker.tick()
    worker.tick()

    update_calls = call_payloads(session, "put", "/api/tasks/63")
    assert len(update_calls) == 2
    failure_payload = update_calls[-1]["kwargs"]["json"]
    assert failure_payload["status"] == "assigned"
    assert failure_payload["assigned_to"] == "codex-worker"
    assert failure_payload["metadata"]["preserve"] is True
    assert failure_payload["metadata"]["mission_control_worker"]["exit_code"] == 23
    assert "result" not in failure_payload

    comment_calls = call_payloads(session, "post", "/api/tasks/63/comments")
    assert len(comment_calls) == 1
    assert "Exit code: 23" in comment_calls[0]["kwargs"]["json"]["content"]


def test_single_instance_lock_rejects_second_holder(tmp_path: Path) -> None:
    lock_path = tmp_path / "mission-control.lock"
    first_lock = mc_work.SingleInstanceLock(lock_path)
    second_lock = mc_work.SingleInstanceLock(lock_path)

    first_lock.acquire()
    try:
        with pytest.raises(RuntimeError):
            second_lock.acquire()
    finally:
        first_lock.release()


def test_validate_agent_name_rejects_numeric_ids() -> None:
    with pytest.raises(ValueError):
        mc_create.validate_agent_name("4")


def test_create_task_uses_agent_name_for_assignment(tmp_path: Path) -> None:
    markdown_path = tmp_path / "issue.md"
    markdown_path.write_text("# Example task\n\nInvestigate this.\n", encoding="utf-8")

    session = FakeSession()
    session.on(
        "post",
        lambda url, **kwargs: FakeResponse({"task": {"id": 5}}, status_code=201),
    )

    created = mc_create.create_task(
        str(markdown_path),
        agent_name="codex-worker",
        session=session,
        server_url="https://mc.example",
        api_key="secret",
        project_name="NTMK",
    )

    assert created is True
    create_calls = call_payloads(session, "post", "/api/tasks")
    assert len(create_calls) == 1
    assert create_calls[0]["kwargs"]["json"]["assigned_to"] == "codex-worker"
