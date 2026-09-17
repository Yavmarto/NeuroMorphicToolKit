"""Tests for the overlay-v1 PYNQ runtime artifact contract."""

import hashlib
import io
import json
import zipfile
from typing import Any

import pytest
from pydantic import ValidationError

from neurocnl.contracts.pynq_deployment_contract import PYNQ_LIMITS
from neurocnl.contracts.pynq_runtime_artifact_contract import (
    PynqOverlayConfigContract,
    PynqOverlayManifestContract,
    PynqPopulationEntry,
    PynqQuantisationInfo,
    PynqRegisterMap,
    PynqRuntimeArtifact,
    validate_pynq_artifact_completeness,
)


def _minimal_overlay_config(**overrides: object) -> dict[str, Any]:
    base: dict[str, Any] = {
        "network_name": "test_net",
        "populations": [
            {"id": "pop_in", "n_neurons": 10, "neuron_model": "LIF", "params": {}},
            {"id": "pop_out", "n_neurons": 10, "neuron_model": "LIF", "params": {}},
        ],
        "connections": [
            {"pre": "pop_in", "post": "pop_out", "weight": 3},
        ],
        "quantisation": {"bits": 8, "scale_factor": 127.0},
        "overlay_id": PYNQ_LIMITS.OVERLAY_ID,
        "overlay_version": PYNQ_LIMITS.OVERLAY_VERSION,
    }
    base.update(overrides)
    return base


def _minimal_register_map(**overrides: object) -> dict[str, Any]:
    """A register map as it looks once resolved from a built `.hwh`.

    The offsets below are the ones Vitis HLS assigns for the v2 kernel's
    argument list. They are fixture data, not a source of truth — the real ones
    are read out of the generated handoff by
    `hardware/pynq_z2/scripts/sync_manifest_offsets.py`.
    """
    base = {
        "resolved_from_hwh": True,
        "base_address": 0x4000_0000,
        "control_reg_offset": 0x00,
        "global_interrupt_enable_offset": 0x04,
        "interrupt_enable_offset": 0x08,
        "interrupt_status_offset": 0x0C,
        "weights_ptr_offset": 0x10,
        "layer_config_ptr_offset": 0x1C,
        "layer_count_offset": 0x28,
        "weight_count_offset": 0x30,
        "timestep_count_offset": 0x38,
        "dma_channel": "axi_dma_0",
        "timestep_us": 1000,
    }
    base.update(overrides)
    return base


def _minimal_overlay_manifest(**overrides: object) -> dict[str, Any]:
    base = PynqOverlayManifestContract(
        register_map=PynqRegisterMap(**_minimal_register_map())
    ).model_dump()
    base.update(overrides)
    return base


def _minimal_manifest(**overrides: object) -> dict[str, Any]:
    base: dict[str, Any] = {
        "target_device": "PYNQ-Z2",
        "checksum_sha256": "a" * 64,
    }
    base.update(overrides)
    return base


def _build_artifact_zip(
    overlay_config: dict[str, Any] | None = None,
    overlay_manifest: dict[str, Any] | None = None,
    register_map: dict[str, Any] | None = None,
    manifest: dict[str, Any] | None = None,
    weights: bytes | None = None,
    readme: str = "# PYNQ Deploy\n",
    exclude_files: set[str] | None = None,
) -> bytes:
    overlay_config = overlay_config or _minimal_overlay_config()
    register_map = register_map or _minimal_register_map()
    overlay_manifest = overlay_manifest or _minimal_overlay_manifest()
    weights = weights or b"\x03"
    manifest = manifest or _minimal_manifest()

    manifest["checksum_sha256"] = hashlib.sha256(weights).hexdigest()
    exclude = exclude_files or set()

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        if "pynq_deploy/overlay_config.json" not in exclude:
            zf.writestr(
                "pynq_deploy/overlay_config.json", json.dumps(overlay_config, indent=2)
            )
        if "pynq_deploy/weights.bin" not in exclude:
            zf.writestr("pynq_deploy/weights.bin", weights)
        if "pynq_deploy/register_map.json" not in exclude:
            zf.writestr(
                "pynq_deploy/register_map.json", json.dumps(register_map, indent=2)
            )
        if "pynq_deploy/overlay_manifest.json" not in exclude:
            zf.writestr(
                "pynq_deploy/overlay_manifest.json",
                json.dumps(overlay_manifest, indent=2),
            )
        if "pynq_deploy/manifest.json" not in exclude:
            zf.writestr("pynq_deploy/manifest.json", json.dumps(manifest, indent=2))
        if "pynq_deploy/README.md" not in exclude:
            zf.writestr("pynq_deploy/README.md", readme)
    return buf.getvalue()


class TestPynqPopulationEntry:
    def test_valid_lif(self) -> None:
        population = PynqPopulationEntry(id="pop0", n_neurons=100, neuron_model="LIF")
        assert population.neuron_model == "LIF"

    def test_unsupported_model_rejected(self) -> None:
        with pytest.raises(ValidationError, match="not supported"):
            PynqPopulationEntry(id="pop0", n_neurons=50, neuron_model="Izhikevich")


class TestPynqQuantisationInfo:
    def test_valid_bit_width(self) -> None:
        quantisation = PynqQuantisationInfo(bits=8, scale_factor=127.0)
        assert quantisation.bits == 8

    def test_invalid_bit_width_rejected(self) -> None:
        with pytest.raises(ValidationError):
            PynqQuantisationInfo(bits=4, scale_factor=7.0)


class TestPynqOverlayConfigContract:
    def test_valid_config(self) -> None:
        config = PynqOverlayConfigContract(**_minimal_overlay_config())
        assert config.overlay_id == PYNQ_LIMITS.OVERLAY_ID
        assert len(config.populations) == 2

    def test_rejects_a_branching_topology(self) -> None:
        """The engine walks layers in order; a fan-out has nowhere to go."""
        config = _minimal_overlay_config(
            populations=[
                {"id": "pop_in", "n_neurons": 4, "neuron_model": "LIF"},
                {"id": "pop_out", "n_neurons": 2, "neuron_model": "LIF"},
                {"id": "pop_other", "n_neurons": 2, "neuron_model": "LIF"},
            ],
            connections=[
                {"pre": "pop_in", "post": "pop_out", "weight": 3},
                {"pre": "pop_in", "post": "pop_other", "weight": 4},
            ],
        )
        with pytest.raises(ValidationError, match="branching or merging topology"):
            PynqOverlayConfigContract(**config)

    def test_rejects_wrong_overlay_id(self) -> None:
        with pytest.raises(ValidationError, match="overlay_id must be"):
            PynqOverlayConfigContract(**_minimal_overlay_config(overlay_id="wrong"))


class TestPynqRegisterMap:
    def test_defaults_are_explicitly_unresolved(self) -> None:
        """An overlay that has not been built has no offsets, not guessed ones.

        Overlay-v1 defaulted to a hand-written map that disagreed with its own
        bitstream, so the host wrote every argument to an address nothing
        decoded.
        """
        register_map = PynqRegisterMap()
        assert register_map.resolved_from_hwh is False
        assert register_map.base_address is None
        assert register_map.weights_ptr_offset is None
        assert register_map.dma_channel == "axi_dma_0"

    def test_unresolved_map_cannot_be_used_on_hardware(self) -> None:
        with pytest.raises(ValueError, match="never resolved from a built"):
            PynqRegisterMap().require_resolved()

    def test_resolved_map_can_be_used_on_hardware(self) -> None:
        register_map = PynqRegisterMap(**_minimal_register_map())
        assert register_map.require_resolved() is register_map

    def test_partially_resolved_map_rejected(self) -> None:
        """Half a register map is how a wrong address gets written."""
        partial = _minimal_register_map()
        partial.pop("timestep_count_offset")
        with pytest.raises(ValidationError, match="missing timestep_count_offset"):
            PynqRegisterMap(**partial)

    def test_offsets_without_resolution_rejected(self) -> None:
        with pytest.raises(ValidationError, match="never resolved from a built"):
            PynqRegisterMap(**_minimal_register_map(resolved_from_hwh=False))

    def test_misaligned_offset_rejected(self) -> None:
        with pytest.raises(ValidationError, match="not 4-byte aligned"):
            PynqRegisterMap(**_minimal_register_map(weights_ptr_offset=0x10001))


class TestPynqOverlayManifestContract:
    def test_weight_layout_matches_the_engine_cache(self) -> None:
        manifest = PynqOverlayManifestContract()

        assert int(manifest.weight_layout["max_entries"]) == manifest.max_synapses
        # v1 pushed weights through an MMIO window the block design never
        # connected to the engine. v2 delivers them from DDR.
        assert manifest.weight_layout["storage"] == "dma_ddr"

    def test_rejects_the_v1_mmio_weight_path(self) -> None:
        with pytest.raises(ValidationError, match="never wired to the engine"):
            PynqOverlayManifestContract(
                weight_layout={
                    "format": "int8_dense_row_major_word_mmio",
                    "storage": "mmio",
                    "max_entries": PYNQ_LIMITS.MAX_SYNAPSES,
                }
            )


def _minimal_artifact_kwargs(**overrides: object) -> dict[str, Any]:
    register_map = PynqRegisterMap(**_minimal_register_map())
    base = {
        "target_device": "PYNQ-Z2",
        "overlay_manifest": PynqOverlayManifestContract(register_map=register_map),
        "overlay_config": PynqOverlayConfigContract(**_minimal_overlay_config()),
        "register_map": register_map,
        "weight_bit_width": 8,
        "weights_checksum_sha256": "a" * 64,
        "manifest_checksum_sha256": "b" * 64,
        "total_neurons": 20,
        "total_synapses": 1,
    }
    base.update(overrides)
    return base


class TestPynqRuntimeArtifact:
    def test_valid_artifact(self) -> None:
        artifact = PynqRuntimeArtifact(**_minimal_artifact_kwargs())
        assert artifact.target_device == "PYNQ-Z2"

    def test_register_map_must_match_manifest(self) -> None:
        wrong_map = PynqRegisterMap(
            **_minimal_register_map(weights_ptr_offset=0x2_0000)
        )
        with pytest.raises(ValidationError, match="register_map must match"):
            PynqRuntimeArtifact(**_minimal_artifact_kwargs(register_map=wrong_map))

    def test_bit_width_mismatch_rejected(self) -> None:
        with pytest.raises(
            ValidationError, match="must match overlay_config.quantisation.bits"
        ):
            PynqRuntimeArtifact(**_minimal_artifact_kwargs(weight_bit_width=16))


class TestValidateArtifactCompleteness:
    def test_valid_artifact_passes(self) -> None:
        artifact = validate_pynq_artifact_completeness(_build_artifact_zip())
        assert artifact.target_device == "PYNQ-Z2"
        assert artifact.overlay_manifest.overlay_id == PYNQ_LIMITS.OVERLAY_ID
        assert artifact.total_neurons == 20

    def test_missing_overlay_manifest_rejected(self) -> None:
        zip_bytes = _build_artifact_zip(
            exclude_files={"pynq_deploy/overlay_manifest.json"}
        )
        with pytest.raises(ValueError, match="missing required files"):
            validate_pynq_artifact_completeness(zip_bytes)

    def test_invalid_overlay_config_rejected(self) -> None:
        zip_bytes = _build_artifact_zip(
            overlay_config={
                "network_name": "bad",
                "populations": [],
                "connections": [],
                "quantisation": {"bits": 8, "scale_factor": 1.0},
                "overlay_id": PYNQ_LIMITS.OVERLAY_ID,
                "overlay_version": PYNQ_LIMITS.OVERLAY_VERSION,
            }
        )
        with pytest.raises(ValidationError):
            validate_pynq_artifact_completeness(zip_bytes)

    def test_bytes_io_input(self) -> None:
        artifact = validate_pynq_artifact_completeness(
            io.BytesIO(_build_artifact_zip())
        )
        assert artifact.target_device == "PYNQ-Z2"

    def test_nonexistent_file_rejected(self) -> None:
        with pytest.raises(FileNotFoundError):
            validate_pynq_artifact_completeness("/nonexistent/path.zip")
