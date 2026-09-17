"""Router for PYNQ Z2 edge sensor acquisition."""

import asyncio
import json
import os
import socket
import urllib.error
import urllib.request
from collections.abc import AsyncGenerator
from pathlib import Path
from typing import Any

from fastapi import APIRouter
from fastapi.responses import StreamingResponse

from ..schemas.runtime import PynqDeviceInfo, PynqDevicesResponse, PynqStreamStopResponse
from ..sources.pynq_source import PYNQSensorSource

router = APIRouter()

# Keep track of active stream sources
_active_sources: dict[str, PYNQSensorSource] = {}

DEFAULT_STREAM_PORT = 8000
_PROBE_TIMEOUT_S = 1.5

# Offline rehearsal stub. Kept for the simulated validation path; real boards are
# appended from the registry so the endpoint is no longer stub-only.
_SIMULATED_DEVICE = PynqDeviceInfo(
    device_id="pynq_sim_01",
    ip_address="127.0.0.1",
    status="online",
    sensors=["simulated_dvs", "simulated_imu"],
)


def _registry_candidates() -> list[Path]:
    """Locations checked, in order, for the PYNQ device registry file."""
    candidates: list[Path] = []
    env_path = os.environ.get("NEUROSENSE_PYNQ_REGISTRY")
    if env_path:
        candidates.append(Path(env_path))
    # Dev-rig bind mount: /repo is the deploy dir, not managed by the source sync,
    # so an operator-placed registry survives `make dev-update`.
    candidates.append(Path("/repo/config/pynq_devices.json"))
    # Repo checkout layout: Neurosense/neurosense/app/routers/pynq.py -> Neurosense/config
    candidates.append(Path(__file__).resolve().parents[3] / "config" / "pynq_devices.json")
    return candidates


def _nodes_from_env() -> list[dict[str, Any]]:
    """Parse ``NEUROSENSE_PYNQ_DEVICES`` (``id`` or ``id@address`` entries)."""
    raw = os.environ.get("NEUROSENSE_PYNQ_DEVICES", "")
    nodes: list[dict[str, Any]] = []
    for raw_entry in raw.split(","):
        entry = raw_entry.strip()
        if not entry:
            continue
        device_id, _, address = entry.partition("@")
        device_id = device_id.strip()
        if not device_id:
            continue
        node: dict[str, Any] = {"device_id": device_id}
        if address.strip():
            node["address"] = address.strip()
        nodes.append(node)
    return nodes


def load_pynq_registry() -> list[dict[str, Any]]:
    """Return configured real PYNQ nodes from env and the registry file."""
    nodes = _nodes_from_env()
    seen = {str(node["device_id"]) for node in nodes}
    for path in _registry_candidates():
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            continue
        devices = payload.get("devices", []) if isinstance(payload, dict) else payload
        if not isinstance(devices, list):
            continue
        for device in devices:
            if not isinstance(device, dict):
                continue
            device_id = str(device.get("device_id", "")).strip()
            if not device_id or device_id in seen:
                continue
            nodes.append(device)
            seen.add(device_id)
        break
    return nodes


def node_address(device: dict[str, Any]) -> str:
    """Resolvable address used for probing and streaming.

    Prefers an explicit ``address`` (e.g. a static IP). The advertised hostname
    is always ``{device_id}.local`` so the documented URI keeps working.
    """
    explicit = device.get("address")
    if explicit:
        return str(explicit)
    host = device.get("host")
    return str(host) if host else f"{device['device_id']}.local"


def stream_host(device_id: str) -> str:
    """Host to dial for a device stream, honouring a registry address override."""
    for device in load_pynq_registry():
        if str(device.get("device_id")) == device_id:
            return node_address(device)
    return f"{device_id}.local"


def _probe_node(device: dict[str, Any], timeout_s: float = _PROBE_TIMEOUT_S) -> PynqDeviceInfo:
    device_id = str(device["device_id"])
    address = node_address(device)
    try:
        resolved = socket.gethostbyname(address)
    except OSError:
        resolved = address

    sensors = [str(sensor) for sensor in device.get("sensors", []) if sensor]
    status = "offline"
    url = f"http://{address}:{DEFAULT_STREAM_PORT}/status"
    try:
        with urllib.request.urlopen(url, timeout=timeout_s) as response:  # noqa: S310
            if response.status == 200:
                status = "online"
                body = json.loads(response.read().decode("utf-8"))
                reported = body.get("sensors") if isinstance(body, dict) else None
                if isinstance(reported, list) and reported:
                    sensors = [str(sensor) for sensor in reported]
    except (urllib.error.URLError, OSError, ValueError):
        status = "offline"

    if not sensors:
        sensors = ["spikes"]
    return PynqDeviceInfo(
        device_id=device_id,
        ip_address=resolved,
        status=status,
        sensors=sensors,
    )


def discover_real_devices() -> list[PynqDeviceInfo]:
    """Probe every configured node and return the reachable/known real devices."""
    return [_probe_node(device) for device in load_pynq_registry()]


@router.get("/sense/pynq/devices", response_model=PynqDevicesResponse)
async def get_pynq_devices() -> PynqDevicesResponse:
    """Retrieve a list of available PYNQ nodes and attached sensors."""
    real_devices = await asyncio.to_thread(discover_real_devices)
    return PynqDevicesResponse(devices=[_SIMULATED_DEVICE, *real_devices])


@router.post("/sense/pynq/stream/start")
async def start_pynq_stream(device_id: str, simulated: bool = False) -> StreamingResponse:
    """Start the data stream from a remote PYNQ node."""
    # Documented URI structure for PYNQ boards on the network, or loopback if
    # simulated. A registry address override keeps the backend able to dial the
    # board when the container cannot resolve .local via mDNS.
    if simulated:
        uri = "ws://localhost:8000/stream"
    else:
        uri = f"ws://{stream_host(device_id)}:{DEFAULT_STREAM_PORT}/stream"

    source = PYNQSensorSource(uri=uri, simulated=simulated)
    _active_sources[device_id] = source

    async def stream_generator() -> AsyncGenerator[str, None]:
        try:
            async for data in source.start_stream():
                # In a real system, you might want to yield a JSON string per line
                yield json.dumps(data) + "\n"
        finally:
            await source.stop_stream()
            if device_id in _active_sources:
                del _active_sources[device_id]

    return StreamingResponse(stream_generator(), media_type="application/x-ndjson")


@router.post("/sense/pynq/stream/stop", response_model=PynqStreamStopResponse)
async def stop_pynq_stream(device_id: str) -> PynqStreamStopResponse:
    """Stop an active stream."""
    if device_id in _active_sources:
        await _active_sources[device_id].stop_stream()
        del _active_sources[device_id]
        return PynqStreamStopResponse(status="stopped", device_id=device_id)
    return PynqStreamStopResponse(status="not_found", device_id=device_id)
