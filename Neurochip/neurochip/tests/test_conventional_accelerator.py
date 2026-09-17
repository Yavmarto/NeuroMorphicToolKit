"""Tests for conventional DNN accelerator manifests and Voyager backend wiring."""

from pathlib import Path

import pytest

from neurochip.conventional_accelerators.backends.voyager import (
    VoyagerAccelerator,
    parse_voyager_benchmark_log,
)
from neurochip.conventional_accelerators.paths import conventional_targets_dir, repo_root
from neurochip.conventional_accelerators.registry import (
    get_accelerator,
    get_manifest,
    list_manifests,
)

_SAMPLE_LOG = """=== CPU baseline (Phase 1 path) ===
cpu_onnx: 5 detections in 120.5 ms
=== AIPU path (Phase 3) ===
aipu_axm: 5 detections in 15.2 ms
=== Summary: AIPU 7.93x vs CPU on bus.jpg ===
"""


def test_list_manifests_includes_four_targets() -> None:
    ids = {manifest.id for manifest in list_manifests()}
    assert ids == {
        "coral_edgetpu",
        "jetson_tensorrt",
        "qualcomm_qnn",
        "voyager_axelera",
    }


def test_voyager_manifest_fields() -> None:
    manifest = get_manifest("voyager_axelera")
    assert manifest.vendor == "Axelera AI"
    assert manifest.required_format == "onnx"
    assert manifest.artifact_format == "axm"
    assert manifest.requires_hardware is True
    assert "voyager_compile_spike.sh" in manifest.compile_cmd


def test_future_targets_have_no_backend_yet() -> None:
    for accelerator_id in ("jetson_tensorrt", "qualcomm_qnn", "coral_edgetpu"):
        with pytest.raises(NotImplementedError):
            get_accelerator(accelerator_id)


def test_voyager_compile_command_points_at_repo_scripts() -> None:
    accelerator = get_accelerator("voyager_axelera")
    assert isinstance(accelerator, VoyagerAccelerator)
    assert (repo_root() / "scripts" / "voyager_compile_spike.sh").is_file()
    assert (repo_root() / "scripts" / "voyager_aipu_spike.sh").is_file()


def test_parse_voyager_benchmark_log() -> None:
    metrics = parse_voyager_benchmark_log(_SAMPLE_LOG, "cpu_onnx")
    assert metrics.baseline_ms == 120.5
    assert metrics.accelerator_ms == 15.2
    assert metrics.detection_count == 5
    assert metrics.speedup == 7.93


def test_export_existing_onnx(tmp_path: Path) -> None:
    from neurochip.conventional_accelerators.interface import ExportRequest

    onnx = tmp_path / "yolov8n.onnx"
    onnx.write_bytes(b"fake-onnx")
    accelerator = get_accelerator("voyager_axelera")
    result = accelerator.export(
        ExportRequest(model_path=onnx, output_dir=tmp_path / "build"),
    )
    assert result.intermediate_path == onnx
    assert result.format == "onnx"


def test_manifest_files_live_next_to_package() -> None:
    assert (conventional_targets_dir() / "voyager_axelera.json").is_file()
