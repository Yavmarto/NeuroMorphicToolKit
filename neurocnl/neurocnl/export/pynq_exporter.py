"""PYNQ Z2 overlay-v2 exporter."""

from __future__ import annotations

import hashlib
import json
import zipfile
from dataclasses import dataclass, field
from io import BytesIO
from pathlib import Path
from typing import TYPE_CHECKING, Any

import nengo
import numpy as np

from neurocnl.contracts.pynq_deployment_contract import PYNQ_LIMITS
from neurocnl.contracts.pynq_runtime_artifact_contract import (
    PynqOverlayManifestContract,
)
from neurocnl.ir.types import PORT_POPULATION_TYPES
from neurocnl.transforms.quantise import quantisation_fidelity, quantise_network_dict

if TYPE_CHECKING:
    from neurocnl.contracts.pynq_runtime_artifact_contract import PynqRuntimeArtifact
    from neurocnl.ir.types import NetworkIR

MAX_SYNAPSES = PYNQ_LIMITS.MAX_SYNAPSES


def _default_overlay_manifest() -> dict[str, Any]:
    return PynqOverlayManifestContract().model_dump()


def _default_register_map() -> dict[str, Any]:
    """The register map of the overlay this artifact targets, not bare defaults.

    ``PynqRuntimeArtifact`` requires the two to be equal, and the board drives the
    engine through these offsets — an artifact carrying `None` for every offset
    could never run. While the overlay was unbuilt both sides were unresolved and
    happened to match; the moment the v2 bitstream supplied real offsets to the
    manifest, every network was rejected with "register_map must match the overlay
    manifest register map". Deriving from the manifest keeps them equal whatever
    the manifest says.
    """
    return PynqOverlayManifestContract().register_map.model_dump()


@dataclass
class PynqOverlayConfig:
    """Configuration for the fixed overlay-v2 PYNQ Z2 runtime."""

    network_name: str
    populations: list[dict[str, Any]]
    connections: list[dict[str, Any]]
    quantisation: dict[str, Any]
    overlay_id: str = PYNQ_LIMITS.OVERLAY_ID
    overlay_version: str = PYNQ_LIMITS.OVERLAY_VERSION
    register_map: dict[str, Any] = field(default_factory=_default_register_map)
    overlay_manifest: dict[str, Any] = field(default_factory=_default_overlay_manifest)

    def _overlay_config_dict(self) -> dict[str, Any]:
        return {
            "network_name": self.network_name,
            "populations": self.populations,
            "connections": self.connections,
            "quantisation": self.quantisation,
            "overlay_id": self.overlay_id,
            "overlay_version": self.overlay_version,
        }

    def to_files(self, output_dir: str | Path) -> None:
        """Write overlay deployment files to disk."""
        out_path = Path(output_dir)
        out_path.mkdir(parents=True, exist_ok=True)

        (out_path / "overlay_config.json").write_text(
            json.dumps(self._overlay_config_dict(), indent=2),
            encoding="utf-8",
        )
        (out_path / "register_map.json").write_text(
            json.dumps(self.register_map, indent=2),
            encoding="utf-8",
        )
        (out_path / "overlay_manifest.json").write_text(
            json.dumps(self.overlay_manifest, indent=2),
            encoding="utf-8",
        )
        (out_path / "weights.bin").write_bytes(self._pack_weights_bytes())

    def _pack_weights_bytes(self) -> bytes:
        """Pack quantized overlay weights according to overlay-v2."""
        bits = int(
            self.quantisation.get("bits", PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS[0])
        )
        if bits not in PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS:
            raise ValueError(
                "The PYNQ overlay only supports "
                f"{PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS}-bit weights"
            )

        weights = [int(conn["weight"]) for conn in self.connections]
        return np.array(weights, dtype=np.int8).tobytes()

    def to_zip(self, output_path: str | Path | None = None) -> bytes:
        """Produce a contract-compliant overlay-v2 PYNQ artifact ZIP."""
        config_dict = self._overlay_config_dict()
        weights_bytes = self._pack_weights_bytes()
        weights_checksum = hashlib.sha256(weights_bytes).hexdigest()

        manifest_dict = {
            "target_device": "PYNQ-Z2",
            "checksum_sha256": weights_checksum,
        }

        readme_text = (
            "# PYNQ Deployment Artifact\n\n"
            f"Network: {self.network_name}\n"
            f"Overlay ID: {self.overlay_id}\n"
            f"Overlay Version: {self.overlay_version}\n"
            f"Quantisation: {self.quantisation.get('bits', '?')}-bit "
            f"(scale={self.quantisation.get('scale_factor', '?')})\n"
            f"Populations: {len(self.populations)}\n"
            f"Connections: {len(self.connections)}\n"
        )

        buf = BytesIO()
        with zipfile.ZipFile(buf, mode="w", compression=zipfile.ZIP_DEFLATED) as zf:
            zf.writestr(
                "pynq_deploy/overlay_config.json", json.dumps(config_dict, indent=2)
            )
            zf.writestr("pynq_deploy/weights.bin", weights_bytes)
            zf.writestr(
                "pynq_deploy/register_map.json", json.dumps(self.register_map, indent=2)
            )
            zf.writestr(
                "pynq_deploy/overlay_manifest.json",
                json.dumps(self.overlay_manifest, indent=2),
            )
            zf.writestr(
                "pynq_deploy/manifest.json", json.dumps(manifest_dict, indent=2)
            )
            zf.writestr("pynq_deploy/README.md", readme_text)

        zip_bytes = buf.getvalue()
        if output_path is not None:
            out = Path(output_path)
            out.parent.mkdir(parents=True, exist_ok=True)
            out.write_bytes(zip_bytes)
        return zip_bytes


def _assert_layer_chain(connection_pairs: set[tuple[str, str]]) -> None:
    """Reject anything the overlay's layer walker cannot execute.

    Overlay-v1 held exactly one dense matrix. v2 holds up to ``MAX_LAYERS``,
    but the engine walks them in order, handing each layer's spikes to the
    next, so a branch, a merge, or two disjoint chains have nowhere to go.
    """
    if len(connection_pairs) > PYNQ_LIMITS.MAX_LAYERS:
        raise ValueError(
            f"The PYNQ overlay supports at most {PYNQ_LIMITS.MAX_LAYERS} weight "
            f"matrices; this network has {len(connection_pairs)}"
        )

    sources = [pre for pre, _ in connection_pairs]
    targets = [post for _, post in connection_pairs]
    if len(set(sources)) != len(sources) or len(set(targets)) != len(targets):
        raise ValueError(
            "The PYNQ overlay runs one feedforward chain of layers; a branching "
            "or merging topology has nowhere to go"
        )


def _clean_identifier(label: str) -> str:
    return label.replace(" ", "_").replace("-", "_")


def _assert_quantisable(connections: list[dict[str, Any]], bits: int) -> None:
    """Refuse only weights that have no fixed-point image at all.

    Lossy rounding is the whole point of quantisation, so the only genuine
    refusal is a non-finite weight. Runs before ``quantise_network_dict`` because
    a NaN otherwise surfaces from deep inside it as "cannot convert float NaN to
    integer", which says nothing about the user's network.

    The degenerate all-collapse case is also checked, defensively: with the
    max-abs scaling this module uses it cannot occur (the largest weight always
    maps to ±(2^(bits-1) - 1)), but an externally supplied scale factor could
    produce it, and deploying a network whose every synapse rounded to zero is
    worth refusing rather than silently shipping.
    """
    fidelity = quantisation_fidelity(
        [float(conn["weight"]) for conn in connections], bits=bits
    )
    if fidelity.has_non_finite:
        raise ValueError(
            f"Network is not quantisable to {bits} bits: it contains non-finite "
            f"weights (NaN or infinity), which have no fixed-point representation."
        )
    if fidelity.is_total_loss:
        raise ValueError(
            f"Network is not quantisable to {bits} bits: every non-zero weight "
            f"rounds to zero at this scale, so the deployed network would compute "
            f"nothing."
        )


def _extract_dense_connection_weights(
    conn: nengo.Connection,
    *,
    pre_size: int,
    post_size: int,
) -> list[float]:
    """Expand a Nengo connection into a dense row-major weight list."""
    weight_count = pre_size * post_size
    transform = getattr(conn, "transform", None)
    raw = (
        transform.init
        if transform is not None and hasattr(transform, "init")
        else transform
    )
    if raw is None:
        return [1.0] * weight_count
    if isinstance(raw, int | float):
        return [float(raw)] * weight_count

    array = np.asarray(raw, dtype=float)
    if array.size == 1:
        return [float(array.reshape(()))] * weight_count
    if array.size != weight_count:
        raise ValueError(
            "PYNQ overlay-v2 requires a dense connection transform whose size matches "
            f"{post_size}x{pre_size}; got {array.shape}"
        )
    return [float(weight) for weight in array.reshape(weight_count)]


def export_pynq_artifact(
    net: nengo.Network,
    output_path: str | Path | None = None,
    **kwargs: Any,
) -> tuple[PynqOverlayConfig, PynqRuntimeArtifact]:
    """Export a Nengo network as a validated overlay-v2 PYNQ artifact."""
    from neurocnl.contracts.pynq_runtime_artifact_contract import (
        validate_pynq_artifact_completeness,
    )

    config = export_pynq(net, **kwargs)
    zip_bytes = config.to_zip(output_path=output_path)
    artifact = validate_pynq_artifact_completeness(zip_bytes)
    return config, artifact


def export_pynq(net: nengo.Network, **kwargs: Any) -> PynqOverlayConfig:
    """Export a Nengo network to the fixed overlay-v2 PYNQ contract."""
    bits = int(kwargs.get("bits", PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS[0]))
    if bits not in PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS:
        raise ValueError(
            f"The PYNQ overlay only supports {PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS}-bit weights"
        )

    populations: list[dict[str, Any]] = []
    connections: list[dict[str, Any]] = []
    ensemble_mapping: dict[int, str] = {}

    for index, ens in enumerate(net.all_ensembles):
        var_name = _clean_identifier(ens.label or f"pop_{index}")
        ensemble_mapping[id(ens)] = var_name

        nt = ens.neuron_type
        tau_rc = nt.tau_rc if isinstance(nt, nengo.LIF) else 0.02
        tau_ref = nt.tau_ref if isinstance(nt, nengo.LIF) else 0.002
        populations.append(
            {
                "id": var_name,
                "n_neurons": ens.n_neurons,
                "neuron_model": "LIF",
                "params": {
                    "tau_rc": tau_rc,
                    "tau_ref": tau_ref,
                    "v_threshold": 1.0,
                },
            }
        )

    if len(populations) > PYNQ_LIMITS.MAX_POPULATIONS:
        raise ValueError(
            f"The PYNQ overlay supports at most {PYNQ_LIMITS.MAX_POPULATIONS} populations; "
            f"got {len(populations)}"
        )

    for conn in net.all_connections:
        pre = conn.pre_obj
        post = conn.post_obj
        pre_ens = (
            pre if isinstance(pre, nengo.Ensemble) else getattr(pre, "ensemble", None)
        )
        post_ens = (
            post
            if isinstance(post, nengo.Ensemble)
            else getattr(post, "ensemble", None)
        )

        if (
            pre_ens is None
            or post_ens is None
            or id(pre_ens) not in ensemble_mapping
            or id(post_ens) not in ensemble_mapping
        ):
            continue

        pre_var = ensemble_mapping[id(pre_ens)]
        post_var = ensemble_mapping[id(post_ens)]
        if pre_var == post_var:
            raise ValueError(
                "The PYNQ overlay does not support recurrent or self-connections"
            )

        dense_weights = _extract_dense_connection_weights(
            conn,
            pre_size=pre_ens.n_neurons,
            post_size=post_ens.n_neurons,
        )
        for weight in dense_weights:
            connections.append(
                {
                    "pre": pre_var,
                    "post": post_var,
                    "weight": weight,
                }
            )

    _assert_layer_chain({(conn["pre"], conn["post"]) for conn in connections})

    raw_dict = {
        "network_name": net.label or "pynq_network",
        "populations": populations,
        "connections": connections,
        "overlay_id": PYNQ_LIMITS.OVERLAY_ID,
        "overlay_version": PYNQ_LIMITS.OVERLAY_VERSION,
    }
    # Refuse only what has no fixed-point image at all, and do it before
    # quantising: this used to demand that every scaled weight land exactly on an
    # integer, contradicting the `np.round` inside the quantiser it guarded and
    # rejecting every trained matrix -- invisible for as long as PYNQ weights were
    # zeros or hand-picked literals. See `quantisation_fidelity`.
    _assert_quantisable(connections, bits)
    quantised_dict = quantise_network_dict(raw_dict, bits=bits)

    for new_conn in quantised_dict["connections"]:
        new_conn["weight"] = int(new_conn["weight"])

    total_neurons = sum(int(pop["n_neurons"]) for pop in quantised_dict["populations"])
    if total_neurons > PYNQ_LIMITS.MAX_NEURONS:
        raise ValueError(
            f"Topology exceeds overlay-v2 constraints: "
            f"{total_neurons} neurons > {PYNQ_LIMITS.MAX_NEURONS} limit."
        )

    total_synapses = len(quantised_dict["connections"])
    max_synapses = PYNQ_LIMITS.max_synapses_for_bit_width(bits)
    if total_synapses > max_synapses:
        raise ValueError(
            "Topology exceeds overlay-v2 constraints: "
            f"{total_synapses} synapses > {max_synapses} limit."
        )

    overlay_manifest = PynqOverlayManifestContract().model_dump()
    register_map = _default_register_map()
    return PynqOverlayConfig(
        network_name=quantised_dict["network_name"],
        populations=quantised_dict["populations"],
        connections=quantised_dict["connections"],
        quantisation=quantised_dict.get(
            "quantisation", {"bits": bits, "scale_factor": 1.0}
        ),
        overlay_id=PYNQ_LIMITS.OVERLAY_ID,
        overlay_version=PYNQ_LIMITS.OVERLAY_VERSION,
        register_map=register_map,
        overlay_manifest=overlay_manifest,
    )


def _expand_ir_connection_weights(
    weight: float | list[float] | list[list[float]] | np.ndarray[Any, Any] | None,
    *,
    pre_size: int,
    post_size: int,
) -> list[float]:
    """Expand a NetworkIR connection weight into a dense row-major weight list."""
    weight_count = pre_size * post_size
    if weight is None:
        return [1.0] * weight_count
    if isinstance(weight, int | float):
        return [float(weight)] * weight_count

    array = np.asarray(weight, dtype=float)
    if array.size == 1:
        return [float(array.reshape(()))] * weight_count
    if array.size != weight_count:
        raise ValueError(
            "PYNQ overlay-v2 requires a dense connection weight whose size matches "
            f"{post_size}x{pre_size}; got {array.shape}"
        )
    return [float(w) for w in array.reshape(weight_count)]


def export_pynq_from_ir(ir: NetworkIR, bits: int = 8) -> PynqOverlayConfig:
    """Export a NeuroCNL ``NetworkIR`` to the fixed overlay-v2 PYNQ contract.

    Nengo-free counterpart to ``export_pynq`` — reads population/connection
    data straight from the lowered IR instead of a ``nengo.Network``.
    """
    if bits not in PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS:
        raise ValueError(
            f"The PYNQ overlay only supports {PYNQ_LIMITS.SUPPORTED_WEIGHT_BIT_WIDTHS}-bit weights"
        )

    # Port populations (declared input/output ports) are DMA-mapped I/O
    # boundaries, not hardware neuron populations — overlay-v2 has no weight
    # matrix for them, so they're excluded from the populations list and from
    # the connections below.
    real_population_names = {
        name
        for name, pop in ir.populations.items()
        if not (
            pop.population_type and pop.population_type.lower() in PORT_POPULATION_TYPES
        )
    }

    populations: list[dict[str, Any]] = []
    for name in real_population_names:
        pop = ir.populations[name]
        populations.append(
            {
                "id": name,
                "n_neurons": pop.size,
                "neuron_model": "LIF",
                "params": {
                    "tau_rc": pop.membrane_time_constant or 0.02,
                    "tau_ref": pop.refractory_period or 0.002,
                    "v_threshold": pop.threshold if pop.threshold is not None else 1.0,
                },
            }
        )

    if len(populations) > PYNQ_LIMITS.MAX_POPULATIONS:
        raise ValueError(
            f"The PYNQ overlay supports at most {PYNQ_LIMITS.MAX_POPULATIONS} populations; "
            f"got {len(populations)}"
        )

    connections: list[dict[str, Any]] = []
    for conn in ir.connections:
        if (
            conn.source not in real_population_names
            or conn.target not in real_population_names
        ):
            continue
        pre_pop = ir.populations[conn.source]
        post_pop = ir.populations[conn.target]
        if conn.source == conn.target:
            raise ValueError(
                "The PYNQ overlay does not support recurrent or self-connections"
            )

        dense_weights = _expand_ir_connection_weights(
            conn.weight,
            pre_size=pre_pop.size or 0,
            post_size=post_pop.size or 0,
        )
        for weight in dense_weights:
            connections.append(
                {
                    "pre": conn.source,
                    "post": conn.target,
                    "weight": weight,
                }
            )

    _assert_layer_chain({(conn["pre"], conn["post"]) for conn in connections})

    raw_dict = {
        "network_name": str(ir.metadata.get("network_name", "pynq_network")),
        "populations": populations,
        "connections": connections,
        "overlay_id": PYNQ_LIMITS.OVERLAY_ID,
        "overlay_version": PYNQ_LIMITS.OVERLAY_VERSION,
    }
    # Refuse only what has no fixed-point image at all, and do it before
    # quantising: this used to demand that every scaled weight land exactly on an
    # integer, contradicting the `np.round` inside the quantiser it guarded and
    # rejecting every trained matrix -- invisible for as long as PYNQ weights were
    # zeros or hand-picked literals. See `quantisation_fidelity`.
    _assert_quantisable(connections, bits)
    quantised_dict = quantise_network_dict(raw_dict, bits=bits)

    for new_conn in quantised_dict["connections"]:
        new_conn["weight"] = int(new_conn["weight"])

    total_neurons = sum(int(pop["n_neurons"]) for pop in quantised_dict["populations"])
    if total_neurons > PYNQ_LIMITS.MAX_NEURONS:
        raise ValueError(
            f"Topology exceeds overlay-v2 constraints: "
            f"{total_neurons} neurons > {PYNQ_LIMITS.MAX_NEURONS} limit."
        )

    total_synapses = len(quantised_dict["connections"])
    max_synapses = PYNQ_LIMITS.max_synapses_for_bit_width(bits)
    if total_synapses > max_synapses:
        raise ValueError(
            "Topology exceeds overlay-v2 constraints: "
            f"{total_synapses} synapses > {max_synapses} limit."
        )

    overlay_manifest = PynqOverlayManifestContract().model_dump()
    register_map = _default_register_map()
    return PynqOverlayConfig(
        network_name=quantised_dict["network_name"],
        populations=quantised_dict["populations"],
        connections=quantised_dict["connections"],
        quantisation=quantised_dict.get(
            "quantisation", {"bits": bits, "scale_factor": 1.0}
        ),
        overlay_id=PYNQ_LIMITS.OVERLAY_ID,
        overlay_version=PYNQ_LIMITS.OVERLAY_VERSION,
        register_map=register_map,
        overlay_manifest=overlay_manifest,
    )


def export_pynq_artifact_from_ir(
    ir: NetworkIR,
    bit_width: int,
    output_path: str | Path | None = None,
) -> tuple[PynqOverlayConfig, PynqRuntimeArtifact]:
    """Export a NeuroCNL ``NetworkIR`` as a validated overlay-v2 PYNQ artifact.

    Nengo-free counterpart to ``export_pynq_artifact`` — the artifact-building
    path used by ``deploy_pynq_network`` since the Nengo generation layer was
    removed.
    """
    from neurocnl.contracts.pynq_runtime_artifact_contract import (
        validate_pynq_artifact_completeness,
    )

    config = export_pynq_from_ir(ir, bits=bit_width)
    zip_bytes = config.to_zip(output_path=output_path)
    artifact = validate_pynq_artifact_completeness(zip_bytes)
    return config, artifact
