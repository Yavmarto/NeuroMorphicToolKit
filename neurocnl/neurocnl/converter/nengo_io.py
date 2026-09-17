"""Nengo framework importer/exporter for NIR.

Maps Nengo ensembles and connections to NIR nodes and edges.
"""

from __future__ import annotations

import math
import re
from typing import Any

import nengo
import nir
import numpy as np


def _slug(name: str) -> str:
    """Convert an arbitrary NIR node name into a valid Python identifier.

    Mirrors backend.app.routers.notebook._python_identifier's convention
    (lowercase, non-alnum -> underscore, digit-leading -> n_ prefix) so
    generated variable names are readable the same way other converters'
    code-gen output is.
    """
    slug = re.sub(r"[^a-z0-9_]+", "_", name.lower()).strip("_")
    if not slug:
        return "node"
    if slug[0].isdigit():
        return f"n_{slug}"
    return slug


class NengoIO:
    """Nengo framework handler for NIR conversion."""

    def to_nir(self, model: nengo.Network, **kwargs: Any) -> nir.NIRGraph:
        """Convert a Nengo network to NIR.

        Maps Nengo Ensembles to NIR LIF nodes and Nengo Connections to NIR Linear/Affine nodes.
        """
        nodes: dict[str, nir.NIRNode] = {}
        edges: list[tuple[str, str]] = []

        # Map Ensembles to NIR LIF nodes
        for i, ens in enumerate(model.all_ensembles):
            label = (ens.label or f"pop_{i}").replace(" ", "_")
            nt = ens.neuron_type
            if isinstance(nt, nengo.LIF):
                tau_rc = np.full(ens.n_neurons, nt.tau_rc)
                _tau_ref = np.full(ens.n_neurons, nt.tau_ref)  # NIR LIF has no tau_ref field
                v_threshold = np.ones(ens.n_neurons)
                nodes[label] = nir.LIF(
                    tau=tau_rc,
                    v_threshold=v_threshold,
                    v_leak=np.zeros(ens.n_neurons),
                    r=np.ones(ens.n_neurons),
                )
            else:
                nodes[label] = nir.LIF(
                    tau=np.full(ens.n_neurons, 0.02),
                    v_threshold=np.ones(ens.n_neurons),
                    v_leak=np.zeros(ens.n_neurons),
                    r=np.ones(ens.n_neurons),
                )

        # Map Connections to NIR Linear/Affine nodes and edges
        for i, conn in enumerate(model.all_connections):
            pre = conn.pre_obj
            post = conn.post_obj
            pre_ens = pre if isinstance(pre, nengo.Ensemble) else getattr(pre, "ensemble", None)
            post_ens = post if isinstance(post, nengo.Ensemble) else getattr(post, "ensemble", None)

            if pre_ens and post_ens:
                pre_label = (
                    pre_ens.label or f"pop_{list(model.all_ensembles).index(pre_ens)}"
                ).replace(" ", "_")
                post_label = (
                    post_ens.label or f"pop_{list(model.all_ensembles).index(post_ens)}"
                ).replace(" ", "_")

                weight = 1.0
                if hasattr(conn, "transform"):
                    t = conn.transform
                    if hasattr(t, "init"):
                        w = t.init
                        if isinstance(w, int | float | np.number):
                            weight = float(w)
                        elif hasattr(w, "flat"):
                            weight = float(w.flat[0]) if w.size > 1 else float(w)
                    elif isinstance(t, int | float | np.number):
                        weight = float(t)
                    elif isinstance(t, np.ndarray):
                        if t.ndim == 0:
                            weight = float(t)
                        elif t.size == 1:
                            weight = float(t.flat[0])

                conn_label = f"conn_{pre_label}_{post_label}_{i}"
                weight_matrix = (
                    np.full((post_ens.n_neurons, pre_ens.n_neurons), weight)
                    if isinstance(weight, float)
                    else weight
                )
                nodes[conn_label] = nir.Linear(weight=weight_matrix)

                edges.append((pre_label, conn_label))
                edges.append((conn_label, post_label))

        return nir.NIRGraph(nodes=nodes, edges=edges)

    def from_nir(self, graph: nir.NIRGraph, dt: float = 1e-4, **kwargs: Any) -> str:
        """Convert an NIR graph to Nengo network definition (Python code).

        Oracle: paper/03_rnn/nir_to_nengo.py's nir_to_nengo() function — read
        it in full before changing this method. That script builds a *live*
        nengo.Network directly (walking graph.nodes once to build a
        name->live-object map plus a per-ensemble synapse `filters` dict,
        then walking graph.edges once to wire every connection, applying
        `filters.get(post)` generically). This method reproduces the exact
        same two-pass, per-node-type design as Python *source text* instead
        of live objects — recurrent connections (e.g. cnl.RSynaptic's
        self-loop, which the NIR graph represents as a flat nir.CubaLIF
        plus a same-population nir.Linear edge back onto itself) fall out of
        the generic edge-replay loop for free, with no special-casing for
        "is this recurrent" anywhere, exactly like the oracle.

        Note: previously this method only handled nir.LIF|nir.CubaLIF (with
        a formula that crashes on real nir.CubaLIF nodes — CubaLIF has no
        `.tau` attribute, only tau_syn/tau_mem) and had no nir.Input/
        nir.Output handling at all, so no graph containing a real recurrent
        population (cnl.RSynaptic/cnl.Synaptic) could ever produce working
        code. Unsupported node types now raise loudly instead of silently
        producing incomplete code — the previous silent gap is exactly how
        this went undetected.
        """
        var = {name: _slug(name) for name in graph.nodes}
        lines = [
            '"""Nengo network — auto-generated from NIR graph."""',
            "",
            "import nengo",
            "import numpy as np",
            "",
            "model = nengo.Network(label='from_nir')",
            "with model:",
        ]
        # post-node var name -> Lowpass-synapse code snippet, populated by
        # CubaLIF nodes (oracle: nir_to_nengo.py's `filters[ens.neurons] = ...`).
        filters: dict[str, str] = {}

        for name, node in graph.nodes.items():
            v = var[name]
            if isinstance(node, nir.Input):
                size = int(np.prod(node.input_type["input"]))
                lines.append(f"    {v} = nengo.Node(None, size_in={size}, label={name!r})")
            elif isinstance(node, nir.Output):
                size = int(np.prod(node.output_type["output"]))
                lines.append(f"    {v} = nengo.Node(None, size_in={size}, label={name!r})")
            elif isinstance(node, nir.LIF):
                # Oracle: nir_to_nengo.py's `elif isinstance(obj, nir.LIF):`
                # branch — requires r==1 and v_leak==0 (no NIR-side scaling
                # or leak support in this mapping).
                r = np.asarray(node.r, dtype=float)
                v_leak = np.asarray(node.v_leak, dtype=float)
                if not np.all(r == 1):
                    raise ValueError(
                        f"Nengo LIF conversion requires r==1 for all neurons (node {name!r})"
                    )
                if not np.all(v_leak == 0):
                    raise ValueError(
                        f"Nengo LIF conversion requires v_leak==0 for all neurons (node {name!r})"
                    )
                tau = np.asarray(node.tau, dtype=float).flatten()
                v_threshold = np.asarray(node.v_threshold, dtype=float).flatten()
                n = tau.shape[0]
                lines.append(
                    f"    {v} = nengo.Ensemble(n_neurons={n}, dimensions=1, label={name!r}, "
                    f"neuron_type=nengo.LIF(tau_rc={float(tau[0]):.8f}, tau_ref=0, "
                    "initial_state={'voltage': nengo.dists.Choice([0])}), "
                    f"gain=np.ones({n}) / np.array({v_threshold.tolist()}), "
                    f"bias=np.zeros({n})).neurons"
                )
            elif isinstance(node, nir.CubaLIF):
                # Oracle: nir_to_nengo.py's `elif isinstance(obj, nir.CubaLIF):`
                # branch (lines 49-80). tau_syn is discretization-corrected
                # via tau_syn_corrected = -dt / log(1 - dt/tau_syn): NIR's
                # tau_syn is a discrete-step decay constant but Nengo's
                # Lowpass synapse wants a continuous time constant — skipping
                # this conversion desyncs the synaptic filter from the
                # intended discrete dynamics. gain = w_in * r / v_threshold
                # (w_in is a per-neuron scale the oracle does NOT assert
                # uniform, unlike r/v_leak/v_threshold/tau_syn/tau_mem, so it
                # must stay a per-neuron array, not a scalar).
                r_arr = np.asarray(node.r, dtype=float)
                v_leak = np.asarray(node.v_leak, dtype=float)
                v_threshold = np.asarray(node.v_threshold, dtype=float)
                tau_syn = np.asarray(node.tau_syn, dtype=float)
                tau_mem = np.asarray(node.tau_mem, dtype=float)
                w_in = np.asarray(node.w_in, dtype=float)
                if not np.all(r_arr == r_arr.flat[0]):
                    raise ValueError(f"Nengo CubaLIF conversion requires uniform r (node {name!r})")
                if not np.all(v_leak == 0):
                    raise ValueError(f"Nengo CubaLIF conversion requires v_leak==0 (node {name!r})")
                if not np.all(v_threshold == v_threshold.flat[0]):
                    raise ValueError(
                        f"Nengo CubaLIF conversion requires uniform v_threshold (node {name!r})"
                    )
                if not np.all(tau_syn == tau_syn.flat[0]):
                    raise ValueError(
                        f"Nengo CubaLIF conversion requires uniform tau_syn (node {name!r})"
                    )
                if not np.all(tau_mem == tau_mem.flat[0]):
                    raise ValueError(
                        f"Nengo CubaLIF conversion requires uniform tau_mem (node {name!r})"
                    )
                r_val = float(r_arr.flat[0])
                v_thr = float(v_threshold.flat[0])
                tau_mem_val = float(tau_mem.flat[0])
                tau_syn_val = float(tau_syn.flat[0])
                tau_syn_corrected = -dt / math.log(1 - dt / tau_syn_val)
                n = tau_mem.flatten().shape[0]
                lines.append(
                    f"    {v} = nengo.Ensemble(n_neurons={n}, dimensions=1, label={name!r}, "
                    f"neuron_type=nengo.LIF(tau_ref=0, tau_rc={tau_mem_val:.8f}, "
                    f"amplitude={dt:.8f}, "
                    "initial_state={'voltage': nengo.dists.Choice([0])}), "
                    f"gain=np.array({w_in.tolist()}) * {r_val:.8f} * np.ones({n}) / {v_thr:.8f}, "
                    f"bias=np.zeros({n})).neurons"
                )
                filters[v] = f"nengo.synapses.Lowpass({tau_syn_corrected:.10f})"
            elif isinstance(node, nir.Linear):
                # Oracle: nir_to_nengo.py's `elif isinstance(obj, nir.Linear):`
                # branch — weights are emitted as a Node computing weight @ x,
                # NOT a Connection(transform=...); the generic edge-replay
                # loop below depends on every node (weight nodes included)
                # being addressable as a plain pre/post endpoint the same
                # way, matching the oracle's pre_map/post_map design. Also
                # covers cnl.RSynaptic's internal recurrent weight node
                # (same NIR type as a feedforward Linear — no special-casing
                # needed for the recurrent case).
                w = np.asarray(node.weight, dtype=float)
                out_f, in_f = w.shape
                lines.append(
                    f"    {v} = nengo.Node(lambda t, x, _w=np.array({w.tolist()}): _w @ x, "
                    f"size_in={in_f}, size_out={out_f}, label={name!r})"
                )
            elif isinstance(node, nir.Affine):
                w = np.asarray(node.weight, dtype=float)
                b = np.asarray(node.bias, dtype=float)
                out_f, in_f = w.shape
                lines.append(
                    f"    {v} = nengo.Node(lambda t, x, _w=np.array({w.tolist()}), "
                    f"_b=np.array({b.tolist()}): _w @ x + _b, "
                    f"size_in={in_f}, size_out={out_f}, label={name!r})"
                )
            else:
                raise ValueError(
                    "Unsupported NIR node type for Nengo conversion: "
                    f"{type(node).__name__} (node {name!r})"
                )

        lines.append("")
        for pre_name, post_name in graph.edges:
            pre_v, post_v = var[pre_name], var[post_name]
            synapse = filters.get(post_v, "None")
            lines.append(f"    nengo.Connection({pre_v}, {post_v}, synapse={synapse})")

        return "\n".join(lines)
