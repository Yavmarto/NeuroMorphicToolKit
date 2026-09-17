"""Devices router -- scan, connect, disconnect, impedance check."""

from fastapi import APIRouter, HTTPException, Request, Response
from pydantic import BaseModel, Field

from ..schemas.devices import DeviceInfo
from ..schemas.runtime import DeviceConnectionResponse, ImpedanceResult
from ..services.device_manager import device_manager

router = APIRouter()


class ConnectDeviceRequest(BaseModel):
    """Optional connection parameters for real-board targets."""

    serial_port: str | None = Field(
        default=None,
        description="Optional serial port override, primarily for OpenBCI Cyton.",
    )


@router.get("", response_model=list[DeviceInfo])
async def get_devices(request: Request, response: Response) -> list[DeviceInfo]:
    """Scan for available biosignal devices and return the list.

    Triggers a BrainFlow discovery scan and returns all detected
    devices with their type, channel count, and connection status.
    """
    try:
        devices = await device_manager.scan_devices()
        return devices
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Device scan failed: {exc}")


@router.post("/{device_id}/connect", response_model=DeviceConnectionResponse)
async def connect_device(
    request: Request,
    response: Response,
    device_id: str,
    body: ConnectDeviceRequest = ConnectDeviceRequest(),
    allow_experimental: bool = False,
) -> DeviceConnectionResponse:
    """Connect to a specific device by ID.

    The device must have been discovered in a prior scan.
    """
    try:
        device = await device_manager.connect(
            device_id,
            serial_port=body.serial_port,
            allow_experimental=allow_experimental,
        )

        # Add warning for experimental devices
        resp_data = device.model_dump()
        if device.support_level in {"experimental", "prototype"}:
            resp_data["warning"] = "This device is experimental and not fully validated."

        return DeviceConnectionResponse(**resp_data)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=409, detail=str(exc))


@router.post("/{device_id}/disconnect", response_model=DeviceInfo)
async def disconnect_device(
    request: Request, response: Response, device_id: str
) -> DeviceConnectionResponse:
    """Disconnect from the specified device.

    Cleanly releases the BrainFlow session and stops data streaming.
    """
    try:
        device = await device_manager.disconnect(device_id)
        return DeviceConnectionResponse(**device.model_dump())
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))


@router.get("/{device_id}/impedance", response_model=ImpedanceResult)
async def check_impedance(request: Request, response: Response, device_id: str) -> ImpedanceResult:
    """Run an impedance check on the connected device.

    Returns per-channel impedance values in kOhm.  The device must
    be connected before running this check.
    """
    try:
        result = await device_manager.check_impedance(device_id)
        return ImpedanceResult(**result)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc))
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc))
