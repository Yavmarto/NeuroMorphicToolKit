"""Local hardware scan endpoints for the Neurochip backend.

``GET /detected`` enumerates Akida, Speck, and serial/Teensy hardware that is
physically present on this host using the existing per-chip discovery helpers,
and returns each hit with its registration state so launchers can auto-register
only the unregistered devices.

PYNQ and SpiNNaker2 are network-attached hardware with no local-scan surface
and are intentionally out of scope for this endpoint (see CEL-120).
"""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Query

from ...contracts.hardware_contracts import DetectedHardwareEntry
from ..services.hardware_detection import detect_local_hardware

router = APIRouter(prefix="/api/neurochip/hardware", tags=["hardware-detection"])


@router.get("/detected", response_model=list[DetectedHardwareEntry])
def list_detected_hardware(
    registered_identifier: Annotated[
        list[str] | None,
        Query(
            description=(
                "Optional device identifiers already present in the caller's "
                "saved-target store. When supplied, each returned hit carries "
                "already_registered=true when its identifier matches one here, "
                "letting the launcher filter to only unregistered hits."
            ),
        ),
    ] = None,
) -> list[DetectedHardwareEntry]:
    """Return locally detected, not-yet-registered hardware candidates."""
    return detect_local_hardware(registered_identifiers=registered_identifier or [])
