"""Per-target hardware reachability checks."""

from __future__ import annotations

import asyncio
import importlib.util
import os

from fastapi import APIRouter
from pydantic import BaseModel

router = APIRouter()

SIMULATOR_SDK: dict[str, str] = {
    "snntorch_sim": "snntorch",
    "lava_sim": "lava",
    "sc_neurocore_sim": "scnn",
    "brian2_sim": "brian2",
    "rockpool_sim": "rockpool",
    "sinabs_sim": "sinabs",
    "nengo_sim": "nengo",
}


class ReachabilityResponse(BaseModel):
    reachable: bool
    detail: str


@router.get("/targets/{target_id}/reachability", response_model=ReachabilityResponse)
async def check_reachability(target_id: str) -> ReachabilityResponse:
    if target_id in SIMULATOR_SDK:
        pkg = SIMULATOR_SDK[target_id]
        if importlib.util.find_spec(pkg):
            return ReachabilityResponse(reachable=True, detail="simulator ready")
        return ReachabilityResponse(reachable=False, detail=f"{pkg} not installed")

    match target_id:
        case "akida":
            return await _check_akida()
        case "neurochip":
            return await _check_neurochip()
        case "sc_neurocore_fpga":
            return await _check_sc_neurocore_fpga()
        case "pynq":
            return _check_pynq()
        case "lava" | "lava_loihi2":
            return await _check_lava_hw()
        case _:
            return ReachabilityResponse(reachable=False, detail=f"unknown target: {target_id}")


async def _check_akida() -> ReachabilityResponse:
    if not importlib.util.find_spec("akida"):
        return ReachabilityResponse(reachable=False, detail="akida SDK not installed")
    try:
        import akida  # noqa: PLC0415

        devices = akida.devices()
        if devices:
            return ReachabilityResponse(reachable=True, detail=f"{len(devices)} device(s) found")
        return ReachabilityResponse(reachable=False, detail="no Akida devices connected")
    except Exception as exc:  # noqa: BLE001
        return ReachabilityResponse(reachable=False, detail=str(exc))


def _check_pynq() -> ReachabilityResponse:
    """PYNQ boards are remote, so this container can never see one.

    The board is a separate networked machine reached over SSH from launcher
    control, which owns the board registry and the overlay-install state. This
    process has neither the `pynq` package nor a route to the board, so any
    probe it ran here would report "not reachable" for a perfectly healthy
    board — the same trap documented for Akida in
    `hardware_reachability_provider.dart`. Answer honestly and name the real
    source instead of falling through to `unknown target: pynq`, which read
    like a missing target rather than a misdirected question.
    """
    return ReachabilityResponse(
        reachable=False,
        detail=(
            "PYNQ board readiness comes from launcher control preflight, not the backend container"
        ),
    )


async def _check_neurochip() -> ReachabilityResponse:
    if not importlib.util.find_spec("serial"):
        return ReachabilityResponse(reachable=False, detail="pyserial not installed")
    try:
        import serial.tools.list_ports  # noqa: PLC0415

        ports = [
            p
            for p in serial.tools.list_ports.comports()
            if any(kw in p.description.lower() for kw in ("neurochip", "teensy"))
        ]
        if ports:
            return ReachabilityResponse(reachable=True, detail=f"found: {ports[0].device}")
        return ReachabilityResponse(reachable=False, detail="no Neurochip/Teensy on serial ports")
    except Exception as exc:  # noqa: BLE001
        return ReachabilityResponse(reachable=False, detail=str(exc))


async def _check_sc_neurocore_fpga() -> ReachabilityResponse:
    host = os.environ.get("SC_NEUROCORE_FPGA_HOST", "")
    if not host:
        return ReachabilityResponse(reachable=False, detail="SC_NEUROCORE_FPGA_HOST not configured")
    port = int(os.environ.get("SC_NEUROCORE_FPGA_PORT", "22"))
    try:
        _, writer = await asyncio.wait_for(asyncio.open_connection(host, port), timeout=2.0)
        writer.close()
        await writer.wait_closed()
        return ReachabilityResponse(reachable=True, detail=f"reachable at {host}:{port}")
    except (TimeoutError, OSError):
        return ReachabilityResponse(reachable=False, detail=f"cannot reach {host}:{port}")
    except Exception as exc:  # noqa: BLE001
        return ReachabilityResponse(reachable=False, detail=str(exc))


async def _check_lava_hw() -> ReachabilityResponse:
    if not importlib.util.find_spec("lava"):
        return ReachabilityResponse(reachable=False, detail="lava SDK not installed")
    host = os.environ.get("LOIHI_HOST", "")
    if not host:
        return ReachabilityResponse(reachable=False, detail="LOIHI_HOST not configured")
    port = int(os.environ.get("LOIHI_PORT", "22"))
    try:
        _, writer = await asyncio.wait_for(asyncio.open_connection(host, port), timeout=2.0)
        writer.close()
        await writer.wait_closed()
        return ReachabilityResponse(reachable=True, detail=f"reachable at {host}:{port}")
    except (TimeoutError, OSError):
        return ReachabilityResponse(reachable=False, detail=f"cannot reach {host}:{port}")
    except Exception as exc:  # noqa: BLE001
        return ReachabilityResponse(reachable=False, detail=str(exc))
