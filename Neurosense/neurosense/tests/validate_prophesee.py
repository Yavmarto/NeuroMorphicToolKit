"""Prophesee EVK acceptance flow for NeuroSense event-camera validation."""

from __future__ import annotations

import argparse
import asyncio
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

import httpx
import numpy as np

from neurosense.app.services.event_encoder import event_encoder


@dataclass(frozen=True)
class ValidationCheck:
    name: str
    passed: bool
    detail: str


@dataclass(frozen=True)
class ValidationReport:
    passed: bool
    mock: bool
    api_base: str | None
    resolution: list[int] | None
    event_count: int | None
    checks: list[ValidationCheck]


def _check(name: str, passed: bool, detail: str) -> ValidationCheck:
    return ValidationCheck(name=name, passed=passed, detail=detail)


def _write_evidence(report: ValidationReport, evidence_path: Path) -> None:
    evidence_path.parent.mkdir(parents=True, exist_ok=True)
    evidence_path.write_text(json.dumps(asdict(report), indent=2), encoding="utf-8")


def _mock_events(count: int = 12) -> np.ndarray[Any, Any]:
    dtype = [("x", "i4"), ("y", "i4"), ("p", "i4"), ("t", "i8")]
    events = np.zeros(count, dtype=dtype)
    for index in range(count):
        events[index] = (index % 4, index % 3, index % 2, index * 1000)
    return events


class MockPropheseeSource:
    """Minimal stand-in for PropheseeSource when Metavision is unavailable."""

    def __init__(self, mode: str = "live", path: str | None = None) -> None:
        self.mode = mode
        self.path = path
        self.width = 640
        self.height = 480
        self._is_open = False
        self._read_count = 0

    def open(self, delta_t: int = 10000) -> None:
        del delta_t
        self._is_open = True

    def read_events(self) -> np.ndarray[Any, Any] | None:
        if not self._is_open or self._read_count >= 1:
            return None
        self._read_count += 1
        return _mock_events()

    def close(self) -> None:
        self._is_open = False

    @property
    def is_open(self) -> bool:
        return self._is_open


async def run_api_validation(
    *,
    api_base: str,
    evidence_path: Path | None = None,
) -> ValidationReport:
    """Validate the deployed hw-worker Prophesee HTTP surface."""
    checks: list[ValidationCheck] = []
    base = api_base.rstrip("/")
    devices_url = f"{base}/api/neurosense/sense/prophesee/devices"
    start_url = f"{base}/api/neurosense/sense/prophesee/stream/start"
    stop_url = f"{base}/api/neurosense/sense/prophesee/stream/stop"
    resolution: list[int] | None = None

    async with httpx.AsyncClient(timeout=30.0) as client:
        devices_response = await client.get(devices_url)
        checks.append(
            _check(
                "devices endpoint",
                devices_response.status_code == 200,
                f"GET {devices_url} returned HTTP {devices_response.status_code}.",
            )
        )
        if devices_response.status_code != 200:
            report = ValidationReport(
                passed=False,
                mock=False,
                api_base=api_base,
                resolution=None,
                event_count=None,
                checks=checks,
            )
            if evidence_path is not None:
                _write_evidence(report, evidence_path)
            return report

        payload = devices_response.json()
        sdk_error = payload.get("error")
        devices = payload.get("devices") or []
        if sdk_error:
            checks.append(
                _check(
                    "metavision sdk",
                    False,
                    sdk_error,
                )
            )
            report = ValidationReport(
                passed=False,
                mock=False,
                api_base=api_base,
                resolution=None,
                event_count=None,
                checks=checks,
            )
            if evidence_path is not None:
                _write_evidence(report, evidence_path)
            return report

        checks.append(
            _check(
                "discover device",
                len(devices) >= 1,
                f"Found {len(devices)} Prophesee device(s).",
            )
        )
        if not devices:
            report = ValidationReport(
                passed=False,
                mock=False,
                api_base=api_base,
                resolution=None,
                event_count=None,
                checks=checks,
            )
            if evidence_path is not None:
                _write_evidence(report, evidence_path)
            return report

        start_response = await client.post(
            start_url,
            json={"mode": "live", "delta_t": 10000},
        )
        start_ok = start_response.status_code == 200
        start_detail = f"POST {start_url} returned HTTP {start_response.status_code}."
        if start_ok:
            start_payload = start_response.json()
            resolution = start_payload.get("resolution") or []
            start_detail = (
                f"Started live stream with resolution {resolution[0]}x{resolution[1]}."
                if len(resolution) >= 2
                else f"Started live stream; resolution={resolution!r}."
            )
        checks.append(_check("stream start", start_ok, start_detail))

        stop_response = await client.post(stop_url)
        stop_ok = stop_response.status_code == 200 and stop_response.json().get("status") in {
            "stopped",
            "already_stopped",
        }
        checks.append(
            _check(
                "stream stop",
                stop_ok,
                f"POST {stop_url} returned {stop_response.json().get('status', stop_response.status_code)!r}.",
            )
        )

    report = ValidationReport(
        passed=all(check.passed for check in checks),
        mock=False,
        api_base=api_base,
        resolution=resolution,
        event_count=None,
        checks=checks,
    )
    if evidence_path is not None:
        _write_evidence(report, evidence_path)
    return report


async def run_local_validation(
    *,
    mock: bool,
    evidence_path: Path | None = None,
) -> ValidationReport:
    """Run in-process Prophesee acceptance with optional mock source."""
    checks: list[ValidationCheck] = []
    resolution: list[int] | None = None
    event_count: int | None = None

    import neurosense.app.sources.prophesee_source as prophesee_source

    if mock:
        source_cls = MockPropheseeSource
        sdk_available = True
    else:
        source_cls = prophesee_source.PropheseeSource
        sdk_available = prophesee_source.METAVISION_AVAILABLE

    checks.append(
        _check(
            "metavision sdk",
            sdk_available,
            "Metavision SDK available." if sdk_available else "metavision-sdk not installed",
        )
    )
    if not sdk_available:
        report = ValidationReport(
            passed=False,
            mock=mock,
            api_base=None,
            resolution=None,
            event_count=None,
            checks=checks,
        )
        if evidence_path is not None:
            _write_evidence(report, evidence_path)
        return report

    source = source_cls(mode="live")
    try:
        source.open(delta_t=10000)
        resolution = [source.width, source.height]
        checks.append(
            _check(
                "open live stream",
                source.is_open and source.width > 0 and source.height > 0,
                f"Opened live source at {source.width}x{source.height}.",
            )
        )

        event_encoder.configure(source.width, source.height)
        events = source.read_events()
        captured = events is not None and len(events) > 0
        if captured:
            encoded = event_encoder.encode_to_spike_tensor(events, bin_width_us=1000)
            event_count = int(encoded["counts"])
        checks.append(
            _check(
                "capture event batch",
                captured,
                f"Captured {0 if events is None else len(events)} events; encoded counts={event_count}.",
            )
        )
    except Exception as exc:
        checks.append(_check("open live stream", False, str(exc)))
    finally:
        if source.is_open:
            source.close()
        checks.append(
            _check(
                "close stream",
                not source.is_open,
                "Prophesee source released cleanly.",
            )
        )

    report = ValidationReport(
        passed=all(check.passed for check in checks),
        mock=mock,
        api_base=None,
        resolution=resolution,
        event_count=event_count,
        checks=checks,
    )
    if evidence_path is not None:
        _write_evidence(report, evidence_path)
    return report


def _default_evidence_path(output_dir: Path, *, mock: bool, api_base: str | None) -> Path:
    if api_base is not None:
        return output_dir / "prophesee_acceptance_api.json"
    suffix = "mock" if mock else "real"
    return output_dir / f"prophesee_acceptance_{suffix}.json"


def _print_report(report: ValidationReport) -> None:
    mode = "API" if report.api_base else ("mock" if report.mock else "local")
    print(f"Prophesee acceptance report ({mode})")
    for check in report.checks:
        status = "PASS" if check.passed else "FAIL"
        print(f"- [{status}] {check.name}: {check.detail}")
    if report.resolution:
        print(f"- Resolution: {report.resolution[0]}x{report.resolution[1]}")
    if report.event_count is not None:
        print(f"- Encoded event count: {report.event_count}")
    print(f"- Overall: {'PASS' if report.passed else 'FAIL'}")


async def _async_main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mock",
        action="store_true",
        help="Run the in-process rehearsal flow with MockPropheseeSource.",
    )
    parser.add_argument(
        "--api-base",
        help="Validate the deployed hw-worker HTTP surface, e.g. http://192.168.2.90:8004.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path("/tmp/neurosense-prophesee-run"),
        help="Directory for acceptance evidence JSON.",
    )
    parser.add_argument(
        "--evidence-path",
        type=Path,
        help="Optional path for machine-readable acceptance evidence JSON.",
    )
    args = parser.parse_args()

    evidence_path = args.evidence_path or _default_evidence_path(
        args.output_dir,
        mock=args.mock,
        api_base=args.api_base,
    )

    if args.api_base:
        report = await run_api_validation(api_base=args.api_base, evidence_path=evidence_path)
    else:
        report = await run_local_validation(mock=args.mock, evidence_path=evidence_path)

    _print_report(report)
    return 0 if report.passed else 1


def main() -> None:
    raise SystemExit(asyncio.run(_async_main()))


if __name__ == "__main__":
    main()
