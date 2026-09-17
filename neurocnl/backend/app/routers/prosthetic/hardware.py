"""Hardware endpoints — serial port management and live sensor streaming."""

from collections.abc import AsyncIterator

from fastapi import APIRouter, HTTPException
from sse_starlette.sse import EventSourceResponse

from backend.app.schemas.prosthetic import HardwareConnectRequest
from backend.app.schemas.runtime import HardwareConnectionResponse, SerialPortsResponse
from backend.app.services.hardware_service import (
    connect,
    disconnect,
    list_serial_ports,
    stream_sensor_data,
)

router = APIRouter()


@router.get("/hardware/serial", response_model=SerialPortsResponse)
def get_serial_ports() -> SerialPortsResponse:
    ports = list_serial_ports()
    return SerialPortsResponse(ports=ports)


@router.post("/hardware/connect", response_model=HardwareConnectionResponse)
def connect_hardware(request: HardwareConnectRequest) -> HardwareConnectionResponse:
    success = connect(request.port, request.baud_rate)
    if not success:
        raise HTTPException(status_code=503, detail="Failed to connect to hardware")
    return HardwareConnectionResponse(status="connected", port=request.port)


@router.post("/hardware/disconnect", response_model=HardwareConnectionResponse)
def disconnect_hardware() -> HardwareConnectionResponse:
    success = disconnect()
    if not success:
        raise HTTPException(status_code=400, detail="No active connection")
    return HardwareConnectionResponse(status="disconnected")


@router.get("/hardware/stream")
async def stream_hardware() -> EventSourceResponse:
    async def event_generator() -> AsyncIterator[dict[str, str]]:
        async for frame in stream_sensor_data():
            yield {"event": "sensor", "data": frame.model_dump_json()}

    return EventSourceResponse(event_generator())
