"""Replay the flagship NeuroSense workflow from a real or rehearsal artifact."""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
from pathlib import Path
from typing import Any

from neurosense.app.services.benchmark_pipeline import benchmark_flagship_pipeline_sync
from neurosense.app.services.session_artifact import load_artifact_metadata, load_spike_summary
from neurosense.tests.validate_hardware import run_validation


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[3]


def _default_artifact() -> Path:
    return Path(__file__).resolve().parents[1] / "tests" / "fixtures" / "canonical_emg_session.hdf5"


def _load_optional_handoffs() -> tuple[Any | None, Any | None]:
    repo_root = _repo_root()
    neurobench_root = repo_root / "Neurobench" / "neurobench"
    neurocnl_root = repo_root / "neurocnl"

    if str(neurobench_root) not in sys.path:
        sys.path.insert(0, str(neurobench_root))
    if str(neurocnl_root) not in sys.path:
        sys.path.insert(0, str(neurocnl_root))

    neurobench_handoff = None
    neurocnl_handoff = None

    try:
        from app.services.neurosense_artifact import summarize_neurosense_artifact as neurobench_fn

        neurobench_handoff = neurobench_fn
    except Exception:
        neurobench_handoff = None

    try:
        from backend.app.services.neurosense_artifact import (
            prepare_neurosense_replay as neurocnl_fn,
        )

        neurocnl_handoff = neurocnl_fn
    except Exception:
        neurocnl_handoff = None

    return neurobench_handoff, neurocnl_handoff


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--artifact-path",
        type=Path,
        default=_default_artifact(),
        help="Existing canonical artifact to replay.",
    )
    parser.add_argument(
        "--mock-validation",
        action="store_true",
        help="Generate a rehearsal artifact with the Cyton validation flow before replaying it.",
    )
    parser.add_argument(
        "--recordings-dir",
        type=Path,
        default=Path("/tmp/neurosense-flagship-demo"),
        help="Recording directory used when --mock-validation is enabled.",
    )
    args = parser.parse_args()

    artifact_path = args.artifact_path
    if args.mock_validation:
        report = asyncio.run(run_validation(mock=True, recordings_dir=args.recordings_dir))
        if not report.passed or report.artifact_path is None:
            raise SystemExit("Mock validation did not produce a replayable artifact.")
        artifact_path = Path(report.artifact_path)

    metadata = load_artifact_metadata(artifact_path)
    spike_summary = load_spike_summary(artifact_path)
    benchmark = benchmark_flagship_pipeline_sync(artifact_path)
    neurobench_handoff, neurocnl_handoff = _load_optional_handoffs()

    result: dict[str, Any] = {
        "artifact": metadata,
        "spikes": spike_summary,
        "benchmark": benchmark,
    }

    if neurobench_handoff is not None:
        result["neurobench"] = neurobench_handoff(artifact_path)
    if neurocnl_handoff is not None:
        result["neurocnl"] = neurocnl_handoff(artifact_path)

    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
