from __future__ import annotations

import fcntl
import os
import shlex
import signal
import subprocess
import sys
import tempfile
import threading
import time
from collections import deque
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any
from urllib.parse import urljoin

import requests
from dotenv import load_dotenv

# --- ENVIRONMENT CONFIGURATION ---
SCRIPT_DIR = Path(__file__).resolve().parent
ENV_PATH = SCRIPT_DIR / ".env"
load_dotenv(ENV_PATH)

SERVER_URL = (os.getenv("MISSION_CONTROL_SERVER_URL") or "").rstrip("/")
API_KEY = os.getenv("MISSION_CONTROL_API_KEY") or ""
POLL_INTERVAL_SECONDS = float(os.getenv("MISSION_CONTROL_POLL_INTERVAL_SECONDS", "2"))
HEARTBEAT_INTERVAL_SECONDS = float(
    os.getenv("MISSION_CONTROL_HEARTBEAT_INTERVAL_SECONDS", "10")
)
PROCESS_TERMINATE_TIMEOUT_SECONDS = float(
    os.getenv("MISSION_CONTROL_PROCESS_TERMINATE_TIMEOUT_SECONDS", "5")
)
OUTPUT_TAIL_LINES = int(os.getenv("MISSION_CONTROL_OUTPUT_TAIL_LINES", "40"))
COMMENT_OUTPUT_LINES = int(os.getenv("MISSION_CONTROL_COMMENT_OUTPUT_LINES", "12"))
COMMENT_OUTPUT_CHAR_LIMIT = int(
    os.getenv("MISSION_CONTROL_COMMENT_OUTPUT_CHAR_LIMIT", "2000")
)
LOCK_FILE_PATH = Path(
    os.getenv(
        "MISSION_CONTROL_WORKER_LOCK_FILE",
        str(Path(tempfile.gettempdir()) / "mission_control_work.lock"),
    )
)
REQUEST_TIMEOUT_SECONDS = 10
WORKER_METADATA_KEY = "mission_control_worker"

# Easily add or remove agents here.
AGENTS_CONFIG = [
    {
        "agent_name": "claude-code-worker",
        "tool_name": "claude-code",
        "role": "coder",
        "description_prefix": "Execute this task automatically: ",
        "command_template": "claude {description}",
    },
    {
        "agent_name": "codex-worker",
        "tool_name": "codex",
        "role": "coder",
        "description_prefix": "",
        "command_template": "codex exec --full-auto {description}",
    },
]


def build_headers(api_key: str, extra_headers: dict[str, str] | None = None) -> dict[str, str]:
    headers = {
        "Content-Type": "application/json",
        "x-api-key": api_key,
    }
    if extra_headers:
        headers.update(extra_headers)
    return headers


def validate_configuration(server_url: str, api_key: str) -> None:
    if server_url and api_key:
        return
    print("❌ Error: MISSION_CONTROL_SERVER_URL or MISSION_CONTROL_API_KEY not found in scripts/.env")
    print("Please check your .env file in the 'scripts' directory.")
    sys.exit(1)


def absolute_url(base_url: str, maybe_relative_url: str | None, fallback_path: str) -> str:
    if maybe_relative_url:
        return urljoin(f"{base_url}/", maybe_relative_url)
    return urljoin(f"{base_url}/", fallback_path.lstrip("/"))


def bounded_output_excerpt(lines: list[str]) -> str:
    excerpt_lines = lines[-COMMENT_OUTPUT_LINES:]
    excerpt = "\n".join(excerpt_lines).strip()
    if len(excerpt) <= COMMENT_OUTPUT_CHAR_LIMIT:
        return excerpt
    return excerpt[-COMMENT_OUTPUT_CHAR_LIMIT:].lstrip()


@dataclass(frozen=True)
class AgentConfig:
    agent_name: str
    tool_name: str
    role: str
    description_prefix: str
    command_template: str


@dataclass
class ActiveRun:
    task_id: int
    command: str
    process: subprocess.Popen[str]
    started_at: float = field(default_factory=time.time)
    output_lines: deque[str] = field(
        default_factory=lambda: deque(maxlen=OUTPUT_TAIL_LINES)
    )
    output_lock: threading.Lock = field(default_factory=threading.Lock)
    reader_thread: threading.Thread | None = None

    def snapshot_output(self) -> list[str]:
        with self.output_lock:
            return list(self.output_lines)


@dataclass
class AgentRuntimeState:
    config: AgentConfig
    agent_id: int
    connection_id: str
    heartbeat_url: str
    registered_agent_name: str
    sse_url: str | None = None
    token_report_url: str | None = None
    last_heartbeat_monotonic: float = 0.0
    active_run: ActiveRun | None = None


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
                f"Another Mission Control worker instance is already running ({self.path})."
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


class MissionControlWorker:
    def __init__(
        self,
        server_url: str,
        api_key: str,
        agent_configs: list[AgentConfig | dict[str, str]] | None = None,
        session: requests.Session | Any | None = None,
        lock_file_path: Path | None = None,
        manage_signals: bool = False,
    ) -> None:
        self.server_url = server_url.rstrip("/")
        self.api_key = api_key
        self.session = session or requests.Session()
        self._owns_session = session is None
        raw_configs = agent_configs or AGENTS_CONFIG
        self.agent_configs = [
            cfg if isinstance(cfg, AgentConfig) else AgentConfig(**cfg)
            for cfg in raw_configs
        ]
        self.runtime_states: list[AgentRuntimeState] = []
        self.stop_event = threading.Event()
        self.shutdown_reason = "Worker shutdown requested."
        self.lock = SingleInstanceLock(lock_file_path or LOCK_FILE_PATH)
        self.manage_signals = manage_signals
        self._previous_signal_handlers: dict[signal.Signals, Any] = {}

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
        print(f"\n🛑 Received {signal_name}. Preparing Mission Control worker shutdown...")
        self.request_stop(f"Received {signal_name}.")

    def request_stop(self, reason: str) -> None:
        self.shutdown_reason = reason
        self.stop_event.set()

    def register_agents(self) -> None:
        self.runtime_states = []
        for config in self.agent_configs:
            print(f"🔌 Registering {config.agent_name}...")
            try:
                response = self.session.post(
                    f"{self.server_url}/api/connect",
                    headers=self.headers(),
                    json={
                        "tool_name": config.tool_name,
                        "agent_name": config.agent_name,
                        "agent_role": config.role,
                    },
                    timeout=REQUEST_TIMEOUT_SECONDS,
                )
                response.raise_for_status()
                payload = response.json()
            except Exception as exc:
                print(f"❌ Failed to register {config.agent_name}: {exc}")
                continue

            agent_id = int(payload["agent_id"])
            registered_name = payload.get("agent_name") or config.agent_name
            heartbeat_url = absolute_url(
                self.server_url,
                payload.get("heartbeat_url"),
                f"/api/agents/{agent_id}/heartbeat",
            )
            state = AgentRuntimeState(
                config=config,
                agent_id=agent_id,
                connection_id=payload["connection_id"],
                heartbeat_url=heartbeat_url,
                registered_agent_name=registered_name,
                sse_url=absolute_url(
                    self.server_url,
                    payload.get("sse_url"),
                    "/api/events",
                )
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
            self.runtime_states.append(state)
            print(
                f"✅ Registered {state.registered_agent_name} "
                f"(agent_id={state.agent_id}, connection_id={state.connection_id})."
            )

    def run(self) -> int:
        try:
            self.lock.acquire()
        except RuntimeError as exc:
            print(f"❌ {exc}")
            return 1

        self.install_signal_handlers()
        try:
            self.register_agents()
            if not self.runtime_states:
                print("❌ No Mission Control agents could be registered.")
                return 1

            print(f"\n📡 Listening for tasks from {self.server_url}...")
            print(" (Queue polling is active. Press Ctrl+C to stop.)\n")

            while not self.stop_event.is_set():
                self.tick()
                self.stop_event.wait(POLL_INTERVAL_SECONDS)
            return 0
        finally:
            self.shutdown()
            self.restore_signal_handlers()
            self.lock.release()

    def tick(self) -> None:
        for state in self.runtime_states:
            self.maybe_send_heartbeat(state)
            if state.active_run is not None:
                self.maybe_finalize_active_run(state)
                continue
            self.poll_and_start_task(state)

    def maybe_send_heartbeat(self, state: AgentRuntimeState) -> None:
        now = time.monotonic()
        if now - state.last_heartbeat_monotonic < HEARTBEAT_INTERVAL_SECONDS:
            return

        try:
            response = self.session.get(
                state.heartbeat_url,
                headers=self.headers(),
                timeout=REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
            state.last_heartbeat_monotonic = now
        except Exception as exc:
            print(f"⚠️ Heartbeat failed for {state.registered_agent_name}: {exc}")

    def poll_and_start_task(self, state: AgentRuntimeState) -> None:
        try:
            response = self.session.get(
                f"{self.server_url}/api/tasks/queue",
                headers=self.headers({"x-agent-name": state.registered_agent_name}),
                params={"max_capacity": 1},
                timeout=REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
            payload = response.json()
        except Exception as exc:
            print(f"⚠️ Queue polling failed for {state.registered_agent_name}: {exc}")
            return

        reason = payload.get("reason")
        task = payload.get("task")
        if reason not in {"assigned", "continue_current"} or not task:
            return

        task_id = int(task["id"])
        print(
            f"\n⚡ [{state.registered_agent_name}] "
            f"Queue dispatch for task {task_id} ({reason})."
        )
        self.start_task(state, task)

    def start_task(self, state: AgentRuntimeState, task: dict[str, Any]) -> None:
        task_id = int(task["id"])
        if state.active_run is not None:
            return

        try:
            self.update_task(
                task_id,
                {
                    "status": "in_progress",
                    "assigned_to": state.registered_agent_name,
                },
            )
        except Exception as exc:
            print(f"⚠️ Failed to mark task {task_id} as in_progress: {exc}")
            return

        prefix = state.config.description_prefix
        raw_description = prefix + (task.get("description") or "")
        safe_description = shlex.quote(raw_description)
        command = state.config.command_template.format(description=safe_description)
        print(f"🏃 [{state.registered_agent_name}] Running: {command}")

        try:
            process = subprocess.Popen(
                command,
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                start_new_session=True,
            )
        except Exception as exc:
            print(f"❌ Failed to start task {task_id}: {exc}")
            self.handle_failed_run(
                state,
                task_id=task_id,
                command=command,
                started_at=time.time(),
                finished_at=time.time(),
                exit_code=None,
                output_lines=[],
                note=f"Local process failed to start: {exc}",
            )
            return

        run = ActiveRun(task_id=task_id, command=command, process=process)
        run.reader_thread = threading.Thread(
            target=self.stream_process_output,
            args=(state, run),
            daemon=True,
        )
        state.active_run = run
        run.reader_thread.start()

    def stream_process_output(self, state: AgentRuntimeState, run: ActiveRun) -> None:
        if run.process.stdout is None:
            return
        try:
            for line in iter(run.process.stdout.readline, ""):
                sys.stdout.write(line)
                sys.stdout.flush()
                with run.output_lock:
                    run.output_lines.append(line.rstrip("\n"))
        finally:
            run.process.stdout.close()
            print(f"\n🧵 Output stream closed for {state.registered_agent_name} task {run.task_id}.")

    def maybe_finalize_active_run(self, state: AgentRuntimeState) -> None:
        run = state.active_run
        if run is None:
            return
        return_code = run.process.poll()
        if return_code is None:
            return

        if run.reader_thread is not None:
            run.reader_thread.join(timeout=1)

        finished_at = time.time()
        output_lines = run.snapshot_output()
        state.active_run = None

        if return_code == 0:
            self.handle_successful_run(
                state,
                task_id=run.task_id,
                command=run.command,
                started_at=run.started_at,
                finished_at=finished_at,
                exit_code=return_code,
                output_lines=output_lines,
            )
            return

        self.handle_failed_run(
            state,
            task_id=run.task_id,
            command=run.command,
            started_at=run.started_at,
            finished_at=finished_at,
            exit_code=return_code,
            output_lines=output_lines,
            note=f"Local process exited with code {return_code}.",
        )

    def handle_successful_run(
        self,
        state: AgentRuntimeState,
        task_id: int,
        command: str,
        started_at: float,
        finished_at: float,
        exit_code: int,
        output_lines: list[str],
    ) -> None:
        payload = {
            "status": "done",
            "assigned_to": state.registered_agent_name,
            "metadata": self.build_task_metadata(
                task_id=task_id,
                state=state,
                command=command,
                started_at=started_at,
                finished_at=finished_at,
                exit_code=exit_code,
                task_status="done",
                output_lines=output_lines,
                note="Local run completed successfully.",
            ),
        }
        try:
            self.update_task(task_id, payload)
        except Exception as exc:
            print(f"⚠️ Failed to mark task {task_id} as done: {exc}")

        self.post_task_comment(
            task_id,
            state.registered_agent_name,
            self.build_comment(
                "completed",
                state,
                exit_code=exit_code,
                started_at=started_at,
                finished_at=finished_at,
                output_lines=output_lines,
                note="Local run completed successfully.",
            ),
        )
        print(f"✅ [{state.registered_agent_name}] Task {task_id} completed.")

    def handle_failed_run(
        self,
        state: AgentRuntimeState,
        task_id: int,
        command: str,
        started_at: float,
        finished_at: float,
        exit_code: int | None,
        output_lines: list[str],
        note: str,
    ) -> None:
        payload = {
            "status": "assigned",
            "assigned_to": state.registered_agent_name,
            "metadata": self.build_task_metadata(
                task_id=task_id,
                state=state,
                command=command,
                started_at=started_at,
                finished_at=finished_at,
                exit_code=exit_code,
                task_status="assigned",
                output_lines=output_lines,
                note=note,
            ),
        }
        try:
            self.update_task(task_id, payload)
        except Exception as exc:
            print(f"⚠️ Failed to requeue task {task_id}: {exc}")

        self.post_task_comment(
            task_id,
            state.registered_agent_name,
            self.build_comment(
                "failed",
                state,
                exit_code=exit_code,
                started_at=started_at,
                finished_at=finished_at,
                output_lines=output_lines,
                note=note,
            ),
        )
        print(f"⚠️ [{state.registered_agent_name}] Task {task_id} returned to assigned.")

    def build_task_metadata(
        self,
        task_id: int,
        state: AgentRuntimeState,
        command: str,
        started_at: float,
        finished_at: float,
        exit_code: int | None,
        task_status: str,
        output_lines: list[str],
        note: str,
    ) -> dict[str, Any]:
        existing_task = self.fetch_task(task_id)
        existing_metadata = existing_task.get("metadata")
        metadata: dict[str, Any] = (
            dict(existing_metadata) if isinstance(existing_metadata, dict) else {}
        )
        metadata[WORKER_METADATA_KEY] = {
            "agent_id": state.agent_id,
            "agent_name": state.registered_agent_name,
            "tool_name": state.config.tool_name,
            "connection_id": state.connection_id,
            "command": command,
            "task_id": task_id,
            "status": task_status,
            "started_at": int(started_at),
            "finished_at": int(finished_at),
            "duration_seconds": round(max(finished_at - started_at, 0.0), 3),
            "exit_code": exit_code,
            "note": note,
            "output_tail": output_lines[-COMMENT_OUTPUT_LINES:],
        }
        return metadata

    def build_comment(
        self,
        outcome: str,
        state: AgentRuntimeState,
        exit_code: int | None,
        started_at: float,
        finished_at: float,
        output_lines: list[str],
        note: str,
    ) -> str:
        excerpt = bounded_output_excerpt(output_lines)
        parts = [
            f"Mission Control worker {outcome} the local run.",
            f"Agent: {state.registered_agent_name}",
            f"Tool: {state.config.tool_name}",
            f"Exit code: {exit_code if exit_code is not None else 'n/a'}",
            f"Duration: {round(max(finished_at - started_at, 0.0), 3)}s",
            f"Note: {note}",
        ]
        if excerpt:
            parts.extend(
                [
                    "",
                    "Recent output:",
                    "~~~text",
                    excerpt,
                    "~~~",
                ]
            )
        return "\n".join(parts)

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
            print(f"⚠️ Failed to fetch task {task_id} for metadata merge: {exc}")
        return {}

    def update_task(self, task_id: int, payload: dict[str, Any]) -> dict[str, Any]:
        response = self.session.put(
            f"{self.server_url}/api/tasks/{task_id}",
            headers=self.headers(),
            json=payload,
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
        response.raise_for_status()
        return response.json()

    def post_task_comment(self, task_id: int, author: str, content: str) -> None:
        try:
            response = self.session.post(
                f"{self.server_url}/api/tasks/{task_id}/comments",
                headers=self.headers(),
                json={
                    "author": author,
                    "content": content,
                },
                timeout=REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
        except Exception as exc:
            print(f"⚠️ Failed to post comment for task {task_id}: {exc}")

    def disconnect(self, state: AgentRuntimeState) -> None:
        try:
            response = self.session.delete(
                f"{self.server_url}/api/connect",
                headers=self.headers(),
                json={"connection_id": state.connection_id},
                timeout=REQUEST_TIMEOUT_SECONDS,
            )
            response.raise_for_status()
            print(f"🔌 Disconnected {state.registered_agent_name}.")
        except Exception as exc:
            print(f"⚠️ Failed to disconnect {state.registered_agent_name}: {exc}")

    def terminate_process_group(self, process: subprocess.Popen[str]) -> None:
        if process.poll() is not None:
            return
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=PROCESS_TERMINATE_TIMEOUT_SECONDS)
        except Exception:
            try:
                os.killpg(process.pid, signal.SIGKILL)
                process.wait(timeout=PROCESS_TERMINATE_TIMEOUT_SECONDS)
            except Exception:
                process.kill()
                process.wait(timeout=PROCESS_TERMINATE_TIMEOUT_SECONDS)

    def abort_active_run(self, state: AgentRuntimeState) -> None:
        run = state.active_run
        if run is None:
            return

        if run.process.poll() is None:
            self.terminate_process_group(run.process)
        if run.reader_thread is not None:
            run.reader_thread.join(timeout=1)

        finished_at = time.time()
        output_lines = run.snapshot_output()
        exit_code = run.process.poll()
        self.handle_failed_run(
            state,
            task_id=run.task_id,
            command=run.command,
            started_at=run.started_at,
            finished_at=finished_at,
            exit_code=exit_code,
            output_lines=output_lines,
            note=f"Worker stopped before the local run completed. {self.shutdown_reason}",
        )
        state.active_run = None

    def shutdown(self) -> None:
        for state in self.runtime_states:
            if state.active_run is not None:
                self.abort_active_run(state)
            self.disconnect(state)

        if self._owns_session and hasattr(self.session, "close"):
            self.session.close()


def main() -> int:
    validate_configuration(SERVER_URL, API_KEY)
    print("🚀 Starting Multi-Agent Mission Control Worker...")
    worker = MissionControlWorker(
        server_url=SERVER_URL,
        api_key=API_KEY,
        manage_signals=True,
    )
    return worker.run()


if __name__ == "__main__":
    raise SystemExit(main())
