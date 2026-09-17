"""Tests for the manifest/hardware register-offset reconciliation.

Overlay-v1's manifest claimed the engine's scalar arguments lived at byte
offsets 8/12/16/20 while Vitis HLS had actually placed them at 0x10/0x18/0x20/
0x28. The host duly wrote every argument to the wrong address, and nothing in
the build or the test suite noticed. These tests cover the script that makes
that class of drift impossible to ship.
"""

from __future__ import annotations

import importlib.util
import json
from pathlib import Path
from types import ModuleType

import pytest

HARDWARE_DIR = Path(__file__).resolve().parents[2] / "hardware" / "pynq_z2"


def _load_sync_module() -> ModuleType:
    path = HARDWARE_DIR / "scripts" / "sync_manifest_offsets.py"
    spec = importlib.util.spec_from_file_location("sync_manifest_offsets", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


sync = _load_sync_module()


def _write_hwh(
    path: Path,
    registers: dict[str, int],
    *,
    instance: str = "snn_engine_0",
    base_address: int = 0x40000000,
) -> Path:
    register_xml = "".join(
        f'<REGISTER NAME="{name}">'
        f'<PROPERTY NAME="ADDRESS_OFFSET" VALUE="{offset}"/>'
        # A nested FIELD carries its own ADDRESS_OFFSET; the parser must not
        # mistake it for the register's.
        f'<FIELDS><FIELD NAME="bit0">'
        f'<PROPERTY NAME="ADDRESS_OFFSET" VALUE="999"/>'
        f"</FIELD></FIELDS>"
        f"</REGISTER>"
        for name, offset in registers.items()
    )
    path.write_text(
        "<EDKSYSTEM>"
        f'<MODULE FULLNAME="/{instance}" MODTYPE="snn_overlay_engine">'
        f"<REGISTERS>{register_xml}</REGISTERS>"
        "</MODULE>"
        f'<MEMRANGE INSTANCE="{instance}" BASENAME="C_S_AXI_CONTROL_BASEADDR" '
        f'BASEVALUE="{hex(base_address)}"/>'
        "</EDKSYSTEM>",
        encoding="utf-8",
    )
    return path


V2_REGISTERS = {
    "CTRL": 0,
    "GIER": 4,
    "IP_IER": 8,
    "IP_ISR": 12,
    "weights": 16,
    "layer_config": 28,
    "layer_count": 40,
    "weight_count": 48,
    "timestep_count": 56,
}


def test_offsets_come_from_the_hardware_handoff(tmp_path: Path) -> None:
    hwh = _write_hwh(tmp_path / "snn_overlay.hwh", V2_REGISTERS)

    register_map = sync.build_register_map(hwh, "snn_engine_0")

    assert register_map["resolved_from_hwh"] is True
    assert register_map["base_address"] == 0x40000000
    assert register_map["control_reg_offset"] == 0
    assert register_map["weights_ptr_offset"] == 16
    assert register_map["layer_config_ptr_offset"] == 28
    assert register_map["layer_count_offset"] == 40
    assert register_map["weight_count_offset"] == 48
    assert register_map["timestep_count_offset"] == 56


def test_nested_field_offsets_are_not_mistaken_for_register_offsets(
    tmp_path: Path,
) -> None:
    hwh = _write_hwh(tmp_path / "snn_overlay.hwh", V2_REGISTERS)

    offsets = sync._register_offsets(hwh, "snn_engine_0")

    assert 999 not in offsets.values()


def test_pointer_registers_are_matched_through_vitis_suffixes(
    tmp_path: Path,
) -> None:
    """Vitis may name a pointer register `weights_r` or `weights_1`."""
    registers = dict(V2_REGISTERS)
    registers["weights_r"] = registers.pop("weights")
    registers["layer_config_1"] = registers.pop("layer_config")
    hwh = _write_hwh(tmp_path / "snn_overlay.hwh", registers)

    register_map = sync.build_register_map(hwh, "snn_engine_0")

    assert register_map["weights_ptr_offset"] == 16
    assert register_map["layer_config_ptr_offset"] == 28


def test_a_missing_weight_register_stops_the_build(tmp_path: Path) -> None:
    """This is the overlay-v1 failure, caught at build time instead of on a board."""
    registers = dict(V2_REGISTERS)
    del registers["weights"]
    hwh = _write_hwh(tmp_path / "snn_overlay.hwh", registers)

    with pytest.raises(sync.ManifestSyncError) as excinfo:
        sync.build_register_map(hwh, "snn_engine_0")

    assert "weights" in str(excinfo.value)


def test_the_real_v1_handoff_is_rejected() -> None:
    """The shipped v1 overlay genuinely has no register for the weight port."""
    staged = HARDWARE_DIR.parents[0] / "overlay_staging" / "pynq_z2" / "snn_overlay.hwh"
    if not staged.exists():
        pytest.skip("no staged overlay handoff in this checkout")

    offsets = sync._register_offsets(staged, "snn_engine_0")
    if "weights" in offsets:
        pytest.skip("staged overlay has already been rebuilt to v2")

    with pytest.raises(sync.ManifestSyncError):
        sync.build_register_map(staged, "snn_engine_0")


def test_check_reports_drift_between_manifest_and_hardware(tmp_path: Path) -> None:
    hwh = _write_hwh(tmp_path / "snn_overlay.hwh", V2_REGISTERS)
    manifest_path = tmp_path / "overlay_manifest.json"
    manifest_path.write_text(
        json.dumps(
            {
                "overlay_id": "snn_overlay_v2",
                "register_map": {
                    "resolved_from_hwh": True,
                    "base_address": 0x40000000,
                    "control_reg_offset": 0,
                    "global_interrupt_enable_offset": 4,
                    "interrupt_enable_offset": 8,
                    "interrupt_status_offset": 12,
                    "weights_ptr_offset": 16,
                    "layer_config_ptr_offset": 28,
                    "layer_count_offset": 8,  # the v1-style hand-written guess
                    "weight_count_offset": 48,
                    "timestep_count_offset": 56,
                    "dma_channel": "axi_dma_0",
                    "timestep_us": 1000,
                },
            }
        ),
        encoding="utf-8",
    )

    problems = sync.check_manifest(manifest_path, hwh, "snn_engine_0")

    assert len(problems) == 1
    assert "layer_count_offset" in problems[0]
    assert "manifest says 8" in problems[0]
    assert "hardware says 40" in problems[0]


def test_check_rejects_an_unresolved_manifest(tmp_path: Path) -> None:
    hwh = _write_hwh(tmp_path / "snn_overlay.hwh", V2_REGISTERS)
    manifest_path = tmp_path / "overlay_manifest.json"
    manifest_path.write_text(
        json.dumps({"register_map": {"resolved_from_hwh": False}}),
        encoding="utf-8",
    )

    problems = sync.check_manifest(manifest_path, hwh, "snn_engine_0")

    assert len(problems) == 1
    assert "never resolved" in problems[0]


def test_write_fills_the_manifest_from_the_handoff(tmp_path: Path) -> None:
    hwh = _write_hwh(tmp_path / "snn_overlay.hwh", V2_REGISTERS)
    manifest_path = tmp_path / "overlay_manifest.json"
    manifest_path.write_text(
        json.dumps(
            {
                "overlay_id": "snn_overlay_v2",
                "max_neurons": 4096,
                "register_map": {
                    "resolved_from_hwh": False,
                    "base_address": None,
                    "dma_channel": "axi_dma_0",
                    "timestep_us": 1000,
                },
            }
        ),
        encoding="utf-8",
    )

    sync.write_manifest(manifest_path, hwh, "snn_engine_0")

    assert sync.check_manifest(manifest_path, hwh, "snn_engine_0") == []
    written = json.loads(manifest_path.read_text(encoding="utf-8"))
    # Unrelated manifest fields survive the rewrite.
    assert written["max_neurons"] == 4096


def test_write_preserves_contract_keys_the_hardware_does_not_own(
    tmp_path: Path,
) -> None:
    """The v2 overlay shipped unusable because --write deleted these.

    `register_map` mixes hardware-derived offsets with contract fields. Assigning
    a freshly built map over the old one dropped `dma_channel`, the launcher
    refused the manifest, and every board reported "Overlay Missing" while
    carrying a perfectly good bitstream.
    """
    hwh = _write_hwh(tmp_path / "snn_overlay.hwh", V2_REGISTERS)
    manifest_path = tmp_path / "overlay_manifest.json"
    manifest_path.write_text(
        json.dumps(
            {
                "overlay_id": "snn_overlay_v2",
                "dma_ip_name": "axi_dma_0",
                "register_map": {"dma_channel": "axi_dma_0", "timestep_us": 1000},
            }
        ),
        encoding="utf-8",
    )

    register_map = sync.write_manifest(manifest_path, hwh, "snn_engine_0")

    assert register_map["dma_channel"] == "axi_dma_0"
    assert register_map["timestep_us"] == 1000
    assert register_map["weights_ptr_offset"] == 16
    written = json.loads(manifest_path.read_text(encoding="utf-8"))
    assert written["register_map"]["dma_channel"] == "axi_dma_0"


def test_check_fails_when_a_contract_key_was_dropped(tmp_path: Path) -> None:
    """Offsets that agree with the hardware are not a complete register map."""
    hwh = _write_hwh(tmp_path / "snn_overlay.hwh", V2_REGISTERS)
    manifest_path = tmp_path / "overlay_manifest.json"
    manifest_path.write_text(
        json.dumps({"overlay_id": "snn_overlay_v2", "register_map": {}}),
        encoding="utf-8",
    )
    sync.write_manifest(manifest_path, hwh, "snn_engine_0")

    problems = sync.check_manifest(manifest_path, hwh, "snn_engine_0")

    assert any("dma_channel" in problem for problem in problems)
    assert any("timestep_us" in problem for problem in problems)
