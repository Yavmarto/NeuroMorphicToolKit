"""Unit tests for the in-process progress bus.

Covers the asyncio<->thread boundary: a worker thread publishes events for a
job_id, and the asyncio subscriber receives them in order. Also covers
fan-out to multiple subscribers, ignored events when no one is listening,
and the close-stream sentinel.
"""

from __future__ import annotations

import asyncio
import threading

import pytest

from backend.app.services.progress_bus import ProgressBus, progress_bus


@pytest.fixture
def anyio_backend() -> str:
    # ProgressBus is intentionally asyncio-only (asyncio.Queue,
    # loop.call_soon_threadsafe) — the app only ever runs under uvicorn's
    # asyncio loop. Without this override, anyio's pytest plugin also
    # parametrizes over trio, which fails with `RuntimeError: no running
    # event loop` since there's no asyncio loop to fetch under trio.
    return "asyncio"


@pytest.mark.anyio
async def test_subscribe_receives_published_event_from_thread() -> None:
    bus = ProgressBus()
    queue = bus.subscribe("job-A")
    publisher = bus.publisher_for("job-A")

    def _worker() -> None:
        publisher({"type": "epoch", "epoch": 1, "loss": 0.42})

    threading.Thread(target=_worker, daemon=True).start()

    event = await asyncio.wait_for(queue.get(), timeout=1.0)
    assert event == {"type": "epoch", "epoch": 1, "loss": 0.42}


@pytest.mark.anyio
async def test_publish_with_no_subscriber_is_dropped() -> None:
    bus = ProgressBus()
    publisher = bus.publisher_for("job-B")
    # Must not raise even though no one is listening.
    publisher({"type": "epoch", "loss": 0.1})
    # Late subscriber gets nothing for prior events.
    queue = bus.subscribe("job-B")
    with pytest.raises(asyncio.TimeoutError):
        await asyncio.wait_for(queue.get(), timeout=0.05)


@pytest.mark.anyio
async def test_fan_out_to_multiple_subscribers() -> None:
    bus = ProgressBus()
    q1 = bus.subscribe("job-C")
    q2 = bus.subscribe("job-C")
    publisher = bus.publisher_for("job-C")

    publisher({"type": "epoch", "epoch": 3, "loss": 0.01})

    e1 = await asyncio.wait_for(q1.get(), timeout=1.0)
    e2 = await asyncio.wait_for(q2.get(), timeout=1.0)
    assert e1 == e2 == {"type": "epoch", "epoch": 3, "loss": 0.01}


@pytest.mark.anyio
async def test_close_emits_end_sentinel_and_drops_subscribers() -> None:
    bus = ProgressBus()
    queue = bus.subscribe("job-D")

    bus.close("job-D")

    received = await asyncio.wait_for(queue.get(), timeout=1.0)
    assert ProgressBus.is_end_sentinel(received)

    # A subsequent publish for the same job_id must NOT reach the closed queue.
    publisher = bus.publisher_for("job-D")
    publisher({"type": "epoch", "loss": 0.0})
    with pytest.raises(asyncio.TimeoutError):
        await asyncio.wait_for(queue.get(), timeout=0.05)


@pytest.mark.anyio
async def test_unsubscribe_removes_only_target_queue() -> None:
    bus = ProgressBus()
    q1 = bus.subscribe("job-E")
    q2 = bus.subscribe("job-E")
    bus.unsubscribe("job-E", q1)
    publisher = bus.publisher_for("job-E")
    publisher({"type": "epoch", "loss": 0.5})
    # q2 still receives it; q1 must not.
    e2 = await asyncio.wait_for(q2.get(), timeout=1.0)
    assert e2["loss"] == 0.5
    with pytest.raises(asyncio.TimeoutError):
        await asyncio.wait_for(q1.get(), timeout=0.05)


def test_singleton_is_a_progress_bus_instance() -> None:
    # Cheap sanity check that the module-level singleton is wired up.
    assert isinstance(progress_bus, ProgressBus)
