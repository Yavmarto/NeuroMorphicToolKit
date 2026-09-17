import json
import re
from pathlib import Path
from typing import Any

from neurochip.provisioning.pynq_overlay_package import inspect_staged_overlay_package

VALID_OVERLAY_MANIFEST: dict[str, Any] = {
    "overlay_id": "snn_overlay_v2",
    "overlay_version": "2.0.0",
    "target_part": "xc7z020clg400-1",
    "supported_neuron_models": ["LIF"],
    "supported_weight_bit_widths": [8],
    "max_neurons": 4096,
    "max_neurons_per_layer": 1024,
    "max_synapses": 262144,
    "max_populations": 4,
    "max_layers": 4,
    "dma_ip_name": "axi_dma_0",
    "snn_ip_name": "snn_engine_0",
    "register_map": {
        "resolved_from_hwh": True,
        "base_address": 1073741824,
        "control_reg_offset": 0,
        "global_interrupt_enable_offset": 4,
        "interrupt_enable_offset": 8,
        "interrupt_status_offset": 12,
        "weights_ptr_offset": 16,
        "layer_config_ptr_offset": 28,
        "layer_count_offset": 40,
        "weight_count_offset": 48,
        "timestep_count_offset": 56,
        # Contract keys, not hardware-derived. This fixture omitted them and
        # still passed, because the model defaults them in — which is how v2
        # shipped a manifest the launcher refused.
        "dma_channel": "axi_dma_0",
        "timestep_us": 1000,
    },
    "weight_layout": {
        "format": "int8_dense_row_major_ddr",
        "storage": "dma_ddr",
        "element_bytes": 1,
        "max_entries": 262144,
        "matrix_order": "post_by_pre",
    },
    "layer_config_layout": {
        "format": "uint32_words",
        "storage": "dma_ddr",
        "words_per_layer": 8,
        "max_layers": 4,
        "fields": {
            "input_size": 0,
            "output_size": 1,
            "weight_offset": 2,
            "threshold": 3,
            "leak_shift": 4,
            "refractory": 5,
        },
    },
}


def test_inspect_staged_overlay_package_reports_missing_directory(tmp_path: Path) -> None:
    status = inspect_staged_overlay_package(tmp_path / "missing")

    assert status.ready is False
    assert status.bitstream_exists is False
    assert status.hwh_exists is False
    assert "directory not found" in status.issues[0]


def test_inspect_staged_overlay_package_requires_both_overlay_files(tmp_path: Path) -> None:
    staging_dir = tmp_path / "pynq_z2"
    staging_dir.mkdir(parents=True, exist_ok=True)
    (staging_dir / "snn_overlay.bit").write_bytes(b"bitstream")

    status = inspect_staged_overlay_package(staging_dir)

    assert status.ready is False
    assert status.bitstream_exists is True
    assert status.hwh_exists is False
    assert any("hardware handoff file" in issue for issue in status.issues)


def test_inspect_staged_overlay_package_accepts_valid_overlay_files(tmp_path: Path) -> None:
    staging_dir = tmp_path / "pynq_z2"
    staging_dir.mkdir(parents=True, exist_ok=True)
    (staging_dir / "snn_overlay.bit").write_bytes(b"bitstream")
    (staging_dir / "snn_overlay.hwh").write_text("<hwh/>", encoding="utf-8")
    (staging_dir / "overlay_manifest.json").write_text(
        json.dumps(VALID_OVERLAY_MANIFEST),
        encoding="utf-8",
    )

    status = inspect_staged_overlay_package(staging_dir)

    assert status.ready is True
    assert status.issues == ()
    assert status.manifest_present is True
    assert status.manifest_valid is True


def _hls_constant(name: str) -> int:
    """Read a capacity constant out of the HLS header."""
    header = (
        Path(__file__).resolve().parents[2]
        / "hardware"
        / "pynq_z2"
        / "hls"
        / "snn_overlay_engine.hpp"
    ).read_text(encoding="utf-8")
    match = re.search(rf"constexpr int {name} = (\d+);", header)
    assert match is not None, f"{name} is not defined in snn_overlay_engine.hpp"
    return int(match.group(1))


def test_repo_manifest_capacity_matches_the_hls_kernel() -> None:
    """The manifest must not promise capacity the kernel does not have.

    Overlay-v1 shipped a manifest that disagreed with its own bitstream, and
    nothing compared the two. Capacity is checked here; the register offsets
    are checked against the generated `.hwh` by
    `hardware/pynq_z2/scripts/sync_manifest_offsets.py --check`.
    """
    manifest = json.loads(
        (
            Path(__file__).resolve().parents[2] / "hardware" / "pynq_z2" / "overlay_manifest.json"
        ).read_text(encoding="utf-8")
    )

    max_neurons_per_layer = _hls_constant("OVERLAY_V2_MAX_NEURONS")
    max_layers = _hls_constant("OVERLAY_V2_MAX_LAYERS")
    max_synapses = _hls_constant("OVERLAY_V2_MAX_SYNAPSES")

    assert manifest["max_neurons_per_layer"] == max_neurons_per_layer
    assert manifest["max_layers"] == max_layers
    assert manifest["max_populations"] == max_layers
    assert manifest["max_synapses"] == max_synapses
    assert manifest["max_neurons"] == max_neurons_per_layer * max_layers
    assert manifest["weight_layout"]["max_entries"] == max_synapses
    assert manifest["layer_config_layout"]["words_per_layer"] == _hls_constant(
        "OVERLAY_V2_CONFIG_WORDS_PER_LAYER"
    )


def test_repo_manifest_register_offsets_are_not_hand_written() -> None:
    """Offsets must come from a built `.hwh`, never from a person.

    Overlay-v1's hand-written register map pointed at nothing, so the host
    wrote every scalar argument to the wrong address.
    """
    manifest = json.loads(
        (
            Path(__file__).resolve().parents[2] / "hardware" / "pynq_z2" / "overlay_manifest.json"
        ).read_text(encoding="utf-8")
    )
    register_map = manifest["register_map"]

    if not register_map.get("resolved_from_hwh"):
        # Unbuilt source tree: every offset must be explicitly unresolved
        # rather than a plausible-looking guess.
        unresolved = [
            key
            for key, value in register_map.items()
            if key != "resolved_from_hwh" and value is not None
        ]
        assert not unresolved, (
            f"register_map has values but was never resolved from a built overlay: {unresolved}"
        )


def test_inspect_staged_overlay_package_rejects_invalid_manifest(tmp_path: Path) -> None:
    staging_dir = tmp_path / "pynq_z2"
    staging_dir.mkdir(parents=True, exist_ok=True)
    (staging_dir / "snn_overlay.bit").write_bytes(b"bitstream")
    (staging_dir / "snn_overlay.hwh").write_text("<hwh/>", encoding="utf-8")
    (staging_dir / "overlay_manifest.json").write_text(
        json.dumps(["not-an-object"]),
        encoding="utf-8",
    )

    status = inspect_staged_overlay_package(staging_dir)

    assert status.ready is False
    assert status.manifest_present is True
    assert status.manifest_valid is False
    assert "overlay manifest is invalid" in status.issues[0]
