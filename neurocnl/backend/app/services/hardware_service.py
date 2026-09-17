"""Service layer for hardware serial communication."""

from __future__ import annotations

from collections.abc import AsyncGenerator

import structlog

from backend.app.schemas.prosthetic import SensorFrame
from neurocnl.backends import BackendCapabilityProfile
from neurocnl.backends import get_backend_capability as _get_backend_capability
from neurocnl.backends import list_backend_capabilities

logger = structlog.get_logger(__name__)

# Module-level state for the serial connection
_serial_connection = None


def list_backend_targets() -> list[str]:
    """List known hardware deployment backend targets.

    Excludes export-only identifiers (e.g. 'nir') that are not deployable
    hardware targets.
    """
    _EXPORT_ONLY = frozenset({"nir"})
    return sorted(k for k in list_backend_capabilities() if k not in _EXPORT_ONLY)


def get_backend_capability(backend: str) -> BackendCapabilityProfile:
    """Return the capability profile for a backend target."""
    return _get_backend_capability(backend)


def list_serial_ports() -> list[str]:
    """List available serial ports."""
    try:
        from serial.tools.list_ports import comports

        return [p.device for p in comports()]
    except ImportError:
        logger.warning("pyserial_not_installed")
        return []


def connect(port: str, baud_rate: int) -> bool:
    """Open a serial connection."""
    global _serial_connection
    try:
        import serial

        _serial_connection = serial.Serial(port, baud_rate, timeout=1)
        logger.info("serial_connected", port=port, baud_rate=baud_rate)
        return True
    except Exception as e:
        logger.error("serial_connect_failed", error=str(e))
        return False


def disconnect() -> bool:
    """Close the serial connection."""
    global _serial_connection
    if _serial_connection is not None:
        _serial_connection.close()
        _serial_connection = None
        logger.info("serial_disconnected")
        return True
    return False


async def stream_sensor_data() -> AsyncGenerator[SensorFrame, None]:
    """Yield sensor frames from the serial connection."""
    import asyncio
    import json
    import time

    while _serial_connection is not None and _serial_connection.is_open:
        try:
            line = _serial_connection.readline().decode("utf-8").strip()
            if line:
                data = json.loads(line)
                yield SensorFrame(
                    timestamp=time.time(),
                    emg_channels=data.get("emg", []),
                    proximity=data.get("proximity", 0.0),
                    tactile=data.get("tactile", 0.0),
                )
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
        except Exception as exc:
            logger.error("sensor_stream_unexpected_error", error=str(exc))
            break
        await asyncio.sleep(0.01)
