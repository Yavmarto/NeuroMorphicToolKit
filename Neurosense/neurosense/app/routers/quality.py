"""Quality router -- real-time signal quality metrics."""

import numpy as np
from fastapi import APIRouter, HTTPException, Request, Response

from ..schemas.quality import SignalQuality
from ..services.device_manager import device_manager
from ..services.quality_analyzer import quality_analyzer

router = APIRouter()


@router.get("", response_model=SignalQuality)
async def get_quality(request: Request, response: Response) -> SignalQuality:
    """Get real-time signal quality metrics for the connected device.

    Reads the latest data from the connected device, computes per-channel
    SNR, noise floor, power line interference, and returns quality
    classifications (good / marginal / unusable) with actionable suggestions.
    """
    connected = device_manager.get_connected_device()
    if connected is None:
        raise HTTPException(
            status_code=400,
            detail="No device connected. Connect a device first.",
        )

    # Read a longer window for quality analysis (1 second of data)
    data = await device_manager.get_current_data(
        connected.id,
        num_samples=connected.sampling_rate_hz,
    )

    data_array = np.array(data, dtype=np.float64)
    if data_array.size == 0:
        return SignalQuality(channels=[])

    # Retrieve impedance if available
    impedance_result = await device_manager.check_impedance(connected.id)
    impedance_values = None
    if impedance_result.get("status") == "completed":
        impedance_values = impedance_result.get("channels", {})

    return quality_analyzer.analyze(
        data=data_array,
        sampling_rate=float(connected.sampling_rate_hz),
        impedance_values=impedance_values,
    )
