"""In-process progress bus for streaming live training events to SSE clients.

Adapters run inside ``loop.run_in_executor(...)`` — i.e. on a thread distinct
from the event loop. They must therefore not touch ``asyncio.Queue`` directly.
This module exposes a small bus that:

* lets the asyncio side **subscribe** to events for a given ``job_id``
  (returning an ``asyncio.Queue`` it can ``await`` on), and
* lets the worker thread **publish** events for that ``job_id`` via a
  thread-safe callable that uses ``loop.call_soon_threadsafe``.

Live fan-out to subscribers is ephemeral and best-effort: if no subscriber is
attached when an event is published, that subscriber simply never sees it.
However, every published event is also durably appended to ``job_events`` in
``jobs.db`` (see ``job_store.append_job_event``), so a client that subscribes
late — even a different device/GUI reconnecting to the same job — can replay
the full history via ``job_store.list_job_events`` before tailing new events.

Event payloads are plain JSON-serialisable dicts. By convention they have a
``type`` key (``"epoch"``, ``"done"``, ``"failed"``); other keys are free-form
so adapters can stream loss, throughput, spike samples, etc.
"""

from __future__ import annotations

import asyncio
import threading
from collections.abc import Callable
from typing import Any

import structlog

from backend.app.services.job_store import job_store

logger = structlog.get_logger(__name__)

ProgressEvent = dict[str, Any]
ProgressCallback = Callable[[ProgressEvent], None]

# Sentinel that tells the SSE iterator the stream is closed and it should stop.
# Distinct from a regular "done" event because the closing happens after the
# adapter returns, possibly long after a "done" was already emitted.
_STREAM_END = object()


async def _append_job_event_safely(job_id: str, event: ProgressEvent) -> None:
    """Persist an event, swallowing failures — replay history is best-effort,
    it must never crash live delivery to attached subscribers."""
    try:
        await job_store.append_job_event(job_id, event)
    except Exception:
        logger.warning("progress_event_persist_failed", job_id=job_id)


class ProgressBus:
    """Thread-safe pub/sub of training progress events keyed by job_id."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        # job_id -> list of (loop, queue) tuples. Multiple SSE clients can
        # subscribe to the same job; we fan-out to every queue.
        self._subscribers: dict[
            str, list[tuple[asyncio.AbstractEventLoop, asyncio.Queue[Any]]]
        ] = {}

    def subscribe(self, job_id: str) -> asyncio.Queue[Any]:
        """Register an asyncio subscriber for *job_id* and return its queue.

        Must be called from the asyncio loop the consumer will await on.
        """
        loop = asyncio.get_running_loop()
        queue: asyncio.Queue[Any] = asyncio.Queue()
        with self._lock:
            self._subscribers.setdefault(job_id, []).append((loop, queue))
        return queue

    def unsubscribe(self, job_id: str, queue: asyncio.Queue[Any]) -> None:
        """Remove a previously-registered subscriber queue."""
        with self._lock:
            subs = self._subscribers.get(job_id)
            if not subs:
                return
            self._subscribers[job_id] = [(l, q) for (l, q) in subs if q is not queue]
            if not self._subscribers[job_id]:
                del self._subscribers[job_id]

    def publisher_for(self, job_id: str) -> ProgressCallback:
        """Return a thread-safe ``publish`` callable bound to *job_id*.

        Hand this to an adapter running in a thread executor. The callable
        marshals the event back onto each subscriber's loop with
        ``call_soon_threadsafe`` so it is safe to invoke from any thread.
        """

        publish_loop = asyncio.get_running_loop()

        def _publish(event: ProgressEvent) -> None:
            with self._lock:
                subs = list(self._subscribers.get(job_id, ()))
            for loop, queue in subs:
                try:
                    loop.call_soon_threadsafe(queue.put_nowait, event)
                except RuntimeError:
                    # Loop is closed — subscriber went away. Skip silently;
                    # the queue will be unsubscribed by its owner.
                    pass
            try:
                publish_loop.call_soon_threadsafe(
                    lambda: asyncio.ensure_future(
                        _append_job_event_safely(job_id, event)
                    )
                )
            except RuntimeError:
                # Loop is closed — nothing left to persist to.
                pass

        return _publish

    def close(self, job_id: str) -> None:
        """Signal end-of-stream to every subscriber of *job_id* and drop them.

        Called once the job has reached a terminal state so SSE clients can
        cleanly exit their async generator.
        """
        with self._lock:
            subs = self._subscribers.pop(job_id, [])
        for loop, queue in subs:
            try:
                loop.call_soon_threadsafe(queue.put_nowait, _STREAM_END)
            except RuntimeError:
                pass

    @staticmethod
    def is_end_sentinel(value: Any) -> bool:
        return value is _STREAM_END


# Singleton shared across the process. Routers and the job_store hold a
# reference; the worker thread receives a bound publisher.
progress_bus = ProgressBus()
