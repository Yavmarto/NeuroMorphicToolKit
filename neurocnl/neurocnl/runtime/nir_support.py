"""NIR runtime support classification for simulator backends.

Given a compiled ``nir.NIRGraph`` and a backend name, returns a
:class:`SupportClassification` describing which NIR nodes are exactly
supported, which are treated as approximate, and which are unsupported.

The classifier must run *before* any simulator dispatch so that the Studio
can show preflight status and structured diagnostics without launching a
potentially expensive simulation.

Supported backends
------------------
``lava_sim``, ``snntorch_sim``, ``sc_neurocore_sim``, ``brian2_sim``
    Native runtime simulators.
``brian2``, ``pynn``, ``lava``, ``rockpool``, ``sinabs``, ``nengo``, ``akida``,
``sc_neurocore_fpga``
    Codegen deploy targets (``backend/app/routers/notebook.py``'s dispatch),
    classified against the converter module each target actually invokes.

See ``list_supported_backends()`` for the full, current set. All NIR node
types not explicitly listed as ``"exact"`` or ``"approximate"`` for a given
backend are classified as unsupported and generate a diagnostic message that
surfaces before any runtime call or code generation.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal

import nir

# ---------------------------------------------------------------------------
# Per-backend NIR node support table
# ---------------------------------------------------------------------------
# "exact"       — node semantics are faithfully reproduced by this simulator.
# "approximate" — node is executed but with known semantic limitations
#                 (e.g. timestep quantization).  The Studio labels the run
#                 as "approximate" and shows a warning.
# "unsupported" — the node cannot be run by this simulator.  The run is
#                 rejected before dispatch with a structured diagnostic.
# ---------------------------------------------------------------------------

# The complete set of NIR primitives that must have explicit verdicts in every
# backend sub-dict.  Used by the classifier and the test suite.
COMPLETE_PRIMITIVE_SET: frozenset[str] = frozenset(
    {
        "Input",
        "Output",
        "Linear",
        "Affine",
        "Conv2d",
        "Flatten",
        "IF",
        "LIF",
        "CubaLIF",
        "LI",
        "AvgPool2d",
        "SumPool2d",
        "Delay",
        "Scale",
        "Threshold",
        "Sigmoid",
        "I",  # Integrator
        "CubaLI",
        # ── CNLStudio-internal node types (not standard NIR primitives) ──────────
        "Synaptic",  # cnl.Synaptic — snnTorch snn.Synaptic with dual time constants
        "RSynaptic",  # cnl.RSynaptic — snnTorch snn.RSynaptic with built-in recurrence
        "RLeaky",  # cnl.RLeaky — snnTorch snn.RLeaky (recurrent LIF, (spk,mem) state)
        "Leaky",  # cnl.Leaky — snnTorch snn.Leaky with explicit beta, init_hidden=False
        "BatchNorm1d",  # cnl.BatchNorm1d — nn.BatchNorm1d, stateless
        "Dropout",  # cnl.Dropout — nn.Dropout, stateless
    }
)

_BACKEND_NIR_SUPPORT: dict[str, dict[str, str]] = {
    "sc_neurocore_sim": {
        # ── Boundary nodes ──────────────────────────────────────────────────
        "Input": "exact",
        "Output": "exact",
        # ── Weight / connectivity nodes ──────────────────────────────────────
        "Linear": "exact",
        "Affine": "exact",  # sc-neurocore maps affine to its linear+bias kernel
        "Conv2d": "unsupported",  # Convolutional kernels are out of scope for the Rust sim path
        "Flatten": "unsupported",  # No reshape primitive in the sc-neurocore Rust sim
        # ── Neuron / dynamics nodes ──────────────────────────────────────────
        "IF": "exact",  # sc-neurocore natively models integrate-and-fire
        "LIF": "exact",
        "CubaLIF": "approximate",  # Mapped to LIF with averaged tau; synaptic filter not modelled
        "LI": "unsupported",  # Leaky integrator without threshold not in sc-neurocore
        "I": "unsupported",  # Pure integrator not in sc-neurocore
        # ── Pooling nodes ────────────────────────────────────────────────────
        "AvgPool2d": "unsupported",  # No pooling primitive in the Rust sim path
        "SumPool2d": "unsupported",
        # ── Delay node ───────────────────────────────────────────────────────
        "Delay": "approximate",  # Timestep-quantised buffer; sub-timestep delays lost
        # ── Activation / transform nodes ─────────────────────────────────────
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        # ── CNLStudio-internal node types ────────────────────────────────────
        "Synaptic": "unsupported",  # snnTorch-only; sc-neurocore has no synaptic filter
        "RSynaptic": "unsupported",  # snnTorch-only; recurrent connections out of scope
        "RLeaky": "unsupported",  # snnTorch-only; no sc-neurocore recurrent LIF
        "Leaky": "unsupported",  # snnTorch-only; explicit-beta LIF
        "BatchNorm1d": "unsupported",  # PyTorch-only; no sc-neurocore equivalent
        "Dropout": "unsupported",  # training-only; not relevant for sc-neurocore
    },
    "lava_sim": {
        # ── Boundary nodes ──────────────────────────────────────────────────
        "Input": "exact",
        "Output": "exact",
        # ── Weight / connectivity nodes ──────────────────────────────────────
        "Linear": "exact",
        "Affine": "approximate",  # Affine -> lava.proc.dense.Dense mapping proven in paper/nir_to_lava.py (zero-bias constraint)
        "Conv2d": "unsupported",  # lava-nc has no Conv process; lava-dl netx is out of scope
        "Flatten": "unsupported",  # lava-nc has no flatten process; lava-dl is out of scope
        # ── Neuron / dynamics nodes ──────────────────────────────────────────
        "IF": "unsupported",  # lava-nc LIF has no IF (infinite-tau) mode
        "LIF": "exact",
        "CubaLIF": "approximate",  # approximated via LIF with adjusted tau; alpha not modelled
        "LI": "unsupported",  # leaky integrator without threshold — no lava-nc process
        "I": "unsupported",  # pure integrator — no lava-nc process
        # ── Pooling nodes ────────────────────────────────────────────────────
        "AvgPool2d": "unsupported",  # no lava-nc pooling process; lava-dl has it
        "SumPool2d": "unsupported",  # no lava-nc pooling process
        # ── Delay node ───────────────────────────────────────────────────────
        "Delay": "approximate",  # approximated via buffer register; sub-timestep delays lost
        # ── Activation / transform nodes ─────────────────────────────────────
        "Scale": "unsupported",  # no lava-nc scalar-multiply process
        "Threshold": "unsupported",  # no lava-nc threshold process separate from LIF
        "Sigmoid": "unsupported",  # not a lava-nc process
        "CubaLI": "unsupported",  # no lava-nc process
        # ── CNLStudio-internal node types ────────────────────────────────────
        "Synaptic": "unsupported",  # snnTorch-only; no lava-nc equivalent
        "RSynaptic": "unsupported",  # snnTorch-only; no lava-nc equivalent
        "RLeaky": "unsupported",  # snnTorch-only; no lava-nc recurrent LIF
        "Leaky": "unsupported",  # snnTorch-only; explicit-beta LIF
        "BatchNorm1d": "unsupported",  # PyTorch-only; no lava-nc equivalent
        "Dropout": "unsupported",  # training-only; not relevant for lava-nc
    },
    "snntorch_sim": {
        # ── Boundary nodes ──────────────────────────────────────────────────
        "Input": "exact",
        "Output": "exact",
        # ── Weight / connectivity nodes ──────────────────────────────────────
        "Linear": "exact",
        "Affine": "exact",  # nn.Linear(weight, bias)
        "Conv2d": "exact",  # nn.Conv2d — weight shape (out, in, kH, kW)
        "Flatten": "exact",  # nn.Flatten(start_dim=1)
        # ── Neuron / dynamics nodes ──────────────────────────────────────────
        "IF": "exact",  # snntorch.Lapicque with large R*C
        "LIF": "exact",
        "CubaLIF": "approximate",  # snntorch.Leaky — alpha (synaptic filter) not modelled
        "LI": "unsupported",  # no snnTorch equivalent without enabling training mode
        "I": "unsupported",  # pure integrator — no snnTorch equivalent
        # ── Pooling nodes ────────────────────────────────────────────────────
        "AvgPool2d": "exact",  # nn.AvgPool2d(kernel_size, stride)
        "SumPool2d": "exact",  # snnTorch has no distinct SumPool2d op; codegen
        # builds nn.AvgPool2d(kernel_size, stride, divisor_override=1), which
        # matches real oracle behavior (validated against paper/02_cnn's
        # cnn_sinabs.nir reference — see notebook.py's nir.SumPool2d branch)
        # ── Delay node ───────────────────────────────────────────────────────
        "Delay": "approximate",  # passthrough; sub-timestep delays not modelled
        # ── Activation / transform nodes ─────────────────────────────────────
        "Scale": "unsupported",  # no NIR-native snnTorch equivalent
        "Threshold": "unsupported",  # no NIR-native snnTorch equivalent
        "Sigmoid": "unsupported",  # not a NIR primitive
        "CubaLI": "unsupported",  # no snnTorch equivalent
        # ── CNLStudio-internal node types ────────────────────────────────────
        "Synaptic": "exact",  # snn.Synaptic — dual time constant (alpha/beta) LIF
        "RSynaptic": "exact",  # snn.RSynaptic — Synaptic with built-in recurrent Linear
        "RLeaky": "exact",  # snn.RLeaky — recurrent LIF with (spk, mem) state
        "Leaky": "exact",  # snn.Leaky — explicit-beta LIF, init_hidden=False
        "BatchNorm1d": "exact",  # nn.BatchNorm1d — pure PyTorch, framework-agnostic
        "Dropout": "exact",  # nn.Dropout — pure PyTorch, framework-agnostic
    },
    "brian2": {
        # ── Boundary nodes ──────────────────────────────────────────────────
        "Input": "exact",  # no isinstance branch; implicit no-op, no crash
        "Output": "exact",  # same
        # ── Weight / connectivity nodes ──────────────────────────────────────
        "Linear": "exact",  # weight correctly extracted and applied via Synapses.w
        "Affine": "unsupported",  # no isinstance branch at all
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        # ── Neuron / dynamics nodes ──────────────────────────────────────────
        "IF": "unsupported",
        "LIF": "approximate",  # threshold hardcoded 'v > 1.0'/reset 'v = 0.0'; v_threshold/v_leak/r ignored
        "CubaLIF": "unsupported",  # CRASHES: node.tau accessed but CubaLIF has no .tau (only tau_syn/tau_mem)
        "LI": "unsupported",
        "I": "unsupported",
        # ── Pooling nodes ────────────────────────────────────────────────────
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        # ── Delay node ───────────────────────────────────────────────────────
        "Delay": "unsupported",
        # ── Activation / transform nodes ─────────────────────────────────────
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        # ── CNLStudio-internal node types ────────────────────────────────────
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "pynn": {
        "Input": "exact",
        "Output": "exact",
        "Linear": "exact",  # weight correctly applied via FromListConnector
        "Affine": "unsupported",
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "unsupported",
        "LIF": "approximate",  # v_thresh/v_reset hardcoded -50.0/-65.0; only tau used
        "CubaLIF": "unsupported",  # CRASHES: same node.tau bug as brian2_io
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "unsupported",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "lava": {
        # Hardware codegen target (LavaIO.from_nir) — distinct from lava_sim's
        # native runtime dispatch (lava_simulator.py) above.
        "Input": "exact",
        "Output": "exact",
        "Linear": "exact",  # weight passed through directly to Dense
        "Affine": "unsupported",  # no isinstance branch at all
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "unsupported",
        "LIF": "approximate",  # integer 'du' decay quantization; vth hardcoded 128, v_threshold ignored
        "CubaLIF": "unsupported",  # CRASHES: same node.tau bug as brian2_io/pynn_io
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "unsupported",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "rockpool": {
        "Input": "exact",  # never dispatched (traversal starts at input's successor) — correct no-op
        "Output": "exact",  # explicit `continue`
        "Linear": "exact",  # LinearTorch, weight transposed correctly
        "Affine": "unsupported",  # no isinstance branch at all — hits `else: raise ValueError`
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "unsupported",
        "LIF": "approximate",  # tau_mem/threshold correctly sourced; v_leak mapped onto LIFTorch's `bias` (different semantics)
        "CubaLIF": "approximate",  # ExpSynTorch + conditional LIFTorch via node.tau_syn/tau_mem (correct attrs, no crash)
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "unsupported",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",  # not dispatched — hits `else: raise ValueError`
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "sinabs": {
        "Input": "exact",  # SinabsIO.from_nir now skips Input/Output explicitly
        "Output": "exact",
        "Linear": "exact",  # weight copied to nn.Linear(bias=False)
        "Affine": "exact",  # weight+bias copied to nn.Linear(bias=True)
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "approximate",  # maps to sl.IAF() with zero params — node's r/v_threshold silently dropped
        "LIF": "approximate",  # only tau_mem used; threshold/v_leak/r dropped to sinabs' own sl.LIF defaults
        "CubaLIF": "unsupported",  # not in `_SUPPORTED` tuple — raises NotImplementedError
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "unsupported",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "nengo": {
        "Input": "exact",  # explicit nengo.Node(None, size_in=...) from input_type
        "Output": "exact",  # same, from output_type
        "Linear": "exact",  # emitted as a Node computing weight @ x — exact weight application
        "Affine": "exact",  # weight @ x + bias, exact
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "unsupported",
        "LIF": "approximate",  # correct tau/threshold reparametrization, but requires r==1 and v_leak==0 (raises otherwise)
        "CubaLIF": "approximate",  # correct tau_syn/tau_mem discretization-corrected mapping, but requires uniform r/v_leak/v_threshold/tau_syn/tau_mem (raises otherwise)
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "unsupported",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",  # not one of Input/Output/LIF/CubaLIF/Linear/Affine — raises ValueError
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "akida": {
        # _generate_akida_code() in backend/app/routers/notebook.py, mirrors
        # converter.akida_adapter.nir_to_akida.
        "Input": "exact",  # explicit akl.InputLayer(input_shape=...)
        "Output": "exact",  # no explicit layer needed — Akida has no OutputLayer concept, correct no-op
        "Linear": "approximate",  # akl.FullyConnected(activation=True); int8-quantized, neuron params not read from any adjacent node
        "Affine": "approximate",  # same as Linear — node.bias is never read at all (dropped, not just quantized)
        "Conv2d": "approximate",  # InputConvolutional/Convolutional, int8-quantized, groups>1 rejected
        "Flatten": "exact",  # no explicit layer needed — Akida flattens implicitly between conv and dense
        "IF": "unsupported",  # standalone neuron nodes are never emitted — structurally dropped, not just imprecise
        "LIF": "unsupported",  # same — no isinstance branch handles LIF/CubaLIF at all
        "CubaLIF": "unsupported",
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "approximate",  # only as a global pool fused into the preceding conv; windowed pooling rejected
        "SumPool2d": "unsupported",  # no Akida equivalent — always rejected, not silently approximated
        "Delay": "unsupported",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
    "sc_neurocore_fpga": {
        # Dispatches through the identical _generate_sc_neurocore_code() function
        # as sc_neurocore_sim (notebook.py) plus an appended FPGA-synthesis
        # comment — verdicts are a literal copy of "sc_neurocore_sim" above.
        "Input": "exact",
        "Output": "exact",
        "Linear": "exact",
        "Affine": "exact",
        "Conv2d": "unsupported",
        "Flatten": "unsupported",
        "IF": "exact",
        "LIF": "exact",
        "CubaLIF": "approximate",
        "LI": "unsupported",
        "I": "unsupported",
        "AvgPool2d": "unsupported",
        "SumPool2d": "unsupported",
        "Delay": "approximate",
        "Scale": "unsupported",
        "Threshold": "unsupported",
        "Sigmoid": "unsupported",
        "CubaLI": "unsupported",
        "Synaptic": "unsupported",
        "RSynaptic": "unsupported",
        "RLeaky": "unsupported",
        "Leaky": "unsupported",
        "BatchNorm1d": "unsupported",
        "Dropout": "unsupported",
    },
}

# Runtime simulators share codegen NIR tables; codegen targets keep the plain ids.
_BACKEND_NIR_SUPPORT["brian2_sim"] = dict(_BACKEND_NIR_SUPPORT["brian2"])
_BACKEND_NIR_SUPPORT["nengo_sim"] = dict(_BACKEND_NIR_SUPPORT["nengo"])
_BACKEND_NIR_SUPPORT["sinabs_sim"] = dict(_BACKEND_NIR_SUPPORT["sinabs"])

# Display names for structured diagnostic messages
_BACKEND_DISPLAY_NAMES: dict[str, str] = {
    "lava_sim": "Lava simulator",
    "snntorch_sim": "snnTorch simulator",
    "sc_neurocore_sim": "SC-NeuroCore simulator",
    "brian2_sim": "Brian2 simulator",
    "nengo_sim": "Nengo simulator",
    "sinabs_sim": "Sinabs simulator",
    "brian2": "Brian2",
    "pynn": "PyNN",
    "lava": "Lava (hardware codegen)",
    "rockpool": "Rockpool",
    "sinabs": "Sinabs",
    "nengo": "Nengo",
    "akida": "BrainChip Akida",
    "sc_neurocore_fpga": "SC-NeuroCore FPGA",
}


@dataclass(slots=True)
class SupportClassification:
    """Result of classifying a NIR graph against one simulator backend.

    Attributes
    ----------
    level : {"exact", "approximate", "unsupported"}
        Overall support level.  "unsupported" means at least one node
        cannot be executed by the backend.  "approximate" means all nodes
        can run but at least one has known semantic limitations.  "exact"
        means full faithful execution.
    supported_nodes : list[str]
        Node type names that are exactly supported.
    unsupported_nodes : list[str]
        Node type names that cannot be executed.  Non-empty → level is
        "unsupported".
    approximate_nodes : list[str]
        Node type names that are executed with approximate semantics.
    diagnostics : list[str]
        Human-readable messages, one per unsupported or approximate node
        type encountered in the graph.
    """

    level: Literal["exact", "approximate", "unsupported"]
    supported_nodes: list[str] = field(default_factory=list)
    unsupported_nodes: list[str] = field(default_factory=list)
    approximate_nodes: list[str] = field(default_factory=list)
    diagnostics: list[str] = field(default_factory=list)


def classify_nir_graph(
    graph: nir.NIRGraph,
    backend_name: str,
) -> SupportClassification:
    """Classify a compiled NIR graph for a given simulator backend.

    Parameters
    ----------
    graph : nir.NIRGraph
        The compiled NIR graph returned by :func:`neurocnl.compile_to_nir`.
    backend_name : str
        Simulator backend identifier.  Must be one of ``"lava_sim"`` or
        ``"snntorch_sim"``.

    Returns
    -------
    SupportClassification
        Classification result.  Callers should check ``level`` before
        dispatching to a simulator and surface ``diagnostics`` to the user
        when the level is not ``"exact"``.

    Raises
    ------
    ValueError
        If ``backend_name`` is not a known simulator backend.
    """
    support_table = _BACKEND_NIR_SUPPORT.get(backend_name)
    if support_table is None:
        known = ", ".join(sorted(_BACKEND_NIR_SUPPORT))
        raise ValueError(
            f"Unknown simulator backend {backend_name!r}. Known simulator backends: {known}."
        )

    display_name = _BACKEND_DISPLAY_NAMES.get(backend_name, backend_name)

    # Collect unique node type names from the graph.
    seen_types: dict[str, str] = {}  # type_name → support verdict
    for _name, node in graph.nodes.items():
        type_name = type(node).__name__
        if type_name not in seen_types:
            verdict = support_table.get(type_name, "unsupported")
            seen_types[type_name] = verdict

    supported_nodes: list[str] = []
    approximate_nodes: list[str] = []
    unsupported_nodes: list[str] = []
    diagnostics: list[str] = []

    for type_name, verdict in sorted(seen_types.items()):
        if verdict == "exact":
            supported_nodes.append(type_name)
        elif verdict == "approximate":
            approximate_nodes.append(type_name)
            diagnostics.append(
                f"{display_name}: nir.{type_name} is executed with approximate semantics "
                f"(timestep quantization may differ). Results are labelled 'approximate'."
            )
        else:
            unsupported_nodes.append(type_name)
            diagnostics.append(
                f"{display_name}: nir.{type_name} is not supported and cannot be executed. "
                f"Remove or replace this node type before running the simulation."
            )

    if unsupported_nodes:
        level: Literal["exact", "approximate", "unsupported"] = "unsupported"
    elif approximate_nodes:
        level = "approximate"
    else:
        level = "exact"

    return SupportClassification(
        level=level,
        supported_nodes=supported_nodes,
        approximate_nodes=approximate_nodes,
        unsupported_nodes=unsupported_nodes,
        diagnostics=diagnostics,
    )


def list_supported_backends() -> list[str]:
    """Return the list of known simulator backend names."""
    return list(_BACKEND_NIR_SUPPORT)


# Backends dispatchable via /simulators/run (live runtime execution) — a
# strict subset of list_supported_backends(), which also includes codegen-
# only deploy targets handled by notebook.py's /notebook/generate-v2 (e.g.
# brian2, sinabs, rockpool, pynn, nengo, akida, lava, sc_neurocore_fpga).
# simulators.py's /simulators/run has no dispatch branch for those — it must
# reject them, not silently fall through to a mismatched simulator.
SIMULATOR_RUNTIME_BACKENDS: frozenset[str] = frozenset(
    {
        "lava_sim",
        "snntorch_sim",
        "sc_neurocore_sim",
        "brian2_sim",
        "nengo_sim",
        "sinabs_sim",
    }
)


def list_simulator_backends() -> list[str]:
    """Return the backend names /simulators/run can actually dispatch to."""
    return sorted(SIMULATOR_RUNTIME_BACKENDS)


def get_supported_node_types(backend_name: str) -> dict[str, str]:
    """Return the node-type → support-level table for a backend.

    Parameters
    ----------
    backend_name : str
        Simulator backend identifier.

    Returns
    -------
    dict[str, str]
        Mapping of NIR node class name to support verdict
        (``"exact"``, ``"approximate"``, or ``"unsupported"``).

    Raises
    ------
    ValueError
        If ``backend_name`` is not a known simulator backend.
    """
    table = _BACKEND_NIR_SUPPORT.get(backend_name)
    if table is None:
        known = ", ".join(sorted(_BACKEND_NIR_SUPPORT))
        raise ValueError(
            f"Unknown simulator backend {backend_name!r}. Known simulator backends: {known}."
        )
    return dict(table)
