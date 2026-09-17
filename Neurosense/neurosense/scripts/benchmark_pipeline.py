"""CLI wrapper for the flagship NeuroSense benchmark flow."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from neurosense.app.services.benchmark_pipeline import benchmark_flagship_pipeline_sync


def _default_artifact() -> Path:
    return Path(__file__).resolve().parents[1] / "tests" / "fixtures" / "canonical_emg_session.hdf5"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--artifact-path",
        type=Path,
        default=_default_artifact(),
        help="Path to the canonical NeuroSense HDF5 artifact.",
    )
    parser.add_argument(
        "--iterations", type=int, default=5, help="Number of benchmark repetitions."
    )
    parser.add_argument(
        "--chunk-samples",
        type=int,
        default=50,
        help="Replay chunk size used for throughput measurement.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON instead of a human summary.",
    )
    args = parser.parse_args()

    result = benchmark_flagship_pipeline_sync(
        args.artifact_path,
        iterations=args.iterations,
        chunk_samples=args.chunk_samples,
    )

    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
        return

    print("Flagship pipeline benchmark")
    for key, value in result.items():
        print(f"- {key}: {value}")


if __name__ == "__main__":
    main()
