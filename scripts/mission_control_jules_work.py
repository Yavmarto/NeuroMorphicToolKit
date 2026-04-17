from __future__ import annotations

import fcntl
import os
import signal
import sys
import tempfile
import threading
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urljoin

import requests
from dotenv import load_dotenv

try:
    from scripts.jules_api import (
        JulesApiError,
        JulesClient,
        ResolvedSource,
        extract_pull_request,
        normalize_repo_identifier,
    )
except ImportError:
    from jules_api import (
        JulesApiError,
        JulesClient,
        ResolvedSource,
        extract_pull_request,
        normalize_repo_identifier,
    )


SCRIPT_DIR = Path(__file__).resolve().parent
ENV_PATH = SCRIPT_DIR / ".env"
GUIDE_PATH = SCRIPT_DIR.parent / "docs" / "jules" / "JULES_WORKSPACE_GUIDE.md"
load_dotenv(ENV_PATH)

SERVER_URL = (os.getenv("MISSION_CONTROL_SERVER_URL") or "").rstrip("/")
API_KEY = os.getenv("MISSION_CONTROL_API_KEY") or ""
JULES_API_KEY = os.getenv("JULES_API_KEY") or ""
AGENT_NAME = os.getenv("MISSION_CONTROL_JULES_AGENT_NAME", "jules-worker")
AGENT_ROLE = os.getenv("MISSION_CONTROL_JULES_AGENT_ROLE", "coder")
POLL_INTERVAL_SECONDS = float(os.getenv("MISSION_CONTROL_JULES_POLL_INTERVAL_SECONDS", "5"))
HEARTBEAT_INTERVAL_SECONDS = float(
    os.getenv("MISSION_CONTROL_JULES_HEARTBEAT_INTERVAL_SECONDS", "10")
)
SYNC_FAILURE_THRESHOLD = int(os.getenv("MISSION_CONTROL_JULES_SYNC_FAILURE_THRESHOLD", "3"))
MAX_CAPACITY = int(os.getenv("MISSION_CONTROL_JULES_MAX_CAPACITY", "1"))
RETRY_BASE_SECONDS = float(os.getenv("MISSION_CONTROL_JULES_RETRY_BASE_SECONDS", "10"))
RETRY_MAX_SECONDS = float(os.getenv("MISSION_CONTROL_JULES_RETRY_MAX_SECONDS", "120"))
REQUEST_TIMEOUT_SECONDS = 10
LOCK_FILE_PATH = Path(
    os.getenv(
        "MISSION_CONTROL_JULES_LOCK_FILE",
        str(Path(tempfile.gettempdir()) / "mission_control_jules_work.lock"),
    )
)
DEFAULT_SOURCE = (os.getenv("MISSION_CONTROL_JULES_DEFAULT_SOURCE") or "").strip() or None
DEFAULT_REPO = (os.getenv("MISSION_CONTROL_JULES_DEFAULT_REPO") or "").strip() or None
DEFAULT_BRANCH = (os.getenv("MISSION_CONTROL_JULES_DEFAULT_BRANCH") or "").strip() or None
WORKER_METADATA_KEY = "mission_control_jules"
REQUEST_METADATA_KEY = "request"
RUNTIME_METADATA_KEY = "runtime"
ACTIVE_SESSION_STATES = {"STATE_UNSPECIFIED", "QUEUED", "PLANNING", "IN_PROGRESS"}
BLOCKED_SESSION_STATES = {"AWAITING_PLAN_APPROVAL", "AWAITING_USER_FEEDBACK", "PAUSED"}
TERMINAL_SESSION_STATES = {"FAILED", "COMPLETED"}


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def build_headers(api_key: str, extra_headers: dict[str, str] | None = None) -> dict[str, str]:
    headers = {
        "Content-Type": "application/json",
        "x-api-key": api_key,
    }
    if extra_headers:
        headers.update(extra_headers)
    return headers


def validate_configuration(server_url: str, api_key: str, jules_api_key: str) -> None:
    if server_url and api_key and jules_api_key:
        return
    print(
        "❌ Error: MISSION_CONTROL_SERVER_URL, MISSION_CONTROL_API_KEY, or JULES_API_KEY "
        "not found in scripts/.env"
    )
    sys.exit(1)


def absolute_url(base_url: str, maybe_relative_url: str | None, fallback_path: str) -> str:
    if maybe_relative_url:
        return urljoin(f"{base_url}/", maybe_relative_url)
    return urljoin(f"{base_url}/", fallback_path.lstrip("/"))


class SingleInstanceLock:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._handle: Any | None = None

    def acquire(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        handle = self.path.open("w", encoding="utf-8")
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            handle.close()
            raise RuntimeError(
                f"Another Mission Control Jules worker instance is already running ({self.path})."
            ) from exc

        handle.seek(0)
        handle.truncate()
        handle.write(f"{os.getpid()}\n")
        handle.flush()
        self._handle = handle

    def release(self) -> None:
        if self._handle is None:
            return
        try:
            fcntl.flock(self._handle.fileno(), fcntl.LOCK_UN)
        finally:
            self._handle.close()
            self._handle = None


def extract_code_block(markdown_text: str, heading: str) -> str | None:
    lines = markdown_text.splitlines()
    target = f"### {heading}"
    for index, line in enumerate(lines):
        if line.strip() != target:
            continue
        in_code_block = False
        captured: list[str] = []
        for candidate in lines[index + 1 :]:
            if candidate.startswith("```"):
                if in_code_block:
                    return "\n".join(captured).strip()
                in_code_block = True
                continue
            if in_code_block:
                captured.append(candidate)
    return None


def load_prompt_templates(guide_path: Path = GUIDE_PATH) -> tuple[str, str]:
    guide_text = guide_path.read_text(encoding="utf-8")
    single_repo_template = extract_code_block(guide_text, "Single-repo task")
    launcher_template = extract_code_block(guide_text, "Launcher / control-plane task")
    if not single_repo_template or not launcher_template:
        raise RuntimeError(f"Could not extract Jules prompt templates from {guide_path}.")
    return single_repo_template, launcher_template


@dataclass(frozen=True)
class JulesTaskRequest:
    repo: str | None = None
    branch: str | None = None
    source: str | None = None
    require_plan_approval: bool = False

    @classmethod
    def from_task(cls, task: dict[str, Any]) -> JulesTaskRequest:
        metadata = task.get("metadata")
        if not isinstance(metadata, dict):
            return cls()
        jules_metadata = metadata.get(WORKER_METADATA_KEY)
        if not isinstance(jules_metadata, dict):
            return cls()
        request = jules_metadata.get(REQUEST_METADATA_KEY)
        if not isinstance(request, dict):
            return cls()

        repo = request.get("repo")
        branch = request.get("branch")
        source = request.get("source")
        require_plan_approval = bool(request.get("requirePlanApproval"))
        return cls(
            repo=normalize_repo_identifier(repo) if isinstance(repo, str) and repo.strip() else None,
            branch=branch.strip() if isinstance(branch, str) and branch.strip() else None,
            source=source.strip() if isinstance(source, str) and source.strip() else None,
            require_plan_approval=require_plan_approval,
        )

    def as_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {}
        if self.repo:
            payload["repo"] = self.repo
        if self.branch:
            payload["branch"] = self.branch
        if self.source:
            payload["source"] = self.source
        if self.require_plan_approval:
            payload["requirePlanApproval"] = True
        return payload


@dataclass
class ConnectionState:
    agent_id: int
    connection_id: str
    registered_agent_name: str
    heartbeat_url: str
    sse_url: str | None = None
    token_report_url: str | None = None
    last_heartbeat_monotonic: float = 0.0


@dataclass
class TrackedJulesTask:
    task_id: int
    title: str
    description: str
    request: JulesTaskRequest
    status: str | None = None
    assigned_to: str | None = None
    session_name: str | None = None
    session_id: str | None = None
    session_url: str | None = None
    state: str | None = None
    source: str | None = None
    repo: str | None = None
    branch: str | None = None
    last_activity_name: str | None = None
    last_activity_time: str | None = None
    pull_request_url: str | None = None
    pull_request_title: str | None = None
    failure_reason: str | None = None
    attention_required: bool = False
    terminal: bool = False
    last_polled_at: str | None = None
    last_progress_message: str | None = None
    last_sync_error: str | None = None
    consecutive_sync_failures: int = 0
    degraded_sync_commented: bool = False
    next_retry_monotonic: float = 0.0
    creation_comment_posted: bool = False
    runtime_known: bool = False

    @classmethod
    def from_task(cls, task: dict[str, Any]) -> TrackedJulesTask:
        request = JulesTaskRequest.from_task(task)
        metadata = task.get("metadata") if isinstance(task.get("metadata"), dict) else {}
        jules_metadata = (
            metadata.get(WORKER_METADATA_KEY) if isinstance(metadata, dict) else {}
        )
        runtime = (
            jules_metadata.get(RUNTIME_METADATA_KEY)
            if isinstance(jules_metadata, dict)
            else {}
        )
        runtime = runtime if isinstance(runtime, dict) else {}
        return cls(
            task_id=int(task["id"]),
            title=task.get("title") or f"Task {task['id']}",
            description=task.get("description") or "",
            request=request,
            status=task.get("status"),
            assigned_to=task.get("assigned_to"),
            session_name=runtime.get("sessionName"),
            session_id=runtime.get("sessionId"),
            session_url=runtime.get("sessionUrl"),
            state=runtime.get("state"),
            source=runtime.get("source"),
            repo=runtime.get("repo"),
            branch=runtime.get("branch"),
            last_activity_name=runtime.get("lastActivityName"),
            last_activity_time=runtime.get("lastActivityTime"),
            pull_request_url=runtime.get("pullRequestUrl"),
            pull_request_title=runtime.get("pullRequestTitle"),
            failure_reason=runtime.get("failureReason"),
            attention_required=bool(runtime.get("attentionRequired")),
            terminal=bool(runtime.get("terminal")),
            last_polled_at=runtime.get("lastPolledAt"),
            last_progress_message=runtime.get("lastProgressMessage"),
            last_sync_error=runtime.get("lastSyncError"),
            consecutive_sync_failures=int(runtime.get("consecutiveSyncFailures", 0) or 0),
            degraded_sync_commented=bool(runtime.get("degradedSyncCommented")),
            creation_comment_posted=bool(runtime.get("creationCommentPosted")),
            runtime_known=bool(runtime),
        )

    def counts_against_capacity(self) -> bool:
        return not self.terminal and not self.attention_required

    def runtime_payload(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "sessionName": self.session_name,
            "sessionId": self.session_id,
            "sessionUrl": self.session_url,
            "state": self.state,
            "lastActivityName": self.last_activity_name,
            "lastActivityTime": self.last_activity_time,
            "lastPolledAt": self.last_polled_at,
            "source": self.source,
            "repo": self.repo,
            "branch": self.branch,
            "pullRequestUrl": self.pull_request_url,
            "pullRequestTitle": self.pull_request_title,
            "failureReason": self.failure_reason,
            "attentionRequired": self.attention_required,
            "terminal": self.terminal,
            "lastProgressMessage": self.last_progress_message,
            "lastSyncError": self.last_sync_error,
            "consecutiveSyncFailures": self.consecutive_sync_failures,
            "degradedSyncCommented": self.degraded_sync_commented,
            "creationCommentPosted": self.creation_comment_posted,
        }
        return {key: value for key, value in payload.items() if value is not None}


class MissionControlJulesWorker:
    def __init__(
        self,
        *,
        server_url: str,
        api_key: str,
        jules_api_key: str,
        agent_name: str = AGENT_NAME,
        agent_role: str = AGENT_ROLE,
        session: requests.Session | Any | None = None,
        jules_client: JulesClient | Any | None = None,
        lock_file_path: Path | None = None,
        guide_path: Path = GUIDE_PATH,
        default_source: str | None = DEFAULT_SOURCE,
        default_repo: str | None = DEFAULT_REPO,
        default_branch: str | None = DEFAULT_BRANCH,
        max_capacity: int = MAX_CAPACITY,
        sync_failure_threshold: int = SYNC_FAILURE_THRESHOLD,
        retry_base_seconds: float = RETRY_BASE_SECONDS,
        retry_max_seconds: float = RETRY_MAX_SECONDS,
        manage_signals: bool = False,
    ) -> None:
        self.server_url = server_url.rstrip("/")
        self.api_key = api_key
        self.jules_api_key = jules_api_key
        self.agent_name = agent_name
        self.agent_role = agent_role
        self.session = session or requests.Session()
        self._owns_session = session is None
        self.jules_client = jules_client or JulesClient(jules_api_key)
        self._owns_jules_client = jules_client is None
        self.lock = SingleInstanceLock(lock_file_path or LOCK_FILE_PATH)
        self.connection: ConnectionState | None = None
        self.tracked_tasks: dict[int, TrackedJulesTask] = {}
        self.stop_event = threading.Event()
        self.shutdown_reason = "Worker shutdown requested."
        self.manage_signals = manage_signals
        self._previous_signal_handlers: dict[signal.Signals, Any] = {}
        self.single_repo_template, self.launcher_template = load_prompt_templates(guide_path)
        self.default_source = default_source
        self.default_repo = normalize_repo_identifier(default_repo) if default_repo else None
        self.default_branch = default_branch
        self.max_capacity = max(max_capacity, 1)
        self.sync_failure_threshold = max(sync_failure_threshold, 1)
        self.retry_base_seconds = max(retry_base_seconds, 1.0)
        self.retry_max_seconds = max(retry_max_seconds, self.retry_base_seconds)

    def headers(self, extra_headers: dict[str, str] | None = None) -> dict[str, str]:
        return build_headers(self.api_key, extra_headers)

    def install_signal_handlers(self) -> None:
        if not self.manage_signals:
            return
        for sig in (signal.SIGINT, signal.SIGTERM):
            try:
                self._previous_signal_handlers[sig] = signal.getsignal(sig)
                signal.signal(sig, self._handle_signal)
            except ValueError:
                continue

    def restore_signal_handlers(self) -> None:
        if not self.manage_signals:
            return
        for sig, previous in self._previous_signal_handlers.items():
            try:
                signal.signal(sig, previous)
            except ValueError:
                continue
        self._previous_signal_handlers.clear()

    def _handle_signal(self, signum: int, _frame: Any) -> None:
        signal_name = signal.Signals(signum).name
        print(f"\n🛑 Received {signal_name}. Preparing Mission Control Jules worker shutdown...")
        self.request_stop(f"Received {signal_name}.")

    def request_stop(self, reason: str) -> None:
        self.shutdown_reason = reason
        self.stop_event.set()

    def register_agent(self) -> None:
        print(f"🔌 Registering {self.agent_name}...")
        response = self.session.post(
            f"{self.server_url}/api/connect",
            headers=self.headers(),
            json={
                "tool_name": "jules",
                "agent_name": self.agent_name,
                "agent_role": self.agent_role,
            },
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
        agent_id = int(payload["agent_id"])
        self.connection = ConnectionState(
            agent_id=agent_id,
            connection_id=payload["connection_id"],
            registered_agent_name=payload.get("agent_name") or self.agent_name,
            heartbeat_url=absolute_url(
                self.server_url,
                payload.get("heartbeat_url"),
                f"/api/agents/{agent_id}/heartbeat",
            ),
            sse_url=absolute_url(self.server_url, payload.get("sse_url"), "/api/events")
            if payload.get("sse_url")
            else None,
            token_report_url=absolute_url(
                self.server_url,
                payload.get("token_report_url"),
                "/api/tokens",
            )
            if payload.get("token_report_url")
            else None,
        )
        print(
            f"✅ Registered {self.connection.registered_agent_name} "
            f"(agent_id={self.connection.agent_id}, connection_id={self.connection.connection_id})."
        )

    def run(self) -> int:
        try:
            self.lock.acquire()
        except RuntimeError as exc:
            print(f"❌ {exc}")
            return 1

        self.install_signal_handlers()
        try:
            self.register_agent()
            self.recover_tasks()

            print(f"\n📡 Syncing Jules sessions with {self.server_url}...")
            print(" (Mission Control queue polling is active. Press Ctrl+C to stop.)\n")

            while not self.stop_event.is_set():
                self.tick()
                self.stop_event.wait(POLL_INTERVAL_SECONDS)
            return 0
        finally:
            self.shutdown()
            self.restore_signal_handlers()
            self.lock.release()

    def tick(self) -> None:
        if self.connection is None:
            raise RuntimeError("Mission Control Jules worker is not connected.")

        self.maybe_send_heartbeat()
        for task_id in list(self.tracked_tasks):
            tracked_task = self.tracked_tasks.get(task_id)
            if tracked_task is None:
                continue
            self.sync_tracked_task(tracked_task)
            if tracked_task.terminal:
                self.tracked_tasks.pop(task_id, None)

        if self.active_capacity() >= self.max_capacity:
            return
        self.poll_queue()

    def active_capacity(self) -> int:
        return sum(1 for task in self.tracked_tasks.values() if task.counts_against_capacity())

    def maybe_send_heartbeat(self) -> None:
        if self.connection is None:
            return
        now = time.monotonic()
        if now - self.connection.last_heartbeat_monotonic < HEARTBEAT_INTERVAL_SECONDS:
            return

        try:
            response = self.session.post(
                self.connection.heartbeat_url,
                headers=self.headers(),
                json={},
                timeout=REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
            self.connection.last_heartbeat_monotonic = now
        except Exception as exc:
            print(f"⚠️ Heartbeat failed for {self.connection.registered_agent_name}: {exc}")

    def poll_queue(self) -> None:
        if self.connection is None:
            return
        try:
            response = self.session.get(
                f"{self.server_url}/api/tasks/queue",
                headers=self.headers({"x-agent-name": self.connection.registered_agent_name}),
                params={"max_capacity": 1},
                timeout=REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
            payload = response.json()
        except Exception as exc:
            print(f"⚠️ Queue polling failed for {self.agent_name}: {exc}")
            return

        reason = payload.get("reason")
        task = payload.get("task")
        if reason not in {"assigned", "continue_current"} or not isinstance(task, dict):
            return

        task_id = int(task["id"])
        if task_id in self.tracked_tasks:
            return

        hydrated_task = self.fetch_task(task_id)
        task_payload = hydrated_task or task
        tracked_task = TrackedJulesTask.from_task(task_payload)
        tracked_task.status = task_payload.get("status")
        tracked_task.assigned_to = task_payload.get("assigned_to")
        self.tracked_tasks[task_id] = tracked_task
        print(f"\n⚡ [{self.agent_name}] Queue dispatch for task {task_id} ({reason}).")
        self.sync_tracked_task(tracked_task)
        if tracked_task.terminal:
            self.tracked_tasks.pop(task_id, None)

    def recover_tasks(self) -> None:
        if self.connection is None:
            return
        recovered = 0
        for status in ("in_progress", "quality_review"):
            for task in self.list_tasks(status=status, assigned_to=self.connection.registered_agent_name):
                tracked_task = TrackedJulesTask.from_task(task)
                if not tracked_task.session_name or tracked_task.terminal:
                    continue
                if tracked_task.task_id in self.tracked_tasks:
                    continue
                self.tracked_tasks[tracked_task.task_id] = tracked_task
                recovered += 1
        if recovered:
            print(f"🔄 Recovered {recovered} Jules task(s) for background sync.")

    def list_tasks(self, *, status: str, assigned_to: str) -> list[dict[str, Any]]:
        response = self.session.get(
            f"{self.server_url}/api/tasks",
            headers=self.headers(),
            params={"status": status, "assigned_to": assigned_to},
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        payload = response.json()
        tasks = payload.get("tasks", [])
        return tasks if isinstance(tasks, list) else []

    def fetch_task(self, task_id: int) -> dict[str, Any]:
        try:
            response = self.session.get(
                f"{self.server_url}/api/tasks/{task_id}",
                headers=self.headers(),
                timeout=REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
            payload = response.json()
            task = payload.get("task")
            if isinstance(task, dict):
                return task
        except Exception as exc:
            print(f"⚠️ Failed to fetch task {task_id}: {exc}")
        return {}

    def sync_tracked_task(self, tracked_task: TrackedJulesTask) -> None:
        if time.monotonic() < tracked_task.next_retry_monotonic:
            return

        if tracked_task.session_name:
            self.sync_existing_session(tracked_task)
            return
        self.create_jules_session_for_task(tracked_task)

    def resolve_task_target(self, tracked_task: TrackedJulesTask) -> tuple[ResolvedSource, str, str]:
        request = tracked_task.request
        if request.source:
            resolved_source = self.jules_client.resolve_source(source_name=request.source)
        elif request.repo:
            resolved_source = self.jules_client.resolve_source(repo_identifier=request.repo)
        elif self.default_source:
            resolved_source = self.jules_client.resolve_source(source_name=self.default_source)
        elif self.default_repo:
            resolved_source = self.jules_client.resolve_source(repo_identifier=self.default_repo)
        else:
            raise JulesApiError(
                "No Jules routing metadata found. Set metadata.mission_control_jules.request.repo "
                "or .source, or configure a default Jules source/repo in the environment."
            )

        resolved_repo = request.repo or resolved_source.repo_identifier or self.default_repo
        if not resolved_repo:
            raise JulesApiError(
                f"Could not determine a repo identifier for Jules source {resolved_source.name}."
            )
        resolved_branch = self.jules_client.validate_branch(
            resolved_source,
            request.branch or self.default_branch,
        )
        return resolved_source, resolved_repo, resolved_branch

    def build_prompt(self, tracked_task: TrackedJulesTask, repo_identifier: str) -> str:
        repo_name = repo_identifier.split("/", 1)[1] if "/" in repo_identifier else repo_identifier
        template = (
            self.launcher_template
            if repo_name == "NeuroMorphicToolKit"
            else self.single_repo_template
        )
        preamble = (
            template.replace("<repo-name>", repo_name)
            .replace(
                "<task details>",
                f"Mission Control task title: {tracked_task.title}",
            )
            .replace(
                "<expected behavior>",
                "Complete the requested change, keep edits scoped to the target repo, and report the outcome in the Jules session.",
            )
        )
        description = tracked_task.description.strip() or "(No description provided.)"
        return (
            f"{preamble}\n\n"
            f"Mission Control task title: {tracked_task.title}\n"
            f"Mission Control task description:\n{description}"
        ).strip()

    def create_jules_session_for_task(self, tracked_task: TrackedJulesTask) -> None:
        try:
            resolved_source, resolved_repo, resolved_branch = self.resolve_task_target(tracked_task)
            session_payload = self.jules_client.create_session(
                title=tracked_task.title[:120],
                prompt=self.build_prompt(tracked_task, resolved_repo),
                source_name=resolved_source.name,
                branch=resolved_branch,
                require_plan_approval=tracked_task.request.require_plan_approval,
                automation_mode="AUTO_CREATE_PR",
            )
        except JulesApiError as exc:
            if exc.is_transient:
                self.handle_transient_sync_failure(tracked_task, exc)
                return
            self.move_task_to_quality_review(
                tracked_task,
                failure_reason=str(exc),
                note="Jules session could not be created with the provided routing metadata.",
            )
            return
        except Exception as exc:
            self.handle_transient_sync_failure(tracked_task, exc)
            return

        tracked_task.session_name = session_payload.get("name")
        tracked_task.session_id = session_payload.get("id")
        tracked_task.session_url = session_payload.get("url")
        tracked_task.state = session_payload.get("state")
        tracked_task.source = resolved_source.name
        tracked_task.repo = resolved_repo
        tracked_task.branch = resolved_branch
        tracked_task.attention_required = False
        tracked_task.terminal = False
        tracked_task.failure_reason = None
        tracked_task.last_sync_error = None
        tracked_task.consecutive_sync_failures = 0
        tracked_task.degraded_sync_commented = False
        tracked_task.next_retry_monotonic = 0.0
        tracked_task.last_polled_at = utc_now_iso()

        self.persist_task_runtime(tracked_task, status="in_progress")
        self.post_task_comment(
            tracked_task.task_id,
            self.build_creation_comment(tracked_task),
        )
        tracked_task.creation_comment_posted = True
        self.persist_task_runtime(tracked_task, status="in_progress")

    def sync_existing_session(self, tracked_task: TrackedJulesTask) -> None:
        try:
            session_payload = self.jules_client.get_session(tracked_task.session_name or "")
            activities = self.jules_client.list_activities(tracked_task.session_name or "")
        except JulesApiError as exc:
            if exc.is_transient:
                self.handle_transient_sync_failure(tracked_task, exc)
                return
            self.move_task_to_quality_review(
                tracked_task,
                failure_reason=str(exc),
                note="Jules session sync hit a non-retryable API error.",
            )
            return
        except Exception as exc:
            self.handle_transient_sync_failure(tracked_task, exc)
            return

        tracked_task.last_polled_at = utc_now_iso()
        tracked_task.state = session_payload.get("state") or tracked_task.state
        tracked_task.session_url = session_payload.get("url") or tracked_task.session_url
        tracked_task.session_id = session_payload.get("id") or tracked_task.session_id
        pull_request = extract_pull_request(session_payload) or {}
        tracked_task.pull_request_url = pull_request.get("url") or tracked_task.pull_request_url
        tracked_task.pull_request_title = pull_request.get("title") or tracked_task.pull_request_title
        tracked_task.last_sync_error = None
        tracked_task.consecutive_sync_failures = 0
        tracked_task.degraded_sync_commented = False
        tracked_task.next_retry_monotonic = 0.0

        latest_activity = activities[-1] if activities else None
        latest_activity_name = self.activity_name(latest_activity)
        latest_activity_kind = self.activity_kind(latest_activity)
        latest_activity_time = latest_activity.get("createTime") if isinstance(latest_activity, dict) else None
        previous_activity_name = tracked_task.last_activity_name

        tracked_task.last_activity_name = latest_activity_name or tracked_task.last_activity_name
        tracked_task.last_activity_time = latest_activity_time or tracked_task.last_activity_time
        tracked_task.last_progress_message = self.latest_progress_message(activities)

        comment = self.build_state_comment(
            tracked_task,
            activities,
            latest_activity_name,
            latest_activity_kind,
            previous_activity_name,
        )
        if comment:
            self.post_task_comment(tracked_task.task_id, comment)

        tracked_task.failure_reason = self.failure_reason_from_session(tracked_task, activities)
        tracked_task.attention_required = tracked_task.state in BLOCKED_SESSION_STATES or tracked_task.state == "FAILED"
        tracked_task.terminal = tracked_task.state in TERMINAL_SESSION_STATES

        target_status = self.map_task_status(tracked_task.state)
        self.persist_task_runtime(tracked_task, status=target_status)

    def handle_transient_sync_failure(self, tracked_task: TrackedJulesTask, exc: Exception) -> None:
        tracked_task.consecutive_sync_failures += 1
        tracked_task.last_sync_error = str(exc)
        tracked_task.last_polled_at = utc_now_iso()
        tracked_task.next_retry_monotonic = time.monotonic() + self.retry_delay_seconds(
            tracked_task.consecutive_sync_failures
        )
        self.persist_task_runtime(tracked_task, status=None)
        if (
            tracked_task.consecutive_sync_failures >= self.sync_failure_threshold
            and not tracked_task.degraded_sync_commented
        ):
            self.post_task_comment(
                tracked_task.task_id,
                self.build_degraded_sync_comment(tracked_task),
            )
            tracked_task.degraded_sync_commented = True
            self.persist_task_runtime(tracked_task, status=None)

    def move_task_to_quality_review(
        self,
        tracked_task: TrackedJulesTask,
        *,
        failure_reason: str,
        note: str,
    ) -> None:
        tracked_task.failure_reason = failure_reason
        tracked_task.attention_required = True
        tracked_task.terminal = False
        tracked_task.last_polled_at = utc_now_iso()
        tracked_task.last_sync_error = None
        tracked_task.next_retry_monotonic = 0.0
        self.persist_task_runtime(tracked_task, status="quality_review")
        self.post_task_comment(
            tracked_task.task_id,
            "\n".join(
                [
                    note,
                    f"Reason: {failure_reason}",
                    f"Agent: {self.agent_name}",
                    f"Jules session: {tracked_task.session_url or 'not created yet'}",
                ]
            ),
        )
        self.tracked_tasks.pop(tracked_task.task_id, None)

    def retry_delay_seconds(self, consecutive_failures: int) -> float:
        return min(self.retry_max_seconds, self.retry_base_seconds * (2 ** (consecutive_failures - 1)))

    def activity_name(self, activity: dict[str, Any] | None) -> str | None:
        if not isinstance(activity, dict):
            return None
        if isinstance(activity.get("name"), str) and activity["name"].strip():
            return activity["name"]
        kind = self.activity_kind(activity)
        if kind:
            return kind
        return None

    def activity_kind(self, activity: dict[str, Any] | None) -> str | None:
        if not isinstance(activity, dict):
            return None
        for key in (
            "planGenerated",
            "planApproved",
            "userMessaged",
            "agentMessaged",
            "progressUpdated",
            "sessionCompleted",
            "sessionFailed",
        ):
            if key in activity:
                return key
        return None

    def latest_progress_message(self, activities: list[dict[str, Any]]) -> str | None:
        for activity in reversed(activities):
            if not isinstance(activity, dict):
                continue
            progress = activity.get("progressUpdated")
            if isinstance(progress, dict):
                title = progress.get("title")
                description = progress.get("description")
                if title and description:
                    return f"{title}: {description}"
                if title:
                    return title
                if description:
                    return description
            agent_message = activity.get("agentMessaged")
            if isinstance(agent_message, dict) and agent_message.get("agentMessage"):
                return agent_message["agentMessage"]
        return None

    def plan_step_titles(self, activities: list[dict[str, Any]]) -> list[str]:
        for activity in reversed(activities):
            plan_generated = activity.get("planGenerated")
            if not isinstance(plan_generated, dict):
                continue
            plan = plan_generated.get("plan")
            if not isinstance(plan, dict):
                continue
            steps = plan.get("steps")
            if not isinstance(steps, list):
                continue
            return [
                step.get("title")
                for step in steps
                if isinstance(step, dict) and step.get("title")
            ]
        return []

    def blocking_message(self, activities: list[dict[str, Any]]) -> str:
        for activity in reversed(activities):
            agent_message = activity.get("agentMessaged")
            if isinstance(agent_message, dict) and agent_message.get("agentMessage"):
                return agent_message["agentMessage"]
            progress = activity.get("progressUpdated")
            if isinstance(progress, dict):
                title = progress.get("title")
                description = progress.get("description")
                if title and description:
                    return f"{title}: {description}"
                if title:
                    return title
                if description:
                    return description
            if isinstance(activity.get("planGenerated"), dict):
                plan_steps = self.plan_step_titles([activity])
                if plan_steps:
                    return f"Plan ready: {', '.join(plan_steps)}"
                return "A Jules plan is ready for review."
        return "Jules is waiting for human input."

    def failure_reason_from_session(
        self,
        tracked_task: TrackedJulesTask,
        activities: list[dict[str, Any]],
    ) -> str | None:
        if tracked_task.state != "FAILED":
            return None
        for activity in reversed(activities):
            session_failed = activity.get("sessionFailed")
            if not isinstance(session_failed, dict):
                continue
            for key in ("failureReason", "reason", "message", "error", "errorMessage"):
                value = session_failed.get(key)
                if isinstance(value, str) and value.strip():
                    return value.strip()
        return tracked_task.failure_reason or "Jules reported a failed session."

    def build_state_comment(
        self,
        tracked_task: TrackedJulesTask,
        activities: list[dict[str, Any]],
        latest_activity_name: str | None,
        latest_activity_kind: str | None,
        previous_activity_name: str | None,
    ) -> str | None:
        activity_changed = latest_activity_name and latest_activity_name != previous_activity_name

        if activity_changed and latest_activity_kind == "planGenerated":
            steps = self.plan_step_titles(activities)
            numbered_steps = "\n".join(
                f"{index}. {title}" for index, title in enumerate(steps, start=1)
            )
            return "\n".join(
                [
                    "Jules generated a plan for this task.",
                    f"Session: {tracked_task.session_url or tracked_task.session_name or 'unknown'}",
                    "Plan steps:",
                    numbered_steps,
                ]
            )

        if tracked_task.state in BLOCKED_SESSION_STATES and activity_changed:
            return "\n".join(
                [
                    f"Jules is waiting for attention ({tracked_task.state}).",
                    f"Session: {tracked_task.session_url or tracked_task.session_name or 'unknown'}",
                    f"Latest message: {self.blocking_message(activities)}",
                ]
            )

        if tracked_task.state == "FAILED" and activity_changed:
            failure_reason = self.failure_reason_from_session(tracked_task, activities) or "Unknown failure"
            return "\n".join(
                [
                    "Jules session failed.",
                    f"Session: {tracked_task.session_url or tracked_task.session_name or 'unknown'}",
                    f"Reason: {failure_reason}",
                ]
            )

        if tracked_task.state == "COMPLETED" and activity_changed:
            parts = [
                "Jules completed this task.",
                f"Session: {tracked_task.session_url or tracked_task.session_name or 'unknown'}",
            ]
            if tracked_task.pull_request_url:
                pr_line = tracked_task.pull_request_url
                if tracked_task.pull_request_title:
                    pr_line = f"{tracked_task.pull_request_title} — {tracked_task.pull_request_url}"
                parts.append(f"Pull request: {pr_line}")
            return "\n".join(parts)

        return None

    def build_creation_comment(self, tracked_task: TrackedJulesTask) -> str:
        return "\n".join(
            [
                "Jules session created for this Mission Control task.",
                f"Session: {tracked_task.session_url or tracked_task.session_name or 'unknown'}",
                f"Target: {tracked_task.repo or 'unknown'} @ {tracked_task.branch or 'unknown'}",
            ]
        )

    def build_degraded_sync_comment(self, tracked_task: TrackedJulesTask) -> str:
        return "\n".join(
            [
                "Jules sync is degraded and will keep retrying.",
                f"Consecutive failures: {tracked_task.consecutive_sync_failures}",
                f"Last error: {tracked_task.last_sync_error or 'unknown'}",
                f"Session: {tracked_task.session_url or tracked_task.session_name or 'not created yet'}",
            ]
        )

    def map_task_status(self, session_state: str | None) -> str:
        if session_state == "COMPLETED":
            return "done"
        if session_state in BLOCKED_SESSION_STATES or session_state == "FAILED":
            return "quality_review"
        return "in_progress"

    def build_task_metadata(self, tracked_task: TrackedJulesTask) -> dict[str, Any]:
        existing_task = self.fetch_task(tracked_task.task_id)
        existing_metadata = existing_task.get("metadata")
        metadata: dict[str, Any] = (
            dict(existing_metadata) if isinstance(existing_metadata, dict) else {}
        )
        jules_metadata = metadata.get(WORKER_METADATA_KEY)
        jules_payload = dict(jules_metadata) if isinstance(jules_metadata, dict) else {}

        request_payload = dict(tracked_task.request.as_dict())
        if not request_payload and isinstance(jules_payload.get(REQUEST_METADATA_KEY), dict):
            request_payload = dict(jules_payload[REQUEST_METADATA_KEY])
        if request_payload:
            jules_payload[REQUEST_METADATA_KEY] = request_payload

        jules_payload[RUNTIME_METADATA_KEY] = tracked_task.runtime_payload()
        metadata[WORKER_METADATA_KEY] = jules_payload
        return metadata

    def persist_task_runtime(self, tracked_task: TrackedJulesTask, *, status: str | None) -> None:
        payload: dict[str, Any] = {"metadata": self.build_task_metadata(tracked_task)}
        if status is not None and self.connection is not None:
            payload["status"] = status
            payload["assigned_to"] = self.connection.registered_agent_name
            tracked_task.status = status
            tracked_task.assigned_to = self.connection.registered_agent_name
        self.update_task(tracked_task.task_id, payload)

    def update_task(self, task_id: int, payload: dict[str, Any]) -> dict[str, Any]:
        response = self.session.put(
            f"{self.server_url}/api/tasks/{task_id}",
            headers=self.headers(),
            json=payload,
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        return response.json()

    def post_task_comment(self, task_id: int, content: str) -> None:
        try:
            response = self.session.post(
                f"{self.server_url}/api/tasks/{task_id}/comments",
                headers=self.headers(),
                json={
                    "author": self.connection.registered_agent_name if self.connection else self.agent_name,
                    "content": content,
                },
                timeout=REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
        except Exception as exc:
            print(f"⚠️ Failed to post comment for task {task_id}: {exc}")

    def disconnect(self) -> None:
        if self.connection is None:
            return
        try:
            response = self.session.delete(
                f"{self.server_url}/api/connect",
                headers=self.headers(),
                json={"connection_id": self.connection.connection_id},
                timeout=REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
            print(f"🔌 Disconnected {self.connection.registered_agent_name}.")
        except Exception as exc:
            print(f"⚠️ Failed to disconnect {self.agent_name}: {exc}")

    def shutdown(self) -> None:
        self.disconnect()
        if self._owns_jules_client and hasattr(self.jules_client, "close"):
            self.jules_client.close()
        if self._owns_session and hasattr(self.session, "close"):
            self.session.close()


def main() -> int:
    validate_configuration(SERVER_URL, API_KEY, JULES_API_KEY)
    print("🚀 Starting Mission Control Jules Worker...")
    worker = MissionControlJulesWorker(
        server_url=SERVER_URL,
        api_key=API_KEY,
        jules_api_key=JULES_API_KEY,
        manage_signals=True,
    )
    return worker.run()


if __name__ == "__main__":
    raise SystemExit(main())
