"""NIR (Neuromorphic Intermediate Representation) exporter."""

from __future__ import annotations

import os
import re
from pathlib import Path
from typing import Any

import nengo
import nir
import numpy as np

from neurocnl.cnl.types import ParsedSentence
from neurocnl.compile import CompileError, Diagnostic
from neurocnl.ir import LoweringError, Materializer, NetworkIR, lower_to_ir
from neurocnl.ir.materializer import NirLoweringSummary

# ponytail: hardcoded — capabilities registry marks stdp as "approximate" for all backends;
# update when capabilities.py adds explicit online_learn verdict
ONLINE_LEARN_BACKENDS: frozenset[str] = frozenset({"lava", "loihi", "loihi2"})

_NIR_CONCEPT_VERDICTS = {
    "threshold_firing": "lowered_faithfully",
    "refractory_period": "lowered_as_metadata",
    "membrane_potential_decay": "lowered_faithfully",
    "synaptic_weight": "lowered_faithfully",
    "axonal_delay": "lowered_faithfully",
    "timing_declaration": "lowered_as_metadata",
    "stdp_learning": "lowered_as_metadata",
    "inhibitory_connection": "lowered_faithfully",
    "population_coding": "lowered_approximately",
    "network_topology": "lowered_approximately",
    "lateral_inhibition": "lowered_approximately",
    "homeostatic_plasticity": "lowered_approximately",
    "neuromodulation": "lowered_as_metadata",
    "population_coding_range": "lowered_as_metadata",
    "adaptive_spiking": "lowered_as_metadata",
    "receptor_dynamics": "lowered_as_metadata",
    "short_term_plasticity": "lowered_approximately",
    "background_noise": "lowered_as_metadata",
    "spatial_connectivity": "not_lowered",
    "akida_hardware": "not_lowered",
    "akida_spatiotemporal": "not_lowered",
}


def sanitize_label(label: str) -> str:
    """Sanitize a label for NIR compatibility.

    Replaces non-alphanumeric characters (excluding underscores) with underscores.
    """
    if not label:
        return ""
    return re.sub(r"[^a-zA-Z0-9_]", "_", label)


def _derive_online_learn_backends() -> frozenset[str]:
    """Derive backends that support online learning from capability registry.

    Queries BACKEND_CAPABILITIES to find backends with 'faithful' support for
    online learning concepts (stdp_learning or online_learn).
    """
    from neurocnl.backends.capabilities import BACKEND_CAPABILITIES

    backends: set[str] = set()
    for name, profile in BACKEND_CAPABILITIES.items():
        # Check for faithful support of stdp_learning or online_learn concepts
        if profile.concept_support.get("stdp_learning") == "faithful":
            backends.add(name)
        if profile.concept_support.get("online_learn") == "faithful":
            backends.add(name)
    return frozenset(backends)


# Derive ONLINE_LEARN_BACKENDS at module load time
ONLINE_LEARN_BACKENDS = _derive_online_learn_backends()


def validate_deployment_mode_fidelity(model: NetworkIR, backend: str) -> None:
    """Validate deployment_mode constraints against backend capabilities.

    Parameters
    ----------
    model : NetworkIR
        The network IR to validate.
    backend : str
        The target backend name.

    Raises
    ------
    CompileError
        If any LearningRuleIR has deployment_mode == "online_learn" and the
        target backend is not in ONLINE_LEARN_BACKENDS.
    """
    from neurocnl.compile import Diagnostic

    # Normalize backend name for comparison
    backend_normalized = backend.strip().lower()

    for rule in model.learning_rules:
        if (
            rule.deployment_mode == "online_learn"
            and backend_normalized not in ONLINE_LEARN_BACKENDS
        ):
            msg = (
                f"online_learn requires a backend with faithful online learning support "
                f"(such as Lava/Loihi); '{backend}' supports offline_train only."
            )
            raise CompileError(
                msg,
                [
                    Diagnostic(
                        stage="concept_fidelity_audit",
                        code="deployment_mode_unsupported",
                        message=msg,
                    )
                ],
            )


def _extract_weight(conn: nengo.Connection) -> np.ndarray[Any, Any]:
    """Extract a deterministic weight from a Nengo connection.

    Raises ValueError if the weight is stochastic.
    """
    weight: float | int | np.ndarray[Any, Any] = 1.0
    if not hasattr(conn, "transform"):
        return np.array(weight)

    t = conn.transform
    if isinstance(t, nengo.transforms.Dense):
        if isinstance(t.init, nengo.dists.Distribution):
            raise ValueError(
                "NIR exporter does not support stochastic (distribution-based) weights. "
                "Please provide a deterministic transform."
            )
        weight = t.init
    elif isinstance(t, nengo.transforms.Sparse):
        raise ValueError(f"NIR exporter does not support transform type {type(t)}")
    elif hasattr(t, "init"):
        if isinstance(t.init, nengo.dists.Distribution):
            raise ValueError(
                "NIR exporter does not support stochastic (distribution-based) weights. "
                "Please provide a deterministic transform."
            )
        weight = t.init
    elif isinstance(t, int | float | np.ndarray):
        weight = t
    elif isinstance(t, nengo.transforms.NoTransform):
        weight = 1.0
    else:
        raise ValueError(f"NIR exporter does not support transform type {type(t)}")

    return np.array(weight, dtype=float)


def _legacy_nengo_to_nir_graph(net: nengo.Network) -> nir.NIRGraph:
    """Convert a legacy Nengo network into a NIR graph."""
    nodes = {}
    edges = []

    ensemble_to_label = {}
    for i, ens in enumerate(net.all_ensembles):
        label = sanitize_label(ens.label) or f"ens_{i}"
        ensemble_to_label[id(ens)] = label

        tau = np.full(ens.dimensions, getattr(ens.neuron_type, "tau_rc", 0.02))
        r = np.ones(ens.dimensions)
        v_leak = np.zeros(ens.dimensions)
        v_threshold = np.ones(ens.dimensions)
        v_reset = np.zeros(ens.dimensions)

        nodes[label] = nir.LIF(
            tau=tau,
            r=r,
            v_leak=v_leak,
            v_threshold=v_threshold,
            v_reset=v_reset,
        )

    for i, conn in enumerate(net.all_connections):
        pre = conn.pre_obj
        post = conn.post_obj

        if isinstance(pre, nengo.Node) and isinstance(
            post, nengo.Ensemble | nengo.ensemble.Neurons
        ):
            post_ens = (
                post
                if isinstance(post, nengo.Ensemble)
                else getattr(post, "ensemble", None)
            )
            if post_ens and id(post_ens) in ensemble_to_label:
                input_label = sanitize_label(pre.label) or f"input_{i}"
                if input_label not in nodes:
                    nodes[input_label] = nir.Input(
                        input_type={"input": np.array([pre.size_out])}
                    )

                post_label = ensemble_to_label[id(post_ens)]
                weight = _extract_weight(conn)
                weight_label = f"weight_in_{input_label}_{i}"
                if weight.ndim == 0:
                    target_dim = post_ens.dimensions
                    weight = (
                        np.full((target_dim, 1), weight.item())
                        if target_dim > 1
                        else np.array([[weight.item()]])
                    )
                elif weight.ndim == 1:
                    weight = weight.reshape((-1, 1))
                nodes[weight_label] = nir.Linear(weight=weight)
                edges.append((input_label, weight_label))
                edges.append((weight_label, post_label))
            continue

        if isinstance(post, nengo.Node) and isinstance(
            pre, nengo.Ensemble | nengo.ensemble.Neurons
        ):
            pre_ens = (
                pre
                if isinstance(pre, nengo.Ensemble)
                else getattr(pre, "ensemble", None)
            )
            if pre_ens and id(pre_ens) in ensemble_to_label:
                output_label = sanitize_label(post.label) or f"output_{i}"
                if output_label not in nodes:
                    nodes[output_label] = nir.Output(
                        output_type={"output": np.array([post.size_in])}
                    )

                pre_label = ensemble_to_label[id(pre_ens)]
                weight = _extract_weight(conn)
                weight_label = f"weight_out_{output_label}_{i}"
                if weight.ndim == 0:
                    source_dim = pre_ens.dimensions
                    weight = (
                        np.full((1, source_dim), weight.item())
                        if source_dim > 1
                        else np.array([[weight.item()]])
                    )
                elif weight.ndim == 1:
                    weight = weight.reshape((1, -1))
                nodes[weight_label] = nir.Linear(weight=weight)
                edges.append((pre_label, weight_label))
                edges.append((weight_label, output_label))
            continue

        pre_ens = (
            pre if isinstance(pre, nengo.Ensemble) else getattr(pre, "ensemble", None)
        )
        post_ens = (
            post
            if isinstance(post, nengo.Ensemble)
            else getattr(post, "ensemble", None)
        )
        if not pre_ens or not post_ens:
            continue
        if (
            id(pre_ens) not in ensemble_to_label
            or id(post_ens) not in ensemble_to_label
        ):
            continue

        pre_label = ensemble_to_label[id(pre_ens)]
        post_label = ensemble_to_label[id(post_ens)]
        weight_label = f"weight_{pre_label}_to_{post_label}_{i}"
        weight = _extract_weight(conn)
        if weight.ndim == 0:
            weight = np.array([[weight.item()]])
        elif weight.ndim == 1:
            weight = weight.reshape((1, -1))
        nodes[weight_label] = nir.Linear(weight=weight)
        edges.append((pre_label, weight_label))
        edges.append((weight_label, post_label))

    for i, probe in enumerate(net.all_probes):
        target = probe.target
        target_ens = (
            target
            if isinstance(target, nengo.Ensemble)
            else getattr(target, "ensemble", None)
        )
        if target_ens and id(target_ens) in ensemble_to_label:
            output_label = sanitize_label(probe.label) or f"probe_{i}"
            if output_label not in nodes:
                nodes[output_label] = nir.Output(
                    output_type={"output": np.array([target_ens.size_out])}
                )
                edges.append((ensemble_to_label[id(target_ens)], output_label))

    return nir.NIRGraph(nodes=nodes, edges=edges)


def materialize_to_nir(model: NetworkIR) -> nir.NIRGraph:
    """Materialize a semantic ``NetworkIR`` into a ``nir.NIRGraph``."""
    return Materializer().materialize(model)


def summarize_nir_lowering(model: NetworkIR) -> NirLoweringSummary:
    """Summarize how a ``NetworkIR`` lowers into current NIR semantics."""
    return Materializer().summarize_lowering(model)


def summarize_nir_concepts(parsed_specs: list[ParsedSentence]) -> dict[str, str]:
    """Classify parsed concepts against the current honest NIR subset."""
    concepts = sorted({str(spec["concept"]) for spec in parsed_specs})
    try:
        ir_model = lower_to_ir(parsed_specs)
    except LoweringError:
        return {
            concept: _NIR_CONCEPT_VERDICTS.get(concept, "not_lowered")
            for concept in concepts
        }

    lowering_verdicts = summarize_nir_lowering(ir_model).concept_verdicts
    return {
        concept: lowering_verdicts.get(
            concept, _NIR_CONCEPT_VERDICTS.get(concept, "not_lowered")
        )
        for concept in concepts
    }


def ensure_nir_exportable(parsed_specs: list[ParsedSentence]) -> None:
    """Reject parsed concepts that current NIR export cannot represent honestly."""
    concept_verdicts = summarize_nir_concepts(parsed_specs)
    rejected = sorted(
        concept
        for concept, verdict in concept_verdicts.items()
        if verdict == "not_lowered"
    )
    if not rejected:
        return

    rejected_list = ", ".join(rejected)
    raise ValueError(
        "NIR export rejected because the current direct CNL -> IR -> NIR bridge cannot "
        f"honestly lower these parser-recognized concepts: {rejected_list}."
    )


def audit_deployment_mode(ir: NetworkIR, backend_name: str) -> None:
    """Raise CompileError if any learning rule requires online_learn on an unsupported backend.

    Parameters
    ----------
    ir : NetworkIR
        The compiled network IR to audit.
    backend_name : str
        The target backend identifier (e.g. ``"nir"``, ``"loihi"``).

    Raises
    ------
    CompileError
        When a learning rule declares ``deployment_mode="online_learn"`` and the
        target backend is not in :data:`ONLINE_LEARN_BACKENDS`.
    """
    for rule in ir.learning_rules:
        if (
            rule.deployment_mode == "online_learn"
            and backend_name not in ONLINE_LEARN_BACKENDS
        ):
            msg = f"online_learn requires Lava/Loihi2; {backend_name!r} supports offline_train only"
            diag = Diagnostic(
                stage="exportability",
                code="unsupported_deployment_mode",
                message=msg,
                hint=f"Set deployment_mode='offline_train' or target one of: {sorted(ONLINE_LEARN_BACKENDS)}",
            )
            raise CompileError(msg, [diag])


def convert_to_nir_graph(model: NetworkIR | nengo.Network) -> nir.NIRGraph:
    """Convert a semantic IR or legacy Nengo network to a NIR graph."""
    if isinstance(model, NetworkIR):
        return materialize_to_nir(model)
    return _legacy_nengo_to_nir_graph(model)


def export_to_nir(
    model: NetworkIR | nengo.Network,
    filename: str | Path,
    *,
    backend: str | None = None,
) -> None:
    """Export a semantic IR or legacy Nengo network to a NIR file.

    Parameters
    ----------
    model : NetworkIR | nengo.Network
        The source model to export.
    filename : str or Path
        The filename to save the NIR graph to.
    backend : str or None, optional
        Target backend name (e.g. ``"snntorch"``, ``"loihi2"``).  When
        provided and *model* is a :class:`NetworkIR`, deployment-mode
        fidelity is validated before writing — a
        :class:`~neurocnl.compile.CompileError` is raised if any learning
        rule requires ``online_learn`` on an unsupported backend.
    """
    if isinstance(model, NetworkIR) and backend is not None:
        audit_deployment_mode(model, backend)
    os.makedirs(os.path.dirname(os.path.abspath(filename)), exist_ok=True)
    nir.write(str(filename), convert_to_nir_graph(model))
