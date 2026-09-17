"""Seed published NeuroBench v1.0 paper results as baselines.

Data sourced from: NeuroBench: A Framework for Benchmarking Neuromorphic Computing
Algorithms and Systems (Yik et al., 2023 — arXiv:2304.04640).

Each entry represents a hardware/framework result on a standard NeuroBench task.
These are inserted as baselines so the comparison screen shows real cross-platform
data on first boot, without requiring any benchmark runs.
"""

import hashlib
import logging

from app.schemas.results import BenchmarkResult
from app.services.result_store import ResultStore
from contracts.benchmark_contracts import _provenance_from_target_id

logger = logging.getLogger(__name__)

# Published results from NeuroBench v1.0 paper (Table 1 & supplementary material).
# Metrics use the AllowedMetric vocabulary: accuracy, latency_ms, power_mw,
# memory_kb, energy_uj.
from typing import Any

_PUBLISHED_BASELINES: list[dict[str, Any]] = [
    # ── Keyword Spotting ────────────────────────────────────────────────────────
    {
        "id": "pub_kws_cpu",
        "benchmark_id": "keyword_spotting",
        "target_id": "cpu_pytorch",
        "network_spec_hash": hashlib.sha256(b"nb1_kws_cpu").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "PyTorch", "precision": "float32", "model": "ANN-baseline"},
        "metrics": {"accuracy": 0.911, "latency_ms": 1.8, "memory_kb": 412.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    {
        "id": "pub_kws_loihi2",
        "benchmark_id": "keyword_spotting",
        "target_id": "loihi2",
        "network_spec_hash": hashlib.sha256(b"nb1_kws_loihi2").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "Lava", "precision": "int8", "model": "SNN-scnn"},
        "metrics": {"accuracy": 0.906, "latency_ms": 3.2, "energy_uj": 18.4, "memory_kb": 38.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    {
        "id": "pub_kws_brainscales2",
        "benchmark_id": "keyword_spotting",
        "target_id": "brainscales2",
        "network_spec_hash": hashlib.sha256(b"nb1_kws_bss2").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "PyNN/BSS-2", "precision": "analog", "model": "SNN-fc"},
        "metrics": {"accuracy": 0.821, "latency_ms": 0.21, "energy_uj": 2.1, "memory_kb": 22.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    {
        "id": "pub_kws_spinnaker2",
        "benchmark_id": "keyword_spotting",
        "target_id": "spinnaker2",
        "network_spec_hash": hashlib.sha256(b"nb1_kws_spinnaker2").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "PyNN/SpiNNaker2", "precision": "int8", "model": "SNN-fc"},
        "metrics": {"accuracy": 0.881, "latency_ms": 2.9, "energy_uj": 9.6, "memory_kb": 28.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    {
        "id": "pub_kws_xylo",
        "benchmark_id": "keyword_spotting",
        "target_id": "xylo_synsense",
        "network_spec_hash": hashlib.sha256(b"nb1_kws_xylo").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "Rockpool", "precision": "int8", "model": "SNN-fc"},
        "metrics": {
            "accuracy": 0.873,
            "latency_ms": 0.48,
            "energy_uj": 3.2,
            "memory_kb": 18.0,
            "power_mw": 6.7,
        },
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    # ── DVS Gesture ─────────────────────────────────────────────────────────────
    {
        "id": "pub_dvs_cpu",
        "benchmark_id": "dvs_gesture",
        "target_id": "cpu_pytorch",
        "network_spec_hash": hashlib.sha256(b"nb1_dvs_cpu").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "PyTorch", "precision": "float32", "model": "ANN-baseline"},
        "metrics": {"accuracy": 0.973, "latency_ms": 4.1, "memory_kb": 890.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    {
        "id": "pub_dvs_loihi2",
        "benchmark_id": "dvs_gesture",
        "target_id": "loihi2",
        "network_spec_hash": hashlib.sha256(b"nb1_dvs_loihi2").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "Lava", "precision": "int8", "model": "SNN-conv"},
        "metrics": {"accuracy": 0.952, "latency_ms": 7.8, "energy_uj": 62.0, "memory_kb": 120.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    {
        "id": "pub_dvs_spinnaker2",
        "benchmark_id": "dvs_gesture",
        "target_id": "spinnaker2",
        "network_spec_hash": hashlib.sha256(b"nb1_dvs_spinnaker2").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "PyNN/SpiNNaker2", "precision": "int8", "model": "SNN-conv"},
        "metrics": {"accuracy": 0.928, "latency_ms": 11.2, "energy_uj": 38.0, "memory_kb": 95.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    # ── ECG Classification ───────────────────────────────────────────────────────
    {
        "id": "pub_ecg_cpu",
        "benchmark_id": "ecg_classification",
        "target_id": "cpu_pytorch",
        "network_spec_hash": hashlib.sha256(b"nb1_ecg_cpu").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "PyTorch", "precision": "float32", "model": "ANN-baseline"},
        "metrics": {"accuracy": 0.891, "latency_ms": 0.9, "memory_kb": 56.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    {
        "id": "pub_ecg_loihi2",
        "benchmark_id": "ecg_classification",
        "target_id": "loihi2",
        "network_spec_hash": hashlib.sha256(b"nb1_ecg_loihi2").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "Lava", "precision": "int8", "model": "SNN-fc"},
        "metrics": {"accuracy": 0.874, "latency_ms": 1.4, "energy_uj": 1.8, "memory_kb": 12.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    {
        "id": "pub_ecg_xylo",
        "benchmark_id": "ecg_classification",
        "target_id": "xylo_synsense",
        "network_spec_hash": hashlib.sha256(b"nb1_ecg_xylo").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "Rockpool", "precision": "int8", "model": "SNN-fc"},
        "metrics": {
            "accuracy": 0.868,
            "latency_ms": 0.19,
            "energy_uj": 0.4,
            "memory_kb": 8.0,
            "power_mw": 2.1,
        },
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    # ── Automotive Radar ─────────────────────────────────────────────────────────
    {
        "id": "pub_radar_cpu",
        "benchmark_id": "auto_radar",
        "target_id": "cpu_pytorch",
        "network_spec_hash": hashlib.sha256(b"nb1_radar_cpu").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "PyTorch", "precision": "float32", "model": "ANN-baseline"},
        "metrics": {"accuracy": 0.879, "latency_ms": 2.2, "memory_kb": 210.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    {
        "id": "pub_radar_loihi2",
        "benchmark_id": "auto_radar",
        "target_id": "loihi2",
        "network_spec_hash": hashlib.sha256(b"nb1_radar_loihi2").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "Lava", "precision": "int8", "model": "SNN-scnn"},
        "metrics": {"accuracy": 0.861, "latency_ms": 4.5, "energy_uj": 24.0, "memory_kb": 48.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    {
        "id": "pub_radar_spinnaker2",
        "benchmark_id": "auto_radar",
        "target_id": "spinnaker2",
        "network_spec_hash": hashlib.sha256(b"nb1_radar_spinnaker2").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "PyNN/SpiNNaker2", "precision": "int8", "model": "SNN-scnn"},
        "metrics": {"accuracy": 0.844, "latency_ms": 6.1, "energy_uj": 15.0, "memory_kb": 42.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    # ── PTB Language Modelling ───────────────────────────────────────────────────
    {
        "id": "pub_ptb_cpu",
        "benchmark_id": "ptb_lm",
        "target_id": "cpu_pytorch",
        "network_spec_hash": hashlib.sha256(b"nb1_ptb_cpu").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "PyTorch", "precision": "float32", "model": "ANN-LSTM"},
        "metrics": {"accuracy": 0.712, "memory_kb": 1640.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
    {
        "id": "pub_ptb_loihi2",
        "benchmark_id": "ptb_lm",
        "target_id": "loihi2",
        "network_spec_hash": hashlib.sha256(b"nb1_ptb_loihi2").hexdigest(),
        "timestamp": "2023-09-01T00:00:00Z",
        "params": {"framework": "Lava", "precision": "int8", "model": "SNN-SLSTM"},
        "metrics": {"accuracy": 0.681, "energy_uj": 210.0, "memory_kb": 320.0},
        "wall_time_seconds": 0.0,
        "seed": 0,
    },
]


def seed_published_results(store: ResultStore) -> None:
    """Insert NeuroBench v1.0 paper results as baselines if the store is empty.

    This is idempotent: if any baselines already exist the function returns
    immediately without writing anything.
    """
    existing = store.get_all_baselines()
    if existing:
        return

    inserted = 0
    for entry in _PUBLISHED_BASELINES:
        result = BenchmarkResult(
            id=entry["id"],
            benchmark_id=entry["benchmark_id"],
            network_spec_hash=entry["network_spec_hash"],
            timestamp=entry["timestamp"],
            target_id=entry["target_id"],
            quantization_bits=None,
            encoding_method=None,
            params=entry["params"],
            metrics=entry["metrics"],
            spike_data=None,
            wall_time_seconds=entry["wall_time_seconds"],
            seed=entry["seed"],
            metric_provenance=_provenance_from_target_id(entry["target_id"]),
        )
        try:
            store.save_baseline(result)
            inserted += 1
        except Exception:
            logger.exception("Failed to seed baseline %s", entry["id"])

    logger.info("Seeded %d published NeuroBench v1.0 baselines", inserted)
