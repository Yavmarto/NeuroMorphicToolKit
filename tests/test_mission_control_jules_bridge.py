from __future__ import annotations

import json
from collections import deque
from pathlib import Path
from typing import Any

import pytest
import requests
import scripts.mission_control_create_task as mc_create
import scripts.mission_control_jules_work as mc_jules

from scripts import jules_api


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


class FakeHttpSession:
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


class FakeMissionControlSession:
    def __init__(self, tasks: dict[int, dict[str, Any]] | None = None) -> None:
        self.calls: list[dict[str, Any]] = []
        self.tasks = tasks or {}
        self.queue_responses: deque[dict[str, Any]] = deque()
        self.comments: list[dict[str, Any]] = []

    def _record(self, method: str, url: str, **kwargs: Any) -> None:
        self.calls.append({"method": method, "url": url, "kwargs": kwargs})

    def get(self, url: str, **kwargs: Any) -> FakeResponse:
        self._record("get", url, **kwargs)
        if url.endswith("/api/tasks/queue"):
            if self.queue_responses:
                return FakeResponse(self.queue_responses.popleft())
            return FakeResponse({"reason": "no_tasks_available", "task": None})
        if url.endswith("/api/tasks"):
            params = kwargs.get("params", {})
            status = params.get("status")
            assigned_to = params.get("assigned_to")
            tasks = [
                task
                for task in self.tasks.values()
                if (status is None or task.get("status") == status)
                and (assigned_to is None or task.get("assigned_to") == assigned_to)
            ]
            return FakeResponse({"tasks": tasks})
        if "/api/tasks/" in url:
            task_id = int(url.rstrip("/").split("/")[-1])
            return FakeResponse({"task": self.tasks[task_id]})
        raise AssertionError(f"Unexpected GET {url}")

    def post(self, url: str, **kwargs: Any) -> FakeResponse:
        self._record("post", url, **kwargs)
        if url.endswith("/api/connect"):
            return FakeResponse(
                {
                    "connection_id": "123e4567-e89b-12d3-a456-426614174000",
                    "agent_id": 11,
                    "agent_name": "jules-worker",
                    "status": "connected",
                    "heartbeat_url": "/api/agents/11/heartbeat",
                    "sse_url": "/api/events",
                    "token_report_url": "/api/tokens",
                }
            )
        if url.endswith("/heartbeat"):
            return FakeResponse({})
        if url.endswith("/comments"):
            self.comments.append(kwargs["json"])
            return FakeResponse({"comment": {"id": len(self.comments)}}, status_code=201)
        if url.endswith("/api/tasks"):
            task_id = max(self.tasks.keys(), default=0) + 1
            payload = dict(kwargs["json"])
            payload["id"] = task_id
            self.tasks[task_id] = payload
            return FakeResponse({"task": payload}, status_code=201)
        raise AssertionError(f"Unexpected POST {url}")

    def put(self, url: str, **kwargs: Any) -> FakeResponse:
        self._record("put", url, **kwargs)
        if "/api/tasks/" not in url:
            raise AssertionError(f"Unexpected PUT {url}")
        task_id = int(url.rstrip("/").split("/")[-1])
        current = dict(self.tasks[task_id])
        update = dict(kwargs["json"])
        metadata = update.get("metadata")
        if isinstance(metadata, dict):
            current["metadata"] = metadata
        current.update({key: value for key, value in update.items() if key != "metadata"})
        self.tasks[task_id] = current
        return FakeResponse({"task": current})

    def delete(self, url: str, **kwargs: Any) -> FakeResponse:
        self._record("delete", url, **kwargs)
        if url.endswith("/api/connect"):
            return FakeResponse({})
        raise AssertionError(f"Unexpected DELETE {url}")

    def close(self) -> None:
        return None


class FakeJulesClient:
    def __init__(self) -> None:
        self.sources_by_name: dict[str, jules_api.ResolvedSource] = {}
        self.sources_by_repo: dict[str, jules_api.ResolvedSource] = {}
        self.create_side_effects: deque[dict[str, Any] | Exception] = deque()
        self.sessions: dict[str, dict[str, Any]] = {}
        self.activities: dict[str, list[dict[str, Any]]] = {}
        self.resolve_calls: list[dict[str, Any]] = []
        self.validate_branch_calls: list[dict[str, Any]] = []
        self.create_calls: list[dict[str, Any]] = []
        self.get_session_calls: list[str] = []
        self.list_activities_calls: list[str] = []

    def resolve_source(
        self,
        *,
        source_name: str | None = None,
        repo_identifier: str | None = None,
    ) -> jules_api.ResolvedSource:
        self.resolve_calls.append(
            {"source_name": source_name, "repo_identifier": repo_identifier}
        )
        if source_name:
            resolved = self.sources_by_name.get(source_name)
            if resolved:
                return resolved
            raise jules_api.JulesApiError(f"Unknown source {source_name}", status_code=404)
        if repo_identifier:
            normalized_repo = jules_api.normalize_repo_identifier(repo_identifier)
            resolved = self.sources_by_repo.get(normalized_repo)
            if resolved:
                return resolved
            raise jules_api.JulesApiError(f"Unknown repo {normalized_repo}", status_code=404)
        raise jules_api.JulesApiError("Missing source or repo", status_code=400)

    def validate_branch(
        self,
        resolved_source: jules_api.ResolvedSource,
        branch: str | None,
    ) -> str:
        self.validate_branch_calls.append(
            {"source": resolved_source.name, "branch": branch}
        )
        effective_branch = branch or resolved_source.default_branch
        if not effective_branch:
            raise jules_api.JulesApiError("Missing branch", status_code=400)
        if resolved_source.branches and effective_branch not in resolved_source.branches:
            raise jules_api.JulesApiError(
                f"Branch '{effective_branch}' is not available on {resolved_source.name}",
                status_code=400,
            )
        return effective_branch

    def create_session(self, **kwargs: Any) -> dict[str, Any]:
        self.create_calls.append(dict(kwargs))
        if self.create_side_effects:
            outcome = self.create_side_effects.popleft()
            if isinstance(outcome, Exception):
                raise outcome
            return outcome
        session_name = "sessions/default"
        return {
            "name": session_name,
            "id": "default",
            "state": "QUEUED",
            "url": "https://jules.google.com/session/default",
        }

    def get_session(self, session_name: str) -> dict[str, Any]:
        self.get_session_calls.append(session_name)
        return self.sessions[session_name]

    def list_activities(self, session_name: str, *, page_size: int = 100) -> list[dict[str, Any]]:
        self.list_activities_calls.append(session_name)
        return list(self.activities.get(session_name, []))

    def close(self) -> None:
        return None


def write_guide(tmp_path: Path) -> Path:
    guide_path = tmp_path / "JULES_WORKSPACE_GUIDE.md"
    guide_path.write_text(
        "### Single-repo task\n"
        "```text\n"
        "Work only in the <repo-name> repository.\n"
        "Task: <task details>\n"
        "Success criteria: <expected behavior>\n"
        "```\n"
        "\n"
        "### Launcher / control-plane task\n"
        "```text\n"
        "Work only in the NeuroMorphicToolKit root repository.\n"
        "Task: <task details>\n"
        "Success criteria: <expected behavior>\n"
        "```",
        encoding="utf-8",
    )
    return guide_path


def resolved_source(
    name: str = "sources/github-completed-spoon-6-NeuroMorphicToolKit",
    repo_identifier: str = "Completed-Spoon-6/NeuroMorphicToolKit",
    default_branch: str = "main",
    branches: tuple[str, ...] = ("main", "dev"),
) -> jules_api.ResolvedSource:
    return jules_api.ResolvedSource(
        name=name,
        repo_identifier=repo_identifier,
        default_branch=default_branch,
        branches=branches,
    )


def call_payloads(session: FakeMissionControlSession, method: str, suffix: str) -> list[dict[str, Any]]:
    return [
        call
        for call in session.calls
        if call["method"] == method and call["url"].endswith(suffix)
    ]


def test_jules_client_resolves_source_from_repo_and_validates_branch() -> None:
    session = FakeHttpSession()
    session.on(
        "get",
        lambda url, **kwargs: FakeResponse(
            {
                "sources": [
                    {
                        "name": "sources/github-completed-spoon-6-Neurocnl",
                        "id": "github-completed-spoon-6-Neurocnl",
                        "githubRepo": {
                            "owner": "Completed-Spoon-6",
                            "repo": "Neurocnl",
                            "defaultBranch": {"displayName": "main"},
                            "branches": [
                                {"displayName": "main"},
                                {"displayName": "dev"},
                            ],
                        },
                    }
                ]
            }
        ),
    )
    client = jules_api.JulesClient("secret", session=session)

    resolved = client.resolve_source(repo_identifier="Yavmarto/neurocnl")

    assert resolved.name == "sources/github-completed-spoon-6-Neurocnl"
    assert resolved.repo_identifier == "Completed-Spoon-6/Neurocnl"
    assert client.validate_branch(resolved, "dev") == "dev"
    with pytest.raises(jules_api.JulesApiError):
        client.validate_branch(resolved, "missing")


def test_jules_client_create_session_payload_shape() -> None:
    session = FakeHttpSession()
    session.on(
        "post",
        lambda url, **kwargs: FakeResponse(
            {
                "name": "sessions/123",
                "id": "123",
                "state": "QUEUED",
                "url": "https://jules.google.com/session/123",
            }
        ),
    )
    client = jules_api.JulesClient("secret", session=session)

    payload = client.create_session(
        title="Add auth tests",
        prompt="Write tests",
        source_name="sources/github-myorg-myrepo",
        branch="main",
    )

    assert payload["name"] == "sessions/123"
    request_payload = session.calls[0]["kwargs"]["json"]
    assert request_payload["automationMode"] == "AUTO_CREATE_PR"
    assert request_payload["sourceContext"]["source"] == "sources/github-myorg-myrepo"
    assert request_payload["sourceContext"]["githubRepoContext"]["startingBranch"] == "main"
    assert "requirePlanApproval" not in request_payload


def test_worker_creates_session_from_task_source_metadata(tmp_path: Path) -> None:
    task_id = 44
    task = {
        "id": task_id,
        "title": "Add tests",
        "description": "Write regression coverage for the bridge.",
        "status": "assigned",
        "metadata": {
            "mission_control_jules": {
                "request": {
                    "source": "sources/github-completed-spoon-6-NeuroMorphicToolKit",
                    "repo": "Completed-Spoon-6/NeuroMorphicToolKit",
                    "branch": "main",
                }
            }
        },
    }
    session = FakeMissionControlSession(tasks={task_id: task})
    session.queue_responses.append({"reason": "assigned", "task": {"id": task_id}})
    client = FakeJulesClient()
    client.sources_by_name["sources/github-completed-spoon-6-NeuroMorphicToolKit"] = resolved_source()
    client.create_side_effects.append(
        {
            "name": "sessions/123",
            "id": "123",
            "state": "QUEUED",
            "url": "https://jules.google.com/session/123",
        }
    )

    worker = mc_jules.MissionControlJulesWorker(
        server_url="https://mc.example",
        api_key="secret",
        jules_api_key="jules-secret",
        session=session,
        jules_client=client,
        guide_path=write_guide(tmp_path),
    )

    worker.register_agent()
    worker.tick()

    assert client.resolve_calls[0]["source_name"] == "sources/github-completed-spoon-6-NeuroMorphicToolKit"
    assert client.create_calls[0]["source_name"] == "sources/github-completed-spoon-6-NeuroMorphicToolKit"
    assert "Mission Control task title: Add tests" in client.create_calls[0]["prompt"]

    queue_headers = call_payloads(session, "get", "/api/tasks/queue")[0]["kwargs"]["headers"]
    assert queue_headers["x-agent-name"] == "jules-worker"

    update_payload = call_payloads(session, "put", f"/api/tasks/{task_id}")[-1]["kwargs"]["json"]
    assert update_payload["status"] == "in_progress"
    runtime = update_payload["metadata"]["mission_control_jules"]["runtime"]
    assert runtime["sessionName"] == "sessions/123"
    assert runtime["source"] == "sources/github-completed-spoon-6-NeuroMorphicToolKit"
    assert runtime["repo"] == "Completed-Spoon-6/NeuroMorphicToolKit"
    assert runtime["branch"] == "main"

    assert len(session.comments) == 1
    assert "https://jules.google.com/session/123" in session.comments[0]["content"]


def test_worker_recovers_existing_session_without_duplicate_creation(tmp_path: Path) -> None:
    task_id = 55
    task = {
        "id": task_id,
        "title": "Resume existing session",
        "description": "Keep syncing the remote task.",
        "status": "in_progress",
        "assigned_to": "jules-worker",
        "metadata": {
            "mission_control_jules": {
                "request": {"repo": "Completed-Spoon-6/NeuroMorphicToolKit", "branch": "main"},
                "runtime": {
                    "sessionName": "sessions/55",
                    "sessionUrl": "https://jules.google.com/session/55",
                    "state": "IN_PROGRESS",
                    "terminal": False,
                },
            }
        },
    }
    session = FakeMissionControlSession(tasks={task_id: task})
    client = FakeJulesClient()
    client.sessions["sessions/55"] = {
        "name": "sessions/55",
        "id": "55",
        "state": "IN_PROGRESS",
        "url": "https://jules.google.com/session/55",
    }
    client.activities["sessions/55"] = [
        {
            "name": "activities/progress-1",
            "progressUpdated": {
                "title": "Running",
                "description": "Still applying edits",
            },
        }
    ]

    worker = mc_jules.MissionControlJulesWorker(
        server_url="https://mc.example",
        api_key="secret",
        jules_api_key="jules-secret",
        session=session,
        jules_client=client,
        guide_path=write_guide(tmp_path),
    )

    worker.register_agent()
    worker.recover_tasks()
    worker.tick()

    assert client.create_calls == []
    assert client.get_session_calls == ["sessions/55"]
    assert task_id in worker.tracked_tasks


def test_worker_deduplicates_plan_comments_by_activity_name(tmp_path: Path) -> None:
    task_id = 66
    task = {
        "id": task_id,
        "title": "Plan once",
        "description": "Wait for approval.",
        "status": "in_progress",
        "assigned_to": "jules-worker",
        "metadata": {
            "mission_control_jules": {
                "request": {"repo": "Completed-Spoon-6/NeuroMorphicToolKit", "branch": "main"},
                "runtime": {
                    "sessionName": "sessions/66",
                    "state": "PLANNING",
                    "terminal": False,
                },
            }
        },
    }
    session = FakeMissionControlSession(tasks={task_id: task})
    client = FakeJulesClient()
    client.sessions["sessions/66"] = {
        "name": "sessions/66",
        "id": "66",
        "state": "AWAITING_PLAN_APPROVAL",
        "url": "https://jules.google.com/session/66",
    }
    client.activities["sessions/66"] = [
        {
            "name": "activities/plan-1",
            "createTime": "2026-04-17T10:00:00Z",
            "planGenerated": {
                "plan": {
                    "steps": [
                        {"title": "Inspect files"},
                        {"title": "Write tests"},
                    ]
                }
            },
        }
    ]

    worker = mc_jules.MissionControlJulesWorker(
        server_url="https://mc.example",
        api_key="secret",
        jules_api_key="jules-secret",
        session=session,
        jules_client=client,
        guide_path=write_guide(tmp_path),
    )

    worker.register_agent()
    worker.recover_tasks()
    worker.tick()
    worker.tick()

    assert len(session.comments) == 1
    assert "Plan steps:" in session.comments[0]["content"]
    last_update = call_payloads(session, "put", f"/api/tasks/{task_id}")[-1]["kwargs"]["json"]
    assert last_update["status"] == "quality_review"


def test_worker_marks_completed_sessions_done_with_pr_metadata(tmp_path: Path) -> None:
    task_id = 77
    task = {
        "id": task_id,
        "title": "Complete task",
        "description": "Finish successfully.",
        "status": "in_progress",
        "assigned_to": "jules-worker",
        "metadata": {
            "mission_control_jules": {
                "request": {"repo": "Completed-Spoon-6/NeuroMorphicToolKit", "branch": "main"},
                "runtime": {"sessionName": "sessions/77", "terminal": False},
            }
        },
    }
    session = FakeMissionControlSession(tasks={task_id: task})
    client = FakeJulesClient()
    client.sessions["sessions/77"] = {
        "name": "sessions/77",
        "id": "77",
        "state": "COMPLETED",
        "url": "https://jules.google.com/session/77",
        "outputs": [
            {
                "pullRequest": {
                    "title": "Fix worker bridge",
                    "url": "https://github.com/example/repo/pull/77",
                }
            }
        ],
    }
    client.activities["sessions/77"] = [
        {"name": "activities/done-1", "sessionCompleted": {}}
    ]

    worker = mc_jules.MissionControlJulesWorker(
        server_url="https://mc.example",
        api_key="secret",
        jules_api_key="jules-secret",
        session=session,
        jules_client=client,
        guide_path=write_guide(tmp_path),
    )

    worker.register_agent()
    worker.recover_tasks()
    worker.tick()

    update_payload = call_payloads(session, "put", f"/api/tasks/{task_id}")[-1]["kwargs"]["json"]
    runtime = update_payload["metadata"]["mission_control_jules"]["runtime"]
    assert update_payload["status"] == "done"
    assert runtime["terminal"] is True
    assert runtime["pullRequestUrl"] == "https://github.com/example/repo/pull/77"
    assert runtime["pullRequestTitle"] == "Fix worker bridge"
    assert "Fix worker bridge" in session.comments[0]["content"]


def test_worker_marks_failed_sessions_quality_review_with_reason(tmp_path: Path) -> None:
    task_id = 78
    task = {
        "id": task_id,
        "title": "Fail task",
        "description": "Handle failure.",
        "status": "in_progress",
        "assigned_to": "jules-worker",
        "metadata": {
            "mission_control_jules": {
                "request": {"repo": "Completed-Spoon-6/NeuroMorphicToolKit", "branch": "main"},
                "runtime": {"sessionName": "sessions/78", "terminal": False},
            }
        },
    }
    session = FakeMissionControlSession(tasks={task_id: task})
    client = FakeJulesClient()
    client.sessions["sessions/78"] = {
        "name": "sessions/78",
        "id": "78",
        "state": "FAILED",
        "url": "https://jules.google.com/session/78",
    }
    client.activities["sessions/78"] = [
        {
            "name": "activities/fail-1",
            "sessionFailed": {"reason": "Compile failed"},
        }
    ]

    worker = mc_jules.MissionControlJulesWorker(
        server_url="https://mc.example",
        api_key="secret",
        jules_api_key="jules-secret",
        session=session,
        jules_client=client,
        guide_path=write_guide(tmp_path),
    )

    worker.register_agent()
    worker.recover_tasks()
    worker.tick()

    update_payload = call_payloads(session, "put", f"/api/tasks/{task_id}")[-1]["kwargs"]["json"]
    runtime = update_payload["metadata"]["mission_control_jules"]["runtime"]
    assert update_payload["status"] == "quality_review"
    assert runtime["terminal"] is True
    assert runtime["failureReason"] == "Compile failed"
    assert "Compile failed" in session.comments[0]["content"]


def test_worker_retries_transient_create_without_repolling_queue(tmp_path: Path) -> None:
    task_id = 88
    task = {
        "id": task_id,
        "title": "Retry create",
        "description": "Handle rate limits.",
        "status": "assigned",
        "metadata": {
            "mission_control_jules": {
                "request": {"repo": "Completed-Spoon-6/NeuroMorphicToolKit", "branch": "main"}
            }
        },
    }
    session = FakeMissionControlSession(tasks={task_id: task})
    session.queue_responses.append({"reason": "assigned", "task": {"id": task_id}})
    client = FakeJulesClient()
    client.sources_by_repo["Completed-Spoon-6/NeuroMorphicToolKit"] = resolved_source()
    client.create_side_effects.extend(
        [
            jules_api.JulesApiError("rate limited", status_code=429),
            {
                "name": "sessions/88",
                "id": "88",
                "state": "QUEUED",
                "url": "https://jules.google.com/session/88",
            },
        ]
    )

    worker = mc_jules.MissionControlJulesWorker(
        server_url="https://mc.example",
        api_key="secret",
        jules_api_key="jules-secret",
        session=session,
        jules_client=client,
        guide_path=write_guide(tmp_path),
        retry_base_seconds=1,
    )

    worker.register_agent()
    worker.tick()

    assert len(client.create_calls) == 1
    assert len(call_payloads(session, "get", "/api/tasks/queue")) == 1
    tracked = worker.tracked_tasks[task_id]
    assert tracked.session_name is None
    assert tracked.consecutive_sync_failures == 1

    worker.tick()
    assert len(client.create_calls) == 1
    assert len(call_payloads(session, "get", "/api/tasks/queue")) == 1

    tracked.next_retry_monotonic = 0.0
    worker.tick()
    assert len(client.create_calls) == 2
    assert len(call_payloads(session, "get", "/api/tasks/queue")) == 1
    assert worker.tracked_tasks[task_id].session_name == "sessions/88"


def test_create_task_includes_jules_metadata_contract(tmp_path: Path) -> None:
    markdown_path = tmp_path / "issue.md"
    markdown_path.write_text("# Jules task\n\nWire the worker bridge.\n", encoding="utf-8")

    session = FakeMissionControlSession()
    created = mc_create.create_task(
        str(markdown_path),
        agent_name="jules-worker",
        jules_repo="Yavmarto/neurocnl",
        jules_branch="dev",
        jules_source="sources/github-completed-spoon-6-Neurocnl",
        jules_require_plan_approval=True,
        session=session,
        server_url="https://mc.example",
        api_key="secret",
        project_name="NTMK",
    )

    assert created is True
    create_call = call_payloads(session, "post", "/api/tasks")[0]["kwargs"]["json"]
    request = create_call["metadata"]["mission_control_jules"]["request"]
    assert request == {
        "repo": "Completed-Spoon-6/Neurocnl",
        "branch": "dev",
        "source": "sources/github-completed-spoon-6-Neurocnl",
        "requirePlanApproval": True,
    }
