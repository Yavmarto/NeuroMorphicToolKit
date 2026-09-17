from __future__ import annotations

import math

import pytest

from app.services.cross_platform_validation import (
    BackendRunSummary,
    ValidationComparisonError,
    build_validation_report,
    normalize_backend_name,
    validate_runs,
)


def test_normalize_backend_name_strips_and_lowercases() -> None:
    assert normalize_backend_name(" Lava ") == "lava"


def test_normalize_backend_name_rejects_empty_value() -> None:
    with pytest.raises(ValidationComparisonError, match="empty after normalization"):
        normalize_backend_name("   ")


def test_validate_runs_returns_deterministic_sorted_order() -> None:
    runs = [
        BackendRunSummary("case-a", "snnTorch", 0.94, 10.0, 42.0, 0.99),
        BackendRunSummary("case-a", " Lava ", 0.91, 12.5, 50.0, 0.97),
        BackendRunSummary("case-a", "Akida", 0.90, 8.0, 20.0, 0.95),
    ]

    case_id, sorted_runs = validate_runs(runs)

    assert case_id == "case-a"
    assert tuple(run.backend_name for run in sorted_runs) == (
        "Akida",
        " Lava ",
        "snnTorch",
    )


def test_build_validation_report_matches_packet_example() -> None:
    runs = [
        BackendRunSummary(
            case_id="mnist-baseline",
            backend_name=" Lava ",
            accuracy=0.91,
            latency_ms=12.5,
            energy_uj=50.0,
            spike_similarity=0.97,
        ),
        BackendRunSummary(
            case_id="mnist-baseline",
            backend_name="snnTorch",
            accuracy=0.94,
            latency_ms=10.0,
            energy_uj=42.0,
            spike_similarity=0.99,
        ),
        BackendRunSummary(
            case_id="mnist-baseline",
            backend_name="Akida",
            accuracy=0.90,
            latency_ms=8.0,
            energy_uj=20.0,
            spike_similarity=0.95,
        ),
    ]

    report = build_validation_report(runs)

    assert report.case_id == "mnist-baseline"
    assert report.backend_names == ("akida", "lava", "snntorch")
    assert report.accuracy_divergence == pytest.approx(0.04)
    assert report.latency_spread_ms == 4.5
    assert report.energy_spread_uj == 30.0
    assert report.minimum_spike_similarity == 0.95


def test_validate_runs_rejects_fewer_than_two_runs() -> None:
    runs = [BackendRunSummary("case-a", "lava", 0.9, 10.0, 20.0, 0.98)]

    with pytest.raises(ValidationComparisonError, match="at least two runs"):
        validate_runs(runs)


def test_validate_runs_rejects_mismatched_case_ids() -> None:
    runs = [
        BackendRunSummary("case-a", "lava", 0.9, 10.0, 20.0, 0.98),
        BackendRunSummary("case-b", "snntorch", 0.9, 11.0, 25.0, 0.97),
    ]

    with pytest.raises(ValidationComparisonError, match="Mismatched case_id values"):
        validate_runs(runs)


def test_validate_runs_rejects_duplicate_backend_names_after_normalization() -> None:
    runs = [
        BackendRunSummary("case-a", " Lava ", 0.9, 10.0, 20.0, 0.98),
        BackendRunSummary("case-a", "lava", 0.92, 11.0, 25.0, 0.97),
    ]

    with pytest.raises(ValidationComparisonError, match="Duplicate backend names"):
        validate_runs(runs)


@pytest.mark.parametrize(
    ("field_name", "value"),
    [
        ("accuracy", math.inf),
        ("latency_ms", math.nan),
        ("energy_uj", -math.inf),
        ("spike_similarity", math.nan),
    ],
)
def test_validate_runs_rejects_non_finite_metrics(
    field_name: str,
    value: float,
) -> None:
    base = {
        "case_id": "case-a",
        "backend_name": "lava",
        "accuracy": 0.9,
        "latency_ms": 10.0,
        "energy_uj": 20.0,
        "spike_similarity": 0.98,
    }
    first = BackendRunSummary(**(base | {field_name: value}))  # type: ignore
    second = BackendRunSummary("case-a", "snntorch", 0.91, 11.0, 21.0, 0.97)

    with pytest.raises(ValidationComparisonError, match="Non-finite"):
        validate_runs([first, second])


@pytest.mark.parametrize("spike_similarity", [-0.01, 1.01])
def test_validate_runs_rejects_out_of_range_spike_similarity(
    spike_similarity: float,
) -> None:
    runs = [
        BackendRunSummary("case-a", "lava", 0.9, 10.0, 20.0, spike_similarity),
        BackendRunSummary("case-a", "snntorch", 0.92, 11.0, 25.0, 0.97),
    ]

    with pytest.raises(ValidationComparisonError, match=r"\[0\.0, 1\.0\]"):
        validate_runs(runs)


def test_build_validation_report_returns_zero_spreads_for_exact_ties() -> None:
    runs = [
        BackendRunSummary("case-a", "lava", 0.9, 10.0, 20.0, 0.98),
        BackendRunSummary("case-a", "snntorch", 0.9, 10.0, 20.0, 0.97),
    ]

    report = build_validation_report(runs)

    assert report.accuracy_divergence == 0.0
    assert report.latency_spread_ms == 0.0
    assert report.energy_spread_uj == 0.0
    assert report.minimum_spike_similarity == 0.97
