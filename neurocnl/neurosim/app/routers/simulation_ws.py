"""WebSocket router for real-time simulation updates."""

import asyncio
import json
from typing import Any

import anyio
import structlog
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from fastapi.encoders import jsonable_encoder

from ..schemas.preview import PreviewRequest, SimulationStatus
from ..services.job_store import job_store
from ..services.preview_runner import PreviewPayload, run_preview

router = APIRouter(prefix="/api/neurosim/ws", tags=["simulation"])
logger = structlog.get_logger(__name__)


@router.websocket("/simulation")
async def simulation_websocket(websocket: WebSocket) -> None:
    """Handle WebSocket connections for real-time simulation updates."""
    await websocket.accept()
    try:
        while True:
            # Receive simulation request
            data = await websocket.receive_text()
            request_data = json.loads(data)
            job_id = job_store.create_job("preview")

            try:
                request = PreviewRequest(**request_data)

                # Initial status
                await websocket.send_text(
                    json.dumps(
                        {
                            "type": "status",
                            "status": "starting",
                            "message": "Initializing simulation...",
                        },
                    ),
                )

                loop = asyncio.get_running_loop()
                queue: asyncio.Queue[dict[str, Any] | None] = asyncio.Queue()

                def progress_callback(
                    payload: PreviewPayload,
                    *,
                    current_time_ms: float,
                    event_loop: asyncio.AbstractEventLoop = loop,
                    current_job_id: str = job_id,
                    results_queue: asyncio.Queue[dict[str, Any] | None] = queue,
                ) -> None:
                    # Put partial results in the queue.
                    # Since this runs in a thread, we must use run_coroutine_threadsafe
                    # or call_soon_threadsafe. anyio makes thread sync easier, but since
                    # nengo blocks, we are in a worker thread. We can just use an event loop
                    # from the main thread.
                    try:
                        event_loop.call_soon_threadsafe(
                            results_queue.put_nowait,
                            {
                                "type": "frame",
                                "status": "running",
                                "current_time_ms": current_time_ms,
                                "playback": jsonable_encoder(payload.playback),
                            },
                        )
                    except Exception as exc:
                        logger.warning(
                            "websocket_progress_callback_failed",
                            error=str(exc),
                            job_id=current_job_id,
                        )

                async def stream_results(
                    results_queue: asyncio.Queue[dict[str, Any] | None] = queue,
                ) -> None:
                    while True:
                        message = await results_queue.get()
                        if message is None:
                            break
                        await websocket.send_text(json.dumps(message))

                # Start the consumer task
                consumer_task = asyncio.create_task(stream_results())

                def run_simulation(
                    sim_request: PreviewRequest = request,
                    event_loop: asyncio.AbstractEventLoop = loop,
                    current_job_id: str = job_id,
                    results_queue: asyncio.Queue[dict[str, Any] | None] = queue,
                ) -> Any:
                    try:
                        return run_preview(
                            sim_request,
                            job_id=current_job_id,
                            progress_callback=progress_callback,
                        )
                    finally:
                        try:
                            event_loop.call_soon_threadsafe(results_queue.put_nowait, None)
                        except Exception as exc:
                            logger.warning(
                                "websocket_completion_signal_failed",
                                error=str(exc),
                                job_id=current_job_id,
                            )

                # Run the simulation in a worker thread
                result = await anyio.to_thread.run_sync(run_simulation)

                # Wait for the consumer to finish streaming all messages
                await consumer_task

                if result.status == SimulationStatus.CANCELLED:
                    await websocket.send_text(
                        json.dumps(
                            {
                                "type": "status",
                                "status": "cancelled",
                            },
                        ),
                    )
                else:
                    # Final completion message
                    await websocket.send_text(
                        json.dumps(
                            {
                                "type": "completion",
                                "status": "completed",
                                "response": jsonable_encoder(result),
                            },
                        ),
                    )

            except Exception as exc:
                job_store.update_job_error(job_id, str(exc))
                await websocket.send_text(
                    json.dumps(
                        {
                            "type": "error",
                            "message": f"Simulation failed: {exc!s}",
                        },
                    ),
                )

    except WebSocketDisconnect:
        logger.info("websocket_client_disconnected", job_id=locals().get("job_id"))
        if "job_id" in locals():
            job_store.cancel_job(job_id)
    except Exception as exc:
        logger.warning(
            "websocket_simulation_error",
            error=str(exc),
            job_id=locals().get("job_id"),
        )
