"""Local hardware auto-detection for the Neurochip backend.

Aggregates the per-chip enumeration helpers that already exist across the
backend (Akida via the ``akida`` SDK, Speck via ``samna``, serial/Teensy via
``pyserial``) behind one operator-facing scan.

Only locally scannable chip types are represented: Akida, Speck, and
serial/Teensy. PYNQ and SpiNNaker2 are network-attached hardware with no local
USB/PCIe scan surface, so they are intentionally excluded (see CEL-120).

Every enumeration is optional-import safe: when an SDK is not installed (CI,
containers without the hardware runtime), the corresponding source returns no
devices instead of raising, so the scan degrades to an empty list.
"""

from __future__ import annotations

import logging
from collections.abc import Iterable
from typing import Any

from ...contracts.hardware_contracts import DetectedChipType, DetectedHardwareEntry

logger = logging.getLogger(__name__)


def _akida_identifier(device: Any) -> str:
    """Derive a stable identifier for an Akida device handle."""
    serial = getattr(device, "device", None) or getattr(device, "serial", None)
    if isinstance(serial, str) and serial.strip():
        return serial.strip()
    return str(device)


def _akida_entries() -> list[DetectedHardwareEntry]:
    """Build detected-hardware entries for physical Akida NSoC devices."""
    from .akida_backend import _discover_akida_devices

    entries: list[DetectedHardwareEntry] = []
    for device in _discover_akida_devices():
        identifier = _akida_identifier(device)
        entries.append(
            DetectedHardwareEntry(
                chip_type="akida",
                display_name=f"Akida {identifier}",
                identifier=identifier,
            )
        )
    return entries


def _speck_entries() -> list[DetectedHardwareEntry]:
    """Build detected-hardware entries for samna-discoverable Speck devices."""
    from .speck_backend import _describe_speck_device, _discover_speck_devices

    entries: list[DetectedHardwareEntry] = []
    for device_info in _discover_speck_devices():
        serial_number = getattr(device_info, "serial_number", None)
        usb_bus_number = getattr(device_info, "usb_bus_number", None)
        usb_device_address = getattr(device_info, "usb_device_address", None)
        if isinstance(serial_number, str) and serial_number.strip():
            identifier = serial_number.strip()
        elif usb_bus_number is not None and usb_device_address is not None:
            identifier = f"usb:{usb_bus_number}:{usb_device_address}"
        else:
            identifier = _describe_speck_device(device_info)
        entries.append(
            DetectedHardwareEntry(
                chip_type="speck",
                display_name=_describe_speck_device(device_info) or "Speck device",
                identifier=identifier,
            )
        )
    return entries


def _teensy_entries() -> list[DetectedHardwareEntry]:
    """Build detected-hardware entries for Teensy-compatible serial ports."""
    from .flash_service import list_serial_ports

    entries: list[DetectedHardwareEntry] = []
    for port in list_serial_ports():
        if not port.get("is_teensy"):
            continue
        identifier = str(port.get("port") or "").strip()
        if not identifier:
            continue
        description = str(port.get("description") or "").strip()
        entries.append(
            DetectedHardwareEntry(
                chip_type="teensy",
                display_name=description or f"Teensy {identifier}",
                identifier=identifier,
            )
        )
    return entries


def _detect_local_hardware() -> list[DetectedHardwareEntry]:
    """Run every per-chip enumeration and return the raw detected hits."""
    return [*_akida_entries(), *_speck_entries(), *_teensy_entries()]


def detect_local_hardware(
    registered_identifiers: Iterable[str] | None = None,
) -> list[DetectedHardwareEntry]:
    """Return locally detected hardware annotated with registration state.

    Each hit is reported as ``{chip_type, display_name, identifier,
    already_registered}``. ``already_registered`` is ``True`` when the device
    identifier is present in ``registered_identifiers`` (the caller's snapshot
    of its saved-target store), so launchers can filter to only unregistered
    hits before auto-creating targets.

    PYNQ and SpiNNaker2 are never enumerated: both are network-attached
    hardware with no local-scan capability and are out of scope by design.
    """
    registered = {str(item).strip() for item in (registered_identifiers or [])}
    entries: list[DetectedHardwareEntry] = []
    for entry in _detect_local_hardware():
        entries.append(
            DetectedHardwareEntry(
                chip_type=entry.chip_type,
                display_name=entry.display_name,
                identifier=entry.identifier,
                already_registered=entry.identifier in registered,
            )
        )
    return entries


def available_chip_types() -> set[DetectedChipType]:
    """Return the locally scannable chip types, independent of what is present.

    Kept small and static so clients can render the scan surface even when no
    hardware or SDK is currently installed.
    """
    return {"akida", "speck", "teensy"}


__all__ = ["detect_local_hardware", "available_chip_types"]
