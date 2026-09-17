"""PiEEG hardware acceptance flow using the ADS1299-compatible Cyton profile."""

from __future__ import annotations

import argparse
import asyncio
import json
from dataclasses import asdict, dataclass
from pathlib import Path
from unittest.mock import patch

import numpy as np

from neurosense.app.schemas.encoding import build_encoding_config
from neurosense.app.services.device_manager import device_manager
from neurosense.app.services.recording_service import recording_service
from neurosense.app.services.replay_service import replay_service
from neurosense.app.services.session_artifact import load_artifact_metadata
from neurosense.app.services.spike_encoder import spike_encoder


@dataclass(frozen=True)
class ValidationCheck:
    name: str
    passed: bool
    detail: str


@dataclass(frozen=True)
class ValidationReport:
    passed: bool
    artifact_path: str | None
    mock: bool
    stream_host: str | None
    checks: list[ValidationCheck]


def _check(name: str, passed: bool, detail: str) -> ValidationCheck:
    return ValidationCheck(name=name, passed=passed, detail=detail)


def _write_evidence(report: ValidationReport, evidence_path: Path) -> None:
    evidence_path.parent.mkdir(parents=True, exist_ok=True)
    evidence_path.write_text(json.dumps(asdict(report), indent=2), encoding="utf-8")


async def run_validation(  # noqa: PLR0912, PLR0915
    *,
    mock: bool,
    recordings_dir: Path,
    stream_host: str | None = None,
    evidence_path: Path | None = None,
) -> ValidationReport:
    """Run the PiEEG acceptance flow with either a mock or streaming relay target."""
    checks: list[ValidationCheck] = []
    artifact_path: str | None = None

    if mock:
        from neurosense.tests.mock_device import MockBoardShim

        device_manager.set_mock_board_shim(MockBoardShim)

    env_patch = {}
    if stream_host:
        env_patch["NEUROSENSE_PIEEG_STREAM_HOST"] = stream_host

    try:
        with (
            patch.dict("os.environ", env_patch, clear=False),
            patch("neurosense.app.services.recording_service._RECORDINGS_DIR", recordings_dir),
            patch("neurosense.app.services.replay_service._RECORDINGS_DIR", recordings_dir),
        ):
            devices = await device_manager.scan_devices()
            target = next((device for device in devices if device.type == "pieeg"), None)
            if target is None:
                report = ValidationReport(
                    passed=False,
                    artifact_path=None,
                    mock=mock,
                    stream_host=stream_host,
                    checks=[
                        _check("discover target", False, "PiEEG target was not exposed by scan.")
                    ],
                )
                if evidence_path is not None:
                    _write_evidence(report, evidence_path)
                return report

            checks.append(
                _check(
                    "discover target",
                    True,
                    f"Found {target.name} at {target.sampling_rate_hz} Hz.",
                )
            )

            try:
                connected = await device_manager.connect(
                    target.id,
                    allow_experimental=True,
                )
                checks.append(
                    _check(
                        "connect",
                        connected.connected,
                        f"Connected to {connected.name} with support level {connected.support_level}.",
                    )
                )
            except Exception as exc:
                checks.append(_check("connect", False, str(exc)))
                report = ValidationReport(
                    passed=False,
                    artifact_path=None,
                    mock=mock,
                    stream_host=stream_host,
                    checks=checks,
                )
                if evidence_path is not None:
                    _write_evidence(report, evidence_path)
                return report

            data = await device_manager.get_current_data(
                target.id, num_samples=target.sampling_rate_hz
            )
            captured = len(data) >= 2 and bool(data[0]) and bool(data[1])
            checks.append(
                _check(
                    "capture samples",
                    captured,
                    f"Captured {len(data)} channels with {len(data[0]) if data else 0} samples.",
                )
            )

            if not captured:
                disconnected = await device_manager.disconnect(target.id)
                checks.append(
                    _check(
                        "disconnect",
                        disconnected.connected is False,
                        "Disconnected after empty capture path.",
                    )
                )
                report = ValidationReport(
                    passed=False,
                    artifact_path=None,
                    mock=mock,
                    stream_host=stream_host,
                    checks=checks,
                )
                if evidence_path is not None:
                    _write_evidence(report, evidence_path)
                return report

            config = build_encoding_config("delta", delta_threshold=0.1)
            spike_encoder.configure(config, target.sampling_rate_hz, seed=7)
            await recording_service.start(
                device_type="pieeg",
                preset_id="emg_prosthetic",
                channels=2,
                sampling_rate_hz=target.sampling_rate_hz,
                encoding_config=config,
                signal_type="emg",
                channel_labels=["flexor", "extensor"],
                hardware_provenance={
                    "validation_mode": "mock" if mock else "real",
                    "stream_host": stream_host,
                },
            )

            sample_array = np.asarray(data[:2], dtype=np.float64)
            recording_service.append_raw(sample_array)
            recording_service.append_filtered(sample_array)
            recording_service.append_spikes(spike_encoder.encode(sample_array))
            session = await recording_service.stop()
            artifact_path = session.file_path
            checks.append(
                _check(
                    "record artifact",
                    artifact_path is not None,
                    f"Recorded canonical artifact at {artifact_path}.",
                )
            )

            if artifact_path is None:
                report = ValidationReport(
                    passed=False,
                    artifact_path=None,
                    mock=mock,
                    stream_host=stream_host,
                    checks=checks,
                )
                if evidence_path is not None:
                    _write_evidence(report, evidence_path)
                return report

            replay_result = await replay_service.start(Path(artifact_path).stem)
            replay_chunk = None
            async for chunk in replay_service.stream_chunks(chunk_samples=25):
                replay_chunk = chunk
                break
            await replay_service.stop()
            replay_ok = replay_result["status"] == "replaying" and replay_chunk is not None
            checks.append(
                _check(
                    "replay artifact",
                    replay_ok,
                    f"Replay emitted {0 if replay_chunk is None else replay_chunk.shape[1]} samples.",
                )
            )

            disconnected = await device_manager.disconnect(target.id)
            checks.append(
                _check(
                    "disconnect",
                    disconnected.connected is False,
                    "Board session released cleanly.",
                )
            )
    finally:
        if mock:
            device_manager.set_mock_board_shim(None)

    report = ValidationReport(
        passed=all(check.passed for check in checks),
        artifact_path=artifact_path,
        mock=mock,
        stream_host=stream_host,
        checks=checks,
    )
    if evidence_path is not None:
        _write_evidence(report, evidence_path)
    return report


def _default_evidence_path(recordings_dir: Path, mock: bool) -> Path:
    suffix = "mock" if mock else "real"
    return recordings_dir / f"pieeg_acceptance_{suffix}.json"


def _print_report(report: ValidationReport) -> None:
    print("PiEEG acceptance report")
    for check in report.checks:
        status = "PASS" if check.passed else "FAIL"
        print(f"- [{status}] {check.name}: {check.detail}")

    if report.artifact_path is not None:
        metadata = load_artifact_metadata(Path(report.artifact_path))
        print(f"- Artifact support level: {metadata['support_level']}")
        print(f"- Artifact path: {report.artifact_path}")

    print(f"- Overall: {'PASS' if report.passed else 'FAIL'}")


async def _async_main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mock", action="store_true", help="Run the rehearsal flow with MockBoardShim."
    )
    parser.add_argument(
        "--stream-host",
        help="Multicast host for the PiEEG streaming-board relay (macOS dev host).",
    )
    parser.add_argument(
        "--recordings-dir",
        type=Path,
        default=Path("/tmp/neurosense-pieeg-run"),
        help="Directory for generated artifacts and acceptance evidence.",
    )
    parser.add_argument(
        "--evidence-path",
        type=Path,
        help="Optional path for machine-readable acceptance evidence JSON.",
    )
    args = parser.parse_args()

    report = await run_validation(
        mock=args.mock,
        recordings_dir=args.recordings_dir,
        stream_host=args.stream_host,
        evidence_path=args.evidence_path or _default_evidence_path(args.recordings_dir, args.mock),
    )
    _print_report(report)
    return 0 if report.passed else 1


def main() -> None:
    raise SystemExit(asyncio.run(_async_main()))


if __name__ == "__main__":
    main()
