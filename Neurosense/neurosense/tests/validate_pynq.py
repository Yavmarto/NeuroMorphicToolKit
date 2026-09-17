"""PYNQ Z2 hardware acceptance flow for the NeuroSense edge-sensor path."""

from __future__ import annotations

import argparse
import asyncio
import json
from collections.abc import Awaitable, Callable
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import httpx

StreamFrameReader = Callable[
    [httpx.AsyncClient, str, str, bool, int, float],
    Awaitable[tuple[list[dict[str, Any]], str | None]],
]

SIMULATED_DEVICE_ID = "pynq_sim_01"
DEFAULT_BASE_URL = "http://127.0.0.1:8004/api/neurosense"
DEFAULT_FRAME_COUNT = 5


@dataclass(frozen=True)
class ValidationCheck:
    name: str
    passed: bool
    detail: str


@dataclass(frozen=True)
class ValidationReport:
    passed: bool
    simulated: bool
    base_url: str
    device_id: str | None
    websocket_uri: str | None
    frames_received: int
    checks: list[ValidationCheck]


def _check(name: str, passed: bool, detail: str) -> ValidationCheck:
    return ValidationCheck(name=name, passed=passed, detail=detail)


def pynq_websocket_uri(device_id: str) -> str:
    """Documented WebSocket URI for a PYNQ node on the local network."""
    return f"ws://{device_id}.local:8000/stream"


def _write_evidence(report: ValidationReport, evidence_path: Path) -> None:
    evidence_path.parent.mkdir(parents=True, exist_ok=True)
    evidence_path.write_text(json.dumps(asdict(report), indent=2), encoding="utf-8")


def _is_simulated_stub(device: dict[str, Any]) -> bool:
    device_id = str(device.get("device_id", ""))
    sensors = [str(sensor) for sensor in device.get("sensors", [])]
    return device_id == SIMULATED_DEVICE_ID or any(
        sensor.startswith("simulated_") for sensor in sensors
    )


async def _probe_websocket(uri: str, timeout_s: float) -> tuple[bool, str]:
    try:
        websockets = __import__("websockets")
    except ImportError:
        return False, "websockets package is not installed."

    try:
        async with websockets.connect(uri, open_timeout=timeout_s, close_timeout=timeout_s):
            return True, f"Connected to {uri}."
    except Exception as exc:
        return False, f"Could not reach {uri}: {exc}"


async def _read_simulated_frames_locally(
    *,
    frame_count: int,
) -> tuple[list[dict[str, Any]], str | None]:
    """Read spike frames in-process; avoids hanging on open NDJSON streams."""
    from neurosense.app.sources.pynq_source import PYNQSensorSource

    source = PYNQSensorSource(uri="ws://localhost:8000/stream", simulated=True)
    frames: list[dict[str, Any]] = []
    try:
        async for data in source.start_stream():
            frames.append(data)
            if len(frames) >= frame_count:
                break
    except Exception as exc:
        return frames, str(exc)
    finally:
        await source.stop_stream()

    if not frames:
        return frames, "Simulated source returned no frames."
    return frames, None


async def _read_stream_frames(
    client: httpx.AsyncClient,
    base_url: str,
    device_id: str,
    simulated: bool,
    frame_count: int,
    timeout_s: float,
) -> tuple[list[dict[str, Any]], str | None]:
    url = f"{base_url.rstrip('/')}/sense/pynq/stream/start"
    frames: list[dict[str, Any]] = []
    try:
        async with client.stream(
            "POST",
            url,
            params={"device_id": device_id, "simulated": str(simulated).lower()},
            timeout=timeout_s,
        ) as response:
            if response.status_code != 200:
                body = await response.aread()
                return (
                    frames,
                    f"Stream start returned {response.status_code}: {body.decode(errors='replace')}",
                )

            try:
                async for line in response.aiter_lines():
                    if not line:
                        continue
                    frames.append(json.loads(line))
                    if len(frames) >= frame_count:
                        break
            finally:
                await response.aclose()
    except Exception as exc:
        return frames, str(exc)

    if not frames:
        return frames, "Stream returned no NDJSON frames."
    return frames, None


async def run_validation(  # noqa: PLR0912, PLR0915 - linear acceptance flow
    *,
    base_url: str = DEFAULT_BASE_URL,
    device_id: str | None = None,
    simulated: bool = False,
    frame_count: int = DEFAULT_FRAME_COUNT,
    timeout_s: float = 10.0,
    evidence_path: Path | None = None,
    client: httpx.AsyncClient | None = None,
    frame_reader: StreamFrameReader | None = None,
) -> ValidationReport:
    """Run the PYNQ acceptance flow against a NeuroSense backend."""
    checks: list[ValidationCheck] = []
    resolved_device_id: str | None = device_id
    websocket_uri: str | None = None
    frames: list[dict[str, Any]] = []

    owns_client = client is None
    http_client = client or httpx.AsyncClient(timeout=timeout_s)
    try:
        devices_url = f"{base_url.rstrip('/')}/sense/pynq/devices"
        response = await http_client.get(devices_url)
        if response.status_code != 200:
            report = ValidationReport(
                passed=False,
                simulated=simulated,
                base_url=base_url,
                device_id=resolved_device_id,
                websocket_uri=websocket_uri,
                frames_received=0,
                checks=[
                    _check(
                        "discover devices",
                        False,
                        f"GET /sense/pynq/devices returned {response.status_code}.",
                    )
                ],
            )
            if evidence_path is not None:
                _write_evidence(report, evidence_path)
            return report

        devices = response.json().get("devices", [])
        checks.append(
            _check(
                "discover devices", True, f"Found {len(devices)} PYNQ device(s) at {devices_url}."
            )
        )

        if resolved_device_id is None:
            if simulated:
                resolved_device_id = next(
                    (device["device_id"] for device in devices if device.get("device_id")),
                    SIMULATED_DEVICE_ID,
                )
                checks.append(
                    _check(
                        "resolve device",
                        True,
                        f"Selected rehearsal device {resolved_device_id}.",
                    )
                )
            else:
                real_devices = [device for device in devices if not _is_simulated_stub(device)]
                if not real_devices:
                    checks.append(
                        _check(
                            "resolve real device",
                            False,
                            "Only simulated stub devices are exposed; no real PYNQ board is registered.",
                        )
                    )
                    report = ValidationReport(
                        passed=False,
                        simulated=simulated,
                        base_url=base_url,
                        device_id=None,
                        websocket_uri=None,
                        frames_received=0,
                        checks=checks,
                    )
                    if evidence_path is not None:
                        _write_evidence(report, evidence_path)
                    return report
                resolved_device_id = real_devices[0]["device_id"]
                checks.append(
                    _check(
                        "resolve real device",
                        True,
                        f"Selected real device {resolved_device_id}.",
                    )
                )
        else:
            checks.append(
                _check("resolve device", True, f"Using explicit device_id={resolved_device_id}.")
            )

        if not simulated:
            websocket_uri = pynq_websocket_uri(resolved_device_id)
            reachable, detail = await _probe_websocket(websocket_uri, timeout_s)
            checks.append(_check("websocket reachable", reachable, detail))
            if not reachable:
                report = ValidationReport(
                    passed=False,
                    simulated=simulated,
                    base_url=base_url,
                    device_id=resolved_device_id,
                    websocket_uri=websocket_uri,
                    frames_received=0,
                    checks=checks,
                )
                if evidence_path is not None:
                    _write_evidence(report, evidence_path)
                return report

        read_frames = frame_reader or _read_stream_frames
        frames, stream_error = await read_frames(
            http_client,
            base_url,
            resolved_device_id,
            simulated,
            frame_count,
            timeout_s,
        )
        frames_received = len(frames)
        if stream_error is not None:
            checks.append(_check("start stream", False, stream_error))
        else:
            sample = frames[0]
            checks.append(
                _check(
                    "start stream",
                    True,
                    f"Received {frames_received} NDJSON frame(s); first keys={sorted(sample.keys())}.",
                )
            )

            has_spikes = all("spikes" in frame for frame in frames)
            checks.append(
                _check(
                    "spike payload",
                    has_spikes,
                    (
                        "Every frame includes a spikes field."
                        if has_spikes
                        else "Missing spikes in stream frames."
                    ),
                )
            )

            if simulated:
                simulated_ok = all(frame.get("simulated") is True for frame in frames)
                checks.append(
                    _check(
                        "simulated markers",
                        simulated_ok,
                        (
                            "Frames are marked simulated=true."
                            if simulated_ok
                            else "Expected simulated=true frames."
                        ),
                    )
                )
            else:
                real_ok = all(frame.get("simulated") is not True for frame in frames)
                checks.append(
                    _check(
                        "real spike data",
                        real_ok,
                        (
                            "Frames are not marked simulated."
                            if real_ok
                            else "Stream still returned simulated=true."
                        ),
                    )
                )

        stop_url = f"{base_url.rstrip('/')}/sense/pynq/stream/stop"
        stop_response = await http_client.post(stop_url, params={"device_id": resolved_device_id})
        stop_payload = stop_response.json()
        stop_ok = stop_response.status_code == 200 and stop_payload.get("status") in {
            "stopped",
            "not_found",
        }
        checks.append(
            _check(
                "stop stream",
                stop_ok,
                f"Stop returned status={stop_payload.get('status')} for device_id={resolved_device_id}.",
            )
        )
    finally:
        if owns_client:
            await http_client.aclose()

    report = ValidationReport(
        passed=all(check.passed for check in checks),
        simulated=simulated,
        base_url=base_url,
        device_id=resolved_device_id,
        websocket_uri=websocket_uri,
        frames_received=len(frames),
        checks=checks,
    )
    if evidence_path is not None:
        _write_evidence(report, evidence_path)
    return report


def _default_evidence_path(output_dir: Path, simulated: bool) -> Path:
    suffix = "simulated" if simulated else "real"
    return output_dir / f"pynq_acceptance_{suffix}.json"


def _print_report(report: ValidationReport) -> None:
    print("PYNQ acceptance report")
    for check in report.checks:
        status = "PASS" if check.passed else "FAIL"
        print(f"- [{status}] {check.name}: {check.detail}")
    if report.websocket_uri is not None:
        print(f"- WebSocket URI: {report.websocket_uri}")
    print(f"- Overall: {'PASS' if report.passed else 'FAIL'}")


async def _async_main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--base-url",
        default=DEFAULT_BASE_URL,
        help="NeuroSense backend base URL including /api/neurosense prefix.",
    )
    parser.add_argument("--device-id", help="Explicit PYNQ device_id override.")
    parser.add_argument(
        "--simulated",
        action="store_true",
        help="Run the rehearsal flow with simulated=true.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("/tmp/neurosense-pynq-run"),
        help="Directory for acceptance evidence JSON.",
    )
    parser.add_argument(
        "--evidence-path",
        type=Path,
        help="Optional path for machine-readable acceptance evidence JSON.",
    )
    parser.add_argument(
        "--frame-count",
        type=int,
        default=DEFAULT_FRAME_COUNT,
        help="Number of NDJSON frames to read before stopping the stream.",
    )
    parser.add_argument(
        "--timeout-s",
        type=float,
        default=10.0,
        help="Per-request and websocket timeout in seconds.",
    )
    args = parser.parse_args()
    evidence_path = args.evidence_path or _default_evidence_path(args.output_dir, args.simulated)

    if args.simulated:
        from neurosense.app.main import app

        transport = httpx.ASGITransport(app=app)

        async def _local_frames(
            _client: httpx.AsyncClient,
            _base_url: str,
            _device_id: str,
            _simulated: bool,
            frame_count: int,
            _timeout_s: float,
        ) -> tuple[list[dict[str, Any]], str | None]:
            return await _read_simulated_frames_locally(frame_count=frame_count)

        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            report = await run_validation(
                base_url="http://test/api/neurosense",
                device_id=args.device_id,
                simulated=True,
                frame_count=args.frame_count,
                timeout_s=args.timeout_s,
                evidence_path=evidence_path,
                client=client,
                frame_reader=_local_frames,
            )
    else:
        report = await run_validation(
            base_url=args.base_url,
            device_id=args.device_id,
            simulated=False,
            frame_count=args.frame_count,
            timeout_s=args.timeout_s,
            evidence_path=evidence_path,
        )

    _print_report(report)
    return 0 if report.passed else 1


def main() -> None:
    raise SystemExit(asyncio.run(_async_main()))


if __name__ == "__main__":
    main()
