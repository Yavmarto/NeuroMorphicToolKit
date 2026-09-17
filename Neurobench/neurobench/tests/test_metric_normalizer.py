from __future__ import annotations

import pytest

from app.services.metric_normalizer import (
    MetricNormalizationError,
    normalize_metrics,
    select_metrics_container,
)


def test_select_metrics_container_prefers_results() -> None:
    payload = {
        "results": {"assertions_passed": "2"},
        "metrics": {"assertions_passed": 999},
    }

    container = select_metrics_container(payload)

    assert container == {"assertions_passed": "2"}


def test_select_metrics_container_ignores_non_mapping_nested_values() -> None:
    payload = {
        "results": "not-a-mapping",
        "metrics": 123,
        "assertions_passed": 1,
    }

    container = select_metrics_container(payload)

    assert container is payload


def test_normalize_metrics_flat_payload() -> None:
    payload = {
        "assertions_passed": 3,
        "assertions_failed": 1,
        "latency_ms": 12.5,
        "energy_uj": "42.0",
        "accuracy": 0.97,
    }

    result = normalize_metrics(payload)

    assert result.values == {
        "assertions_passed": 3.0,
        "assertions_failed": 1.0,
        "latency_ms": 12.5,
        "energy_uj": 42.0,
        "accuracy": 0.97,
        "mujoco_steps": 0.0,
    }


def test_normalize_metrics_nested_metrics_payload() -> None:
    payload = {
        "metrics": {
            "energy_uj": 7,
            "mujoco_steps": "18",
        }
    }

    result = normalize_metrics(payload)

    assert result.values == {
        "assertions_passed": 0.0,
        "assertions_failed": 0.0,
        "latency_ms": 0.0,
        "energy_uj": 7.0,
        "accuracy": 0.0,
        "mujoco_steps": 18.0,
    }


def test_normalize_metrics_prefers_results_over_metrics_for_each_canonical_key() -> None:
    payload = {
        "results": {
            "assertions_passed": "4",
            "accuracy": "0.75",
        },
        "metrics": {
            "assertions_passed": 99,
            "accuracy": 0.99,
            "latency_ms": 12,
        },
        "assertions_passed": 1000,
    }

    result = normalize_metrics(payload)

    assert result.values == {
        "assertions_passed": 4.0,
        "assertions_failed": 0.0,
        "latency_ms": 0.0,
        "energy_uj": 0.0,
        "accuracy": 0.75,
        "mujoco_steps": 0.0,
    }


def test_normalize_metrics_defaults_all_canonical_keys_when_missing() -> None:
    result = normalize_metrics({"metrics": {}})

    assert result.values == {
        "assertions_passed": 0.0,
        "assertions_failed": 0.0,
        "latency_ms": 0.0,
        "energy_uj": 0.0,
        "accuracy": 0.0,
        "mujoco_steps": 0.0,
    }


def test_normalize_metrics_rejects_invalid_string_value() -> None:
    payload = {"metrics": {"latency_ms": "fast"}}

    with pytest.raises(MetricNormalizationError, match="latency_ms"):
        normalize_metrics(payload)


def test_normalize_metrics_rejects_boolean_value() -> None:
    payload = {"accuracy": True}

    with pytest.raises(MetricNormalizationError, match="boolean value"):
        normalize_metrics(payload)
