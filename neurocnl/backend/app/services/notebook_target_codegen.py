"""Per-target/framework notebook codegen for `backend.app.routers.notebook`.

Mechanical extraction of the twelve functions that turn a compiled
`nir.NIRGraph` into per-target Jupyter cell source: the four framework
generators (`_generate_snntorch_code`, `_generate_sc_neurocore_code`,
`_generate_akida_code`, `_generate_rockpool_code`), the IO-converter error
helpers (`_io_error_markdown`, `_safe_io_call`), the post-training Akida
export/bundle/visualizer cells (`_akida_exporter_code`, `_akida_bundle_code`,
`_weight_visualizer_code`, `_auto_weight_visualizer_cell`,
`_attribution_visualizer_code`), and the target dispatcher
(`_generate_arch_code`), kept last to match its original position relative to
the others. Bodies are copied verbatim — behavior, strings, and comments are
unchanged.

Several of these functions call small helpers that still live in
`backend.app.routers.notebook` (`_weight_key_check_lines`,
`_WEIGHTED_NODE_TYPES`, `_weights_artifact_name`, `_TARGET_CELLS`,
`_logger`). Those are imported locally, inside the functions that need them,
rather than at module scope: `notebook.py` imports `_generate_arch_code` and
`_auto_weight_visualizer_cell` from this module during its own import phase,
before any of its own functions are defined, so a module-level import back
into `notebook.py` here would create a circular-import failure.

`_scalar`, `_python_identifier`, and `_declared_endpoint_width` are imported
directly from `notebook_graph_analysis` (their real home — see that module's
own docstring) rather than via `notebook.py`'s compatibility re-export, since
that avoids the circular-import problem entirely for names that never lived
in `notebook.py`.
"""

from __future__ import annotations

import math
from collections.abc import Callable
from typing import Any

import nir
import numpy as np

from backend.app.schemas.notebook import PipelineConfigPayload
from backend.app.services.notebook_graph_analysis import (
    declared_endpoint_width as _declared_endpoint_width,
)
from backend.app.services.notebook_graph_analysis import (
    python_identifier as _python_identifier,
)
from backend.app.services.notebook_graph_analysis import scalar as _scalar
from neurocnl.converter._diagnostics import raise_unsupported_node
from neurocnl.converter.brian2_io import Brian2IO
from neurocnl.converter.lava_io import LavaIO
from neurocnl.converter.nengo_io import NengoIO
from neurocnl.converter.pynn_io import PyNNIO
from neurocnl.converter.sinabs_io import SinabsIO
from neurocnl.lif_semantics import resolve_dt
from neurocnl.runtime.cnl_nodes import BatchNorm1d as CnlBatchNorm1d
from neurocnl.runtime.cnl_nodes import Dropout as CnlDropout
from neurocnl.runtime.cnl_nodes import Leaky as CnlLeaky
from neurocnl.runtime.cnl_nodes import RLeaky as CnlRLeaky
from neurocnl.runtime.cnl_nodes import RSynaptic as CnlRSynaptic
from neurocnl.runtime.cnl_nodes import Synaptic as CnlSynaptic


def _generate_snntorch_code(
    graph: nir.NIRGraph,
    weights_filename: str = "weights.npz",
    spike_grad_expr: str | None = None,
    time_major_input: bool = False,
) -> tuple[str, dict[str, np.ndarray[Any, Any]]]:
    """Generate a Net(nn.Module) snnTorch cell from a NIR graph.

    Returns (code_str, weights_dict) — weights are NOT embedded inline;
    they go to `weights_filename` next to the notebook and are loaded via
    np.load.

    `spike_grad_expr`, when given (e.g. `"surrogate.fast_sigmoid(slope=5.0)"`,
    sourced from a pipeline DAG's `surrogateBackward` node — see
    `_build_v2_notebook`), is assigned once to a module-level `spike_grad`
    and passed into every spike-producing neuron constructor below. Without
    it, every constructor keeps its snnTorch-library default surrogate
    gradient exactly as before — this only changes output when a
    `surrogateBackward` node is actually present in the pipeline.

    `time_major_input`, set when the resolved dataset format is a `tonic_*`
    loader (see `_dag_node_code`'s `dataLoader` case), tells `forward()` the
    incoming batch is *already* `(T, B, ...)` — `tonic.collation.PadTensors(
    batch_first=False)` guarantees this. Without it, `forward()` falls back
    to guessing axis order from raw dim sizes, which silently scrambles the
    batch/time axes whenever the real timestep count happens to be <= the
    batch size (routine for SHD/N-TIDIGITS with a small `time_window`) —
    this produces a near-zero training loss and an eventual shape-mismatch
    crash instead of a clean error, since neither axis order is invalid on
    its own for the elementwise/last-dim ops in between.
    """
    from backend.app.routers.notebook import (
        _WEIGHTED_NODE_TYPES,
        _weight_key_check_lines,
    )

    dt = 1e-3  # timestep in seconds (matches simulator default)
    spike_grad_kwarg = ", spike_grad=spike_grad" if spike_grad_expr else ""

    weights: dict[str, np.ndarray[Any, Any]] = {}
    node_vars: dict[str, str] = {}
    # (var, neuron_kind) for hidden-state init lines in forward()
    spiking_vars: list[tuple[str, str]] = []
    # n_neurons for "rsynaptic" vars only — needed to pre-shape initial state
    # (see rsynaptic_n_neurons usage below for why).
    rsynaptic_n_neurons: dict[str, int] = {}
    # nir node name -> what its snnTorch module was constructed from, so the
    # NIR Exporter can invert it (see the nir.LIF branch below).
    neuron_export: dict[str, dict[str, object]] = {}

    init_lines: list[str] = []  # lines inside __init__ (8-space indent)

    for name, node in graph.nodes.items():
        var = _python_identifier(name)
        node_vars[name] = var

        if isinstance(node, nir.Input | nir.Output):
            pass  # no __init__ entry

        elif isinstance(node, nir.LIF):
            # Oracle: snntorch.import_nir._nir_to_snntorch_module's nir.LIF
            # branch hardcodes its own dt=1e-4 for this node type (distinct
            # from the module-wide `dt` above, which this branch does not
            # use), and computes beta = 1 - dt/tau (NOT exp(-dt/tau)),
            # reset_mechanism="zero", reset_delay=False. It also rescales the
            # firing threshold by w_scale = r*dt/tau whenever that ratio isn't
            # ~1 (hack_w_scale, defaults True in the oracle's signature),
            # because snnTorch's Leaky has no separate "r" (resistance) term
            # to apply to the input current the way NIR's LIF does. Skipping
            # any of this silently changes beta/threshold and desyncs spike
            # timing from the oracle-imported network.
            #
            # `dt` and `beta` are overridable via this node's `metadata`
            # dict (round-tripped through the CNL grammar's generic
            # `annotated with metadata <key> equal to <value>` clause — see
            # nir_cnl/parser.py and nir_cnl/renderer.py) for users who need
            # different timestep/decay behavior than the oracle default.
            # The default (no metadata present) stays exactly `dt=1e-4` with
            # `beta` derived from it, matching the oracle byte-for-byte — the
            # constant now lives in `lif_semantics.DEFAULT_LIF_DT_SECONDS` so
            # the simulators and this codegen cannot drift apart. Resolved
            # node-only on purpose: `compile_to_nir` already stamps a declared
            # network timestep onto every nir.LIF, so consulting the graph here
            # would be redundant, and keeping this branch's inputs unchanged is
            # what makes the codegen tests a regression guard.
            lif_dt, _ = resolve_dt(node)
            tau = _scalar(getattr(node, "tau", None), 0.02)
            r = _scalar(getattr(node, "r", None), 1.0)
            thr = (
                _scalar(getattr(node, "v_threshold", None), 1.0) or 1.0
            )  # ponytail: threshold=0 fires every step (mirrors nir.IF fix below)
            if "beta" in node.metadata:
                beta = float(node.metadata["beta"])
            else:
                beta = 1 - (lif_dt / tau) if tau > 0 else 0.95
            w_scale = r * lif_dt / tau if tau > 0 else 1.0
            if abs(w_scale - 1.0) > 1e-6:
                thr = thr / w_scale
            n = int(np.asarray(getattr(node, "tau", [1])).size)
            # Record what this population was actually built with, so the NIR
            # Exporter can write a graph whose tau/threshold reproduce exactly
            # these numbers. Without it the exported .nir carries the compiled
            # graph's zeros -- real weights, blank neurons -- and nothing
            # downstream can run it.
            neuron_export[name] = {
                "module": var,
                "dt": lif_dt,
                "input_scale": w_scale,
                "r": r,
                "v_leak": _scalar(getattr(node, "v_leak", None), 0.0),
                "n": n,
            }
            init_lines += [
                f"        # LIF population: {name!r}  ({n} neurons)",
                f"        self.{var} = snn.Leaky(beta={beta:.6f}, threshold={thr:.4f}, "
                f"reset_mechanism='zero', init_hidden=True, reset_delay=False{spike_grad_kwarg})",
            ]
            spiking_vars.append((var, "leaky"))

        elif isinstance(node, nir.CubaLIF):
            # ponytail: approximates CubaLIF with snn.Leaky (synaptic current
            # filtering is not modelled); pre-existing gap, unchanged by the
            # nir.LIF fix above.
            tau = _scalar(getattr(node, "tau", None), 0.02)
            beta = math.exp(-dt / tau) if tau > 0 else 0.95
            thr = _scalar(getattr(node, "v_threshold", None), 1.0)
            n = int(np.asarray(getattr(node, "tau", [1])).size)
            init_lines += [
                f"        # LIF population: {name!r}  ({n} neurons)",
                f"        self.{var} = snn.Leaky(beta={beta:.6f}, threshold={thr:.4f}, "
                f"init_hidden=True{spike_grad_kwarg})",
                f"        # ponytail: {name!r} approximates CubaLIF with snn.Leaky; "
                "synaptic current filtering is not modelled.",
            ]
            spiking_vars.append((var, "leaky"))

        elif isinstance(node, nir.IF):
            thr = (
                _scalar(getattr(node, "v_threshold", None), 1.0) or 1.0
            )  # ponytail: threshold=0 fires every step
            # beta=0.9 mirrors snntorch.import_nir's hardcoded IF->Leaky
            # mapping (_nir_to_snntorch_module); using the Leaky default
            # (beta=1) diverges from that reference and collapses accuracy
            # to chance level. Overridable via this node's `beta` metadata
            # key (same generic metadata mechanism as nir.LIF's `dt`/`beta`
            # above) for users who need different decay behavior; the
            # default (no metadata present) stays exactly 0.9, matching the
            # oracle byte-for-byte.
            #
            # reset_delay=False also mirrors the oracle's hardcoded mapping,
            # but is NOT similarly overridable: it's a bool, and
            # nir_cnl/renderer.py's `_is_supported_metadata_value` only
            # allows str|int|float metadata values, so a bool-typed
            # `reset_delay` metadata key would be silently dropped (emitted
            # as a `# metadata ... omitted` comment) rather than round-trip.
            # Exposing it would require a CNL grammar change, not just a
            # notebook.py read — intentionally left fixed here.
            if_beta = float(node.metadata.get("beta", 0.9))
            init_lines += [
                f"        # IF population: {name!r}",
                f"        self.{var} = snn.Leaky(beta={if_beta:.6f}, threshold={thr:.4f}, "
                f"init_hidden=True, reset_delay=False{spike_grad_kwarg})",
            ]
            spiking_vars.append((var, "leaky"))

        elif isinstance(node, nir.Linear | nir.Affine):
            w = np.asarray(node.weight)
            out_f, in_f = w.shape
            has_bias = isinstance(node, nir.Affine) and node.bias is not None
            weights[f"{var}_weight"] = w
            init_lines += [
                f"        # Linear layer: {name!r}  shape {w.shape}",
                # Constructed with PyTorch's default bias=True (not
                # bias=False) so the weight tensor draws the same random
                # numbers, in the same order, as the reference
                # implementation (paper/03_rnn/Braille_training_snntorch.ipynb's
                # model_build, which does the same construct-then-discard),
                # under an identical seed — even when the bias is discarded
                # immediately below.
                f"        self.{var} = nn.Linear({in_f}, {out_f})",
                (
                    f"        self.{var}.weight.data = torch.from_numpy(_w['{var}_weight'].copy())"
                    if not np.all(w == 0)
                    else "        # weight is all-zeros in NIR graph; keeping PyTorch default init"
                ),
            ]
            if has_bias:
                b = np.asarray(node.bias)
                weights[f"{var}_bias"] = b
                init_lines.append(
                    f"        self.{var}.bias.data = torch.from_numpy(_w['{var}_bias'].copy())"
                    if not np.all(b == 0)
                    else "        # bias is all-zeros in NIR graph; keeping PyTorch default init"
                )
            else:
                init_lines.append(f"        self.{var}.bias = None")

        elif isinstance(node, nir.Conv2d):
            w = np.asarray(node.weight)
            out_ch, in_ch, k_h, k_w = w.shape
            has_bias = hasattr(node, "bias") and node.bias is not None
            stride = tuple(
                int(s) for s in np.asarray(getattr(node, "stride", (1, 1))).flat
            )
            padding = tuple(
                int(p) for p in np.asarray(getattr(node, "padding", (0, 0))).flat
            )
            weights[f"{var}_weight"] = w
            init_lines += [
                f"        # Conv2d layer: {name!r}  shape {w.shape}",
                # See the Linear/Affine branch above: construct with default
                # bias=True (not bias=False) so the weight tensor's random
                # draws land in the same position of the RNG stream as a
                # construct-then-discard reference implementation.
                f"        self.{var} = nn.Conv2d({in_ch}, {out_ch}, ({k_h}, {k_w}), stride={stride}, padding={padding})",
                (
                    f"        self.{var}.weight.data = torch.from_numpy(_w['{var}_weight'].copy())"
                    if not np.all(w == 0)
                    else "        # weight is all-zeros in NIR graph; keeping PyTorch default init"
                ),
            ]
            if has_bias:
                b = np.asarray(node.bias)
                weights[f"{var}_bias"] = b
                init_lines.append(
                    f"        self.{var}.bias.data = torch.from_numpy(_w['{var}_bias'].copy())"
                    if not np.all(b == 0)
                    else "        # bias is all-zeros in NIR graph; keeping PyTorch default init"
                )
            else:
                init_lines.append(f"        self.{var}.bias = None")

        elif isinstance(node, nir.Flatten):
            # clamp start_dim to ≥1 so batch dim is never flattened during training
            start_dim = max(1, int(getattr(node, "start_dim", 1)))
            end_dim = int(getattr(node, "end_dim", -1))
            init_lines += [
                f"        # Flatten layer: {name!r}",
                f"        self.{var} = nn.Flatten(start_dim={start_dim}, end_dim={end_dim})",
            ]

        elif isinstance(node, nir.AvgPool2d):
            pool_size = None
            for attr in ("kernel_size", "pool_size", "sumpool_size"):
                candidate = getattr(node, attr, None)
                if candidate is not None:
                    pool_size = candidate
                    break
            if pool_size is None:
                init_lines += [
                    f"        # AvgPool2d: {name!r} — missing kernel_size metadata, skipped",
                ]
            else:
                kernel_size = tuple(int(k) for k in np.asarray(pool_size).flat)
                stride_attr = getattr(node, "stride", None)
                stride = (
                    tuple(int(s) for s in np.asarray(stride_attr).flat)
                    if stride_attr is not None
                    else kernel_size
                )
                init_lines += [
                    f"        # AvgPool2d layer: {name!r}",
                    f"        self.{var} = nn.AvgPool2d(kernel_size={kernel_size}, stride={stride})",
                ]

        elif isinstance(node, nir.SumPool2d):
            kernel_size = tuple(int(k) for k in np.asarray(node.kernel_size).flat)
            stride_attr = getattr(node, "stride", None)
            stride = (
                tuple(int(s) for s in np.asarray(stride_attr).flat)
                if stride_attr is not None
                else kernel_size
            )
            init_lines += [
                # divisor_override=1 mirrors snntorch.import_nir's SumPool2d
                # mapping: AvgPool2d without it divides by the kernel area,
                # making every value past this layer kernel_area-times too
                # small once compounded through the rest of the network.
                f"        # SumPool2d: {name!r} — true sum via divisor_override=1",
                f"        self.{var} = nn.AvgPool2d(kernel_size={kernel_size}, stride={stride}, "
                "divisor_override=1)",
            ]

        elif isinstance(node, nir.Delay):
            delay = _scalar(getattr(node, "delay", None), 0.0)
            init_lines += [
                f"        # Delay node: {name!r}  delay={delay}s — passthrough in scaffold",
                "        # ponytail: snnTorch scaffold treats Delay as a passthrough.",
            ]

        elif isinstance(node, CnlRSynaptic):
            n = node.n_neurons
            init_lines += [
                f"        # RSynaptic population: {name!r}  ({n} neurons, alpha={node.alpha:.4f}, beta={node.beta:.4f})",
                # reset_delay=False mirrors (a) the Braille reference
                # notebooks' explicit override (Braille_training_snntorch.ipynb,
                # snntorch_apply_subtract.ipynb both hardcode
                # reset_delay = False locally, not from the JSON params) and
                # (b) snntorch.import_nir._nir_to_snntorch_module's
                # nir.NIRGraph/CubaLIF-in-subgraph branch, which also
                # hardcodes reset_delay=False. snn.RSynaptic defaults
                # reset_delay=True; leaving it unset diverges from the
                # weights' training-time convention and desyncs reset timing
                # from spike timing.
                #
                # Unlike nir.LIF's `dt`/`beta` and nir.IF's `beta` (see
                # those branches above), reset_delay is NOT exposed as a
                # metadata override: it's bool-typed, and
                # nir_cnl/renderer.py's `_is_supported_metadata_value` only
                # allows str|int|float metadata values, so a bool metadata
                # key would be silently dropped rather than round-trip
                # through CNL text. This is intentional — a real override
                # would need a separate CNL grammar change, not just a
                # notebook.py read.
                f"        self.{var} = snn.RSynaptic(alpha={node.alpha:.6f}, beta={node.beta:.6f}, "
                f"linear_features={n}, threshold={node.threshold:.4f}, "
                f"reset_mechanism='{node.reset_mechanism}', reset_delay=False{spike_grad_kwarg})",
            ]
            if not node.use_bias:
                init_lines.append(f"        self.{var}.recurrent.bias = None")
            spiking_vars.append((var, "rsynaptic"))
            rsynaptic_n_neurons[var] = n

        elif isinstance(node, CnlSynaptic):
            n = node.n_neurons
            init_lines += [
                f"        # Synaptic population: {name!r}  ({n} neurons, alpha={node.alpha:.4f}, beta={node.beta:.4f})",
                # reset_delay=False — same rationale as CnlRSynaptic above,
                # including why it's not exposed as a metadata override
                # (bool-typed metadata is blocked by
                # nir_cnl/renderer.py's `_is_supported_metadata_value`).
                f"        self.{var} = snn.Synaptic(alpha={node.alpha:.6f}, beta={node.beta:.6f}, "
                f"threshold={node.threshold:.4f}, reset_mechanism='{node.reset_mechanism}', "
                f"reset_delay=False{spike_grad_kwarg})",
            ]
            spiking_vars.append((var, "synaptic"))

        elif isinstance(node, CnlRLeaky):
            n = node.n_neurons
            init_lines += [
                f"        # RLeaky population: {name!r}  ({n} neurons, beta={node.beta:.4f})",
                f"        self.{var} = snn.RLeaky(beta={node.beta:.6f}, linear_features={n}, "
                f"threshold={node.threshold:.4f}, reset_mechanism='{node.reset_mechanism}'"
                f"{spike_grad_kwarg})",
            ]
            spiking_vars.append((var, "rleaky"))

        elif isinstance(node, CnlLeaky):
            n = node.n_neurons
            init_lines += [
                f"        # Leaky (explicit-beta) population: {name!r}  ({n} neurons, beta={node.beta:.4f})",
                f"        self.{var} = snn.Leaky(beta={node.beta:.6f}, threshold={node.threshold:.4f}, "
                f"reset_mechanism='{node.reset_mechanism}', init_hidden=False{spike_grad_kwarg})",
            ]
            spiking_vars.append((var, "leaky_explicit"))

        elif isinstance(node, CnlBatchNorm1d):
            init_lines += [
                f"        # BatchNorm1d: {name!r}  ({node.num_features} features)",
                f"        self.{var} = nn.BatchNorm1d({node.num_features})",
            ]
            # stateless — no spiking_vars entry

        elif isinstance(node, CnlDropout):
            init_lines += [
                f"        # Dropout: {name!r}  (p={node.p})",
                f"        self.{var} = nn.Dropout(p={node.p})",
            ]
            # stateless — no spiking_vars entry

        else:
            init_lines += [
                f"        # Unsupported NIR node: {name!r} ({type(node).__name__}) — skipped",
            ]

    # Hidden-state init lines (before time loop in forward, 8-space indent)
    mem_init_lines: list[str] = []
    for var, kind in spiking_vars:
        if kind == "rsynaptic":
            # NOT self.{var}.init_rsynaptic() here: it returns an empty
            # (0,)-shaped placeholder for spk/syn/mem. snn.RSynaptic.forward's
            # reset_delay=False branch (which we hardcode above) computes
            # `spk / self.graded_spikes_factor - self.reset` using the raw
            # `spk` *parameter* passed in — not the auto-reshaped self.spk —
            # so an empty placeholder crashes with a shape-mismatch
            # RuntimeError on the very first call. Pre-shaping to
            # (batch, n_neurons) avoids this real snnTorch defect (confirmed
            # by reproducing it against both the reference notebooks' own
            # model_build() and the installed snntorch 0.9.1/1.0.0 sources —
            # not something introduced by this codegen). snn.Synaptic is
            # unaffected: its forward() computes spk internally rather than
            # taking it as a parameter, so init_synaptic()'s empty
            # placeholder is safe.
            n_rsyn = rsynaptic_n_neurons[var]
            mem_init_lines += [
                f"        spk_{var} = torch.zeros(x.shape[1], {n_rsyn}, dtype=x.dtype, device=x.device)",
                f"        syn_{var} = torch.zeros(x.shape[1], {n_rsyn}, dtype=x.dtype, device=x.device)",
                f"        mem_{var} = torch.zeros(x.shape[1], {n_rsyn}, dtype=x.dtype, device=x.device)",
            ]
        elif kind == "synaptic":
            mem_init_lines.append(
                f"        syn_{var}, mem_{var} = self.{var}.init_synaptic()"
            )
        elif kind == "rleaky":
            mem_init_lines.append(
                f"        spk_{var}, mem_{var} = self.{var}.init_rleaky()"
            )
        elif kind == "leaky_explicit":
            mem_init_lines.append(f"        mem_{var} = self.{var}.init_leaky()")
        else:  # Leaky with init_hidden=True manages state internally
            mem_init_lines.append(f"        self.{var}.init_leaky()")

    # Recurrent models (any node with explicit carry-over state) need a
    # temporal-sequence forward: iterate over the time dimension of the input.
    _recurrent_kinds = {"rsynaptic", "synaptic", "rleaky", "leaky_explicit"}
    has_recurrent = any(kind in _recurrent_kinds for _, kind in spiking_vars)
    # loop variable: xt (per-timestep slice) for recurrent nets, x for static-input
    loop_var = "xt" if has_recurrent else "x"

    # Determine which spiking vars feed directly into nir.Output — those are the
    # output layer(s). All others are hidden and tracked for regularisation.
    output_spiking_vars: set[str] = {
        node_vars[src]
        for src, dst in graph.edges
        if isinstance(graph.nodes.get(dst), nir.Output)
        and node_vars.get(src) is not None
    }

    # Forward loop body from edges (12-space indent)
    loop_lines: list[str] = []
    for src, dst in graph.edges:
        sv = node_vars.get(src)
        src_node = graph.nodes.get(src)
        if (
            sv is None
            or src_node is None
            or isinstance(src_node, nir.Input | nir.Output)
        ):
            continue
        # Determine whether this spiking node is the network output or a hidden layer.
        spike_target = "spk_rec" if sv in output_spiking_vars else "hid_rec"
        if isinstance(src_node, CnlRSynaptic):
            loop_lines += [
                f"            spk_{sv}, syn_{sv}, mem_{sv} = self.{sv}({loop_var}, spk_{sv}, syn_{sv}, mem_{sv})",
                f"            {spike_target}.append(spk_{sv})",
                f"            {loop_var} = spk_{sv}",
            ]
        elif isinstance(src_node, CnlSynaptic):
            loop_lines += [
                f"            spk_{sv}, syn_{sv}, mem_{sv} = self.{sv}({loop_var}, syn_{sv}, mem_{sv})",
                f"            {spike_target}.append(spk_{sv})",
                f"            {loop_var} = spk_{sv}",
            ]
        elif isinstance(src_node, CnlRLeaky):
            loop_lines += [
                f"            spk_{sv}, mem_{sv} = self.{sv}({loop_var}, spk_{sv}, mem_{sv})",
                f"            {spike_target}.append(spk_{sv})",
                f"            {loop_var} = spk_{sv}",
            ]
        elif isinstance(src_node, CnlLeaky):
            loop_lines += [
                f"            spk_{sv}, mem_{sv} = self.{sv}({loop_var}, mem_{sv})",
                f"            {spike_target}.append(spk_{sv})",
                f"            {loop_var} = spk_{sv}",
            ]
        elif isinstance(src_node, CnlBatchNorm1d | CnlDropout):
            loop_lines.append(f"            {loop_var} = self.{sv}({loop_var})")
        elif isinstance(src_node, nir.LIF | nir.CubaLIF | nir.IF):
            # nir.IF is constructed as snn.Leaky(beta=0.9, init_hidden=True), the
            # same single-return convention as LIF/CubaLIF. It must NOT be called
            # with an explicit membrane arg (spk, mem = self.n(x, mem)): the
            # init_hidden=True path never creates a local mem_{sv}, so that form
            # raised UnboundLocalError at forward time.
            if has_recurrent:
                # Inside a temporal loop, track spiking output the same way
                loop_lines += [
                    f"            spk_{sv} = self.{sv}({loop_var})",
                    f"            {spike_target}.append(spk_{sv})",
                    f"            {loop_var} = spk_{sv}",
                ]
            else:
                loop_lines += [
                    f"            spk_{sv} = self.{sv}({loop_var})",
                    *(
                        [
                            f"            mem_rec.append(getattr(self.{sv}, 'mem', spk_{sv}).clone())"
                        ]
                        if sv in output_spiking_vars
                        else []
                    ),
                    f"            {loop_var} = spk_{sv}",
                ]
        elif isinstance(
            src_node,
            nir.Linear
            | nir.Affine
            | nir.Conv2d
            | nir.Flatten
            | nir.AvgPool2d
            | nir.SumPool2d,
        ):
            loop_lines.append(f"            {loop_var} = self.{sv}({loop_var})")
        elif isinstance(src_node, nir.Delay):
            loop_lines.append(f"            # {src!r} Delay — passthrough")

    # Per-layer spike rates: every spiking node's spk_{var} is reassigned
    # each timestep above but never captured beyond the final layer's
    # output. Accumulate a running per-node mean here so every layer's rate
    # (not just the network's final output) reaches _nmtk_emit — see
    # _rate_acc_init below and its finalisation in both forward() variants.
    for _rate_var, _rate_kind in spiking_vars:
        loop_lines.append(
            f"            _rate_acc['{_rate_var}'] += float(spk_{_rate_var}.float().mean().item())"
        )
    _rate_acc_init = (
        "        _rate_acc = {"
        + ", ".join(f"'{v}': 0.0" for v, _ in spiking_vars)
        + "}"
    )
    _rate_acc_finalize = (
        "        self._layer_rates = {k: (v / (t + 1)) for k, v in _rate_acc.items()}"
    )

    # Real per-neuron activity for one eval sample (batch index 0 of whatever
    # batch is currently forwarded), gated by self._capture_activity so this
    # never runs — and never allocates — during training. Feeds the Results
    # step's Network Playback Grid/Raster views (previously always empty:
    # nothing ever produced activity_npy_b64 for them to fetch).
    for _act_var, _act_kind in spiking_vars:
        loop_lines.append(
            f"            if self._capture_activity: "
            f"_activity_acc['{_act_var}'].append("
            f"spk_{_act_var}[0].detach().flatten().cpu().numpy())"
        )
    _activity_acc_init = (
        "        _activity_acc = {"
        + ", ".join(f"'{v}': []" for v, _ in spiking_vars)
        + "}"
    )
    _activity_finalize = [
        "        if self._capture_activity:",
        "            self._layer_activity = "
        "{k: np.stack(v, axis=0) for k, v in _activity_acc.items() if v}",
    ]

    # Assemble the complete cell source
    lines = [
        '"""snnTorch network — auto-generated from NIR graph."""',
        "",
        "import torch",
        "import torch.nn as nn",
        "import snntorch as snn",
        "import numpy as np",
        "",
    ]
    if spike_grad_expr:
        lines += [
            "from snntorch import surrogate",
            f"spike_grad = {spike_grad_expr}",
            "",
        ]
    lines += [
        f"_w = np.load('{weights_filename}')  # weights file saved alongside this notebook",
    ]
    lines += _weight_key_check_lines(weights, weights_filename)
    lines += [
        "",
        "class Net(nn.Module):",
        "    def __init__(self):",
        "        super().__init__()",
    ]
    lines.extend(init_lines)
    lines.append("        self._capture_activity = False")
    if has_recurrent:
        # Temporal-sequence forward: iterate over the time dimension of the input.
        # Handles any shape with time as dim 1 from a DataLoader: (B,T,...) → (T,B,...).
        # A tonic_* loader already delivers (T,B,...) (PadTensors(batch_first=False)),
        # so swapping there would scramble the axes instead of fixing them.
        lines += [
            "",
            "    def forward(self, x):",
        ]
        if time_major_input:
            lines += [
                "        # x already (T,B,...) — tonic's PadTensors(batch_first=False) guarantees this, no swap needed",
            ]
        else:
            lines.append("        x = x.swapaxes(0, 1)  # (B,T,...) → (T,B,...)")
        lines.append("        # initialise explicit hidden states")
        lines.extend(mem_init_lines)
        lines += [
            "        spk_rec, hid_rec = [], []",
            _rate_acc_init,
            _activity_acc_init,
            "        for t in range(x.shape[0]):",
            "            xt = x[t]",
            # tonic ToFrame can leave a singleton channel axis (e.g. SHD
            # (T,B,1,700)); flatten before Linear/RSynaptic expect (B,F).
            "            if xt.dim() > 2:",
            "                xt = xt.flatten(start_dim=1)",
        ]
        lines.extend(loop_lines)
        lines += [
            "        _hid = torch.stack(hid_rec, dim=0) if hid_rec else torch.zeros_like(spk_rec[0]).unsqueeze(0)",
            _rate_acc_finalize,
            *_activity_finalize,
            "        return torch.stack(spk_rec, dim=0), _hid  # (T,B,out), (T,B,hid)",
        ]
    else:
        lines += [
            "",
            "    def forward(self, x):",
            "        # initialise hidden states",
        ]
        lines.extend(mem_init_lines)
        if time_major_input:
            lines += [
                "        # x already (T,B,...) time-first from tonic (PadTensors(batch_first=False))",
                "        # Preserve image axes for Conv2d; only static feature batches need a time axis.",
                "        if x.dim() == 2:",
                "            x = x.unsqueeze(0).expand(globals().get('num_steps', 1), -1, -1)",
                "        _x_seq = x",
            ]
        else:
            lines += [
                "        # x: (T,B,C,H,W) time-first from tonic, or (B,C,H,W) for a single frame",
                "        if x.dim() == 4:",
                "            x = x.unsqueeze(0)  # (B,C,H,W) → (1,B,C,H,W)",
                "        elif x.dim() == 3 and x.shape[0] <= x.shape[1]:",
                "            x = x.swapaxes(0, 1)  # (B,T,N) → (T,B,N) synthetic spike batches",
                "        elif x.dim() == 2:",
                "            x = x.unsqueeze(0).expand(globals().get('num_steps', 1), -1, -1)  # (B,F) static features → (T,B,F), repeated every step (rate coding)",
                "        _x_seq = x",
            ]
        # Backstop for the widths the backend could not check statically (tonic
        # datasets, client-scope paths, unreadable files). Without it the only
        # symptom of a dataset/model width mismatch is a torch matmul error from
        # inside the first nn.Linear, naming neither the dataset nor the Input
        # node — nir.Input emits no code, and the neuron layers are elementwise.
        input_ports = [
            n for n, node in graph.nodes.items() if isinstance(node, nir.Input)
        ]
        declared_input_width = (
            _declared_endpoint_width(graph.nodes[input_ports[0]])
            if len(input_ports) == 1
            else None
        )
        if declared_input_width:
            port_name = input_ports[0]
            lines += [
                "        _input_feature_width = int(np.prod(_x_seq.shape[2:])) if _x_seq.dim() > 2 else _x_seq.shape[-1]",
                f"        if _input_feature_width != {declared_input_width}:",
                "            raise RuntimeError(",
                '                f"This dataset provides {_input_feature_width} features per '
                'sample, but the "',
                f"                \"network's input port '{port_name}' declares "
                f'{declared_input_width}. Set the Input "',
                "                \"node's Size to match your dataset and resize the layers "
                'after it, then "',
                '                "regenerate the notebook."',
                "            )",
            ]
        lines += [
            "        spk_rec = []",
            "        mem_rec = []",
            _rate_acc_init,
            _activity_acc_init,
            "        for t in range(_x_seq.shape[0]):",
            "            x = _x_seq[t]",
        ]
        lines.extend(loop_lines)
        lines += [
            "            spk_rec.append(x)",
            "        mem_out = torch.stack(mem_rec, dim=0) if mem_rec else x",
            _rate_acc_finalize,
            *_activity_finalize,
            "        return torch.stack(spk_rec, dim=0), mem_out  # (T, batch, out), membrane trace or last activation",
        ]
    lines += [
        "",
        "",
        "_nmtk_nir_module_names = "
        + repr(
            {
                name: node_vars[name]
                for name, node in graph.nodes.items()
                if isinstance(node, _WEIGHTED_NODE_TYPES)
            }
        ),
        "_nmtk_nir_neuron_params = " + repr(neuron_export),
        "net = Net().float()  # ponytail: npz weights load as float64; cast to match DataLoader float32 input",
        "print(f'Net: {sum(p.numel() for p in net.parameters())} parameters')",
    ]

    return "\n".join(lines), weights


def _generate_sc_neurocore_code(
    graph: nir.NIRGraph,
    weights_filename: str = "weights.npz",
) -> tuple[str, dict[str, np.ndarray[Any, Any]]]:
    """Generate SC-NeuroCore simulation code from a NIR graph.

    Mirrors the conversion logic in neurocnl.runtime.sc_neurocore_simulator:
    - nir.LIF / nir.CubaLIF → sc_neurocore.network.Population(StochasticLIFNeuron, ...)
    - nir.Linear / nir.Affine → weight matrix loaded from `weights_filename`
    """
    from backend.app.routers.notebook import _weight_key_check_lines

    weights: dict[str, np.ndarray[Any, Any]] = {}
    lines = [
        '"""SC-NeuroCore simulation — auto-generated from NIR graph."""',
        "",
        "import sc_neurocore",
        "import sc_neurocore.network as scn",
        "from sc_neurocore.neurons import StochasticLIFNeuron",
        "import numpy as np",
        "",
        f"_w = np.load('{weights_filename}')  # weights saved alongside this notebook",
        "",
    ]

    pop_vars: dict[str, str] = {}
    weight_vars: dict[str, str] = {}

    for name, node in graph.nodes.items():
        # use _python_identifier so keys match snnTorch's weights.npz keys
        var = _python_identifier(name)

        if isinstance(node, nir.LIF | nir.CubaLIF):
            n = int(np.asarray(getattr(node, "tau", [1])).size)
            tau = _scalar(getattr(node, "tau", None), 0.02)
            r = _scalar(getattr(node, "r", None), 1.0)
            thr = _scalar(getattr(node, "v_threshold", None), 1.0)
            v_leak = _scalar(getattr(node, "v_leak", None), 0.0)
            pop_vars[name] = var
            lines += [
                f"# Population: {name!r}  ({n} neurons)",
                f"{var} = scn.Population(",
                "    StochasticLIFNeuron,",
                f"    n={n},",
                "    params=dict(",
                f"        tau_mem={tau:.6f},",
                f"        resistance={r:.6f},",
                f"        v_threshold={thr:.4f},",
                f"        v_rest={v_leak:.4f},",
                "        dt=1e-3,",
                "    ),",
                ")",
                "",
            ]

        elif isinstance(node, nir.Linear | nir.Affine):
            w = np.asarray(node.weight)
            weights[f"{var}_weight"] = w
            has_bias = isinstance(node, nir.Affine) and node.bias is not None
            if has_bias:
                weights[f"{var}_bias"] = np.asarray(node.bias)
            weight_vars[name] = var
            lines += [
                f"# Weight matrix: {name!r}  shape {w.shape}",
                f"{var}_weights = _w['{var}_weight'].copy()",
                "",
            ]

    lines += _weight_key_check_lines(weights, weights_filename)
    lines += [
        "# Spike monitors",
    ]
    for name, var in pop_vars.items():
        lines.append(f"{var}_mon = scn.SpikeMonitor()")
    lines += [
        "",
        "# ── Simulation loop ──────────────────────────────────────────",
        "T = 100  # timesteps",
        "for t in range(T):",
        "    # Replace with your actual input currents.",
    ]
    for name, var in pop_vars.items():
        lines.append(f"    currents_{var} = np.zeros({var}.n)  # TODO: real stimulus")
        lines.append(f"    spikes_{var} = {var}.step_all(currents_{var})")
        lines.append(f"    {var}_mon.record(spikes_{var}, t)")
    lines += [
        "",
        "# ── Results ──────────────────────────────────────────────────",
    ]
    for name, var in pop_vars.items():
        lines.append(f"t_arr_{var}, idx_arr_{var} = {var}_mon.raster_data()")
        lines.append(f"print(f'{name}: {{len(t_arr_{var})}} spikes')")
    lines.append("")
    return "\n".join(lines), weights


def _generate_akida_code(
    graph: nir.NIRGraph,
    weights_filename: str = "weights.npz",  # noqa: ARG001 - kept for signature parity
) -> tuple[str, dict[str, np.ndarray[Any, Any]]]:
    """Generate BrainChip Akida model code from a NIR graph.

    Delegates to `neurocnl.converter.akida_adapter.nir_to_akida` rather than
    building layers here. This function used to carry its own copy of that
    logic, which drifted until it emitted `akl.InputLayer` -- a symbol the SDK
    does not have -- so the cell raised `AttributeError` on every run. It also
    wrote a `weights.npz` it never loaded, and set no layer variables, so even
    a fixed version would have mapped an untrained network.

    Returns no weight payload: `nir_to_akida` carries the weights straight out
    of the graph the notebook already compiled.
    """
    # Fail at generation time, not in the user's kernel, for anything the
    # adapter cannot map.
    _AKIDA_SUPPORTED = (
        nir.Input,
        nir.Output,
        nir.Linear,
        nir.Affine,
        nir.Conv2d,
        nir.Flatten,
        nir.IF,
        nir.LIF,
        nir.CubaLIF,
    )
    lines = [
        '"""BrainChip Akida model — auto-generated from NIR graph."""',
        "",
        "# Layer structure derived from NIR graph:",
    ]
    for name, node in graph.nodes.items():
        if not isinstance(node, _AKIDA_SUPPORTED):
            raise_unsupported_node(node, "Akida", _AKIDA_SUPPORTED, node_name=name)
        if isinstance(node, nir.Linear | nir.Affine):
            w = np.asarray(node.weight)
            lines.append(f"#   FullyConnected  {name!r}  ({w.shape[0]} units)")
        elif isinstance(node, nir.Conv2d):
            w = np.asarray(node.weight)
            lines.append(f"#   Conv2D  {name!r}  ({w.shape[0]} filters)")
        elif isinstance(node, nir.IF | nir.LIF | nir.CubaLIF):
            n = int(
                np.asarray(getattr(node, "tau", getattr(node, "v_threshold", [1]))).size
            )
            lines.append(f"#   neuron  {name!r}  ({n} units)")

    lines += [
        "",
        "from neurocnl.converter.akida_adapter import AkidaConversionError, nir_to_akida",
        "",
        "# `graph` was compiled from the CNL spec in the Architecture cell above.",
        "# These are the weights that spec carries, NOT trained ones: `akida` has no",
        "# training adapter, so nothing on this notebook's path fits them. To put a",
        "# TRAINED model on the card, generate the snnTorch notebook instead and add",
        "# an Akida Exporter node to its Training canvas — that path reloads",
        "# best_model.pt, quantizes it, and writes the *.akida-bundle.zip the deploy",
        "# panel consumes.",
        "try:",
        "    model = nir_to_akida(graph, weight_bits=4)",
        "except AkidaConversionError as _exc:",
        "    raise RuntimeError(f'This model cannot be converted to Akida: {_exc}') from _exc",
        "model.summary()",
    ]
    return "\n".join(lines), {}


def _generate_rockpool_code(graph: nir.NIRGraph, embed_flatten: bool = False) -> str:
    """Generate Rockpool / Xylo model code from a NIR graph.

    RockpoolIO.from_nir() returns a live Sequential object, so this helper
    emits code that (a) describes the layer structure as comments derived
    from the compiled graph and (b) calls RockpoolIO().from_nir() at
    notebook-execution time so the user gets a real runnable model.

    RockpoolIO.from_nir() re-derives its own `graph` from `cnl_spec` at
    *notebook execution time* via a fresh compile_to_nir() call — that
    re-derived graph still has the original cnl.* nodes, since server-side
    flattening of the `graph` argument passed into this function only
    affects the static "Layer structure" comments below, not what actually
    runs when the user opens and executes the notebook. embed_flatten=True
    (set by _build_v2_notebook via cnl_flattened) makes the emitted code
    repeat the same flatten_cnl_ops() call at runtime so the notebook
    doesn't crash on a real cnl.RSynaptic/Synaptic/etc. node.
    """
    lines = [
        '"""Rockpool (SynSense Xylo) model — auto-generated from NIR graph."""',
        "",
        "# Layer structure derived from NIR graph:",
    ]
    for name, node in graph.nodes.items():
        if isinstance(node, nir.LIF | nir.CubaLIF):
            n = int(np.asarray(getattr(node, "tau", [1])).size)
            tau = _scalar(getattr(node, "tau", None), 0.02)
            lines.append(f"#   LIF  '{name}'  n={n}  tau={tau:.4f}s")
        elif isinstance(node, nir.Linear | nir.Affine):
            w = np.asarray(node.weight)
            lines.append(f"#   Linear  '{name}'  shape={w.shape}")

    lines += [
        "",
        "from neurocnl.compile import compile_to_nir",
        "from neurocnl.converter.rockpool_io import RockpoolIO",
        "",
        "# Re-compile from the CNL spec above and build the Rockpool Sequential.",
        "graph = compile_to_nir(cnl_spec)",
    ]
    if embed_flatten:
        lines += [
            "from neurocnl.runtime.cnl_flatten import flatten_cnl_ops",
            "graph, _flatten_diagnostics = flatten_cnl_ops(graph)",
            "for _msg in _flatten_diagnostics:",
            "    print('NOTE:', _msg)",
        ]
    lines += [
        "model = RockpoolIO().from_nir(graph)",
        "print(model)",
    ]
    return "\n".join(lines)


def _io_error_markdown(io_name: str, exc: Exception) -> str:
    """Render a caught converter exception as a notebook warning blockquote."""
    return (
        f"> **⚠️ {io_name} conversion failed — showing scaffold code below**\n>\n"
        f"> ```\n> {type(exc).__name__}: {exc}\n> ```\n>\n"
        f"> This usually means the compiled NIR graph contains a node type or "
        f"configuration `{io_name}` does not support."
    )


def _safe_io_call(
    fn: Callable[[], str], io_name: str, target: str
) -> tuple[str, str | None]:
    """Call an IO converter.

    Returns (code, error_markdown). error_markdown is None on success, or a
    markdown blockquote surfacing the failure when fn() raised — the
    scaffold fallback is still returned as `code` so the notebook always has
    a runnable code cell, but the failure is no longer swallowed into a
    server-only log line.
    """
    from backend.app.routers.notebook import _TARGET_CELLS, _logger

    try:
        return fn(), None
    except Exception as exc:
        _logger.warning("%s failed (%s); using scaffold", io_name, exc)
        cells = _TARGET_CELLS.get(target, [])
        scaffold = (
            cells[-1].get(
                "source", f"# {io_name} scaffold — check framework installation"
            )
            if cells
            else f"# {io_name} scaffold"
        )
        return scaffold, _io_error_markdown(io_name, exc)


def _akida_exporter_code(
    filename: str,
    weight_bits: int,
    max_batches: int,
    *,
    deploy_bundle: bool = True,
    eval_samples: int = 2000,
) -> str:
    """Emit the post-training Akida conversion, comparison, and deploy bundle.

    Runs after the epoch loop at module level, so everything here is 0-indent.

    The comparison is the point of the node: an Akida FullyConnected is a
    single-pass quantized unit while the trained network is a temporal LIF, so
    conversion is an approximation whose cost has to be measured rather than
    assumed. Both accuracies are computed with the same
    ``spk_out.sum(0).argmax(-1)`` rule the Eval canvas uses, so the two numbers
    are comparable.

    The classifier layer is built with its activation **off**, and scored with
    ``predict()`` on the raw potentials. Two independent reasons: the Akida host
    runs ``model.predict`` when it serves a sample, so a model saved the other
    way fails on arrival; and an argmax over a 4-bit clipped output vector ties
    constantly, which reads as a conversion failure when it is only a readout
    one.

    When `deploy_bundle` is set the cell also writes an ``*.akida-bundle.zip``
    next to the model. That suffix is not decoration -- it is what
    ``/notebook/artifacts/latest-akida-bundle`` globs and what the launcher's
    filename validator demands, so writing it is the whole difference between a
    converted model and one that can reach the card.
    """
    # Sits inside `with torch.no_grad():` -> `for ...:`, so the body is 8-space.
    batch_guard = (
        f"        if _ak_batches >= {max_batches}:\n            break\n"
        if max_batches > 0
        else ""
    )
    bundle_stem = filename.removesuffix(".fbz") or "model"
    bundle_code = (
        _akida_bundle_code(bundle_stem, filename, eval_samples) if deploy_bundle else ""
    )
    return (
        "import dataclasses\n"
        "from pathlib import Path\n"
        "import numpy as np\n"
        "import nir\n"
        "from neurocnl.converter.akida_adapter import (\n"
        "    AkidaConversionError, calibrate_act_steps, nir_to_akida, quantize_inputs)\n"
        "if not Path('best_model.pt').exists():\n"
        "    raise RuntimeError('best_model.pt is missing; finish training before exporting to Akida.')\n"
        "if 'test_loader' not in globals():\n"
        "    raise RuntimeError('Akida Exporter needs a test/eval Data Loader in this pipeline to measure accuracy.')\n"
        "net.load_state_dict(torch.load('best_model.pt', map_location='cpu', weights_only=True))\n"
        "for _nir_name, _module_name in _nmtk_nir_module_names.items():\n"
        "    _nir_node = graph.nodes[_nir_name]\n"
        "    _module = getattr(net, _module_name)\n"
        "    _updates = {'weight': _module.weight.detach().cpu().numpy().copy()}\n"
        "    if isinstance(_nir_node, nir.Affine) and _module.bias is not None:\n"
        "        _updates['bias'] = _module.bias.detach().cpu().numpy().copy()\n"
        "    try:\n"
        "        graph.nodes[_nir_name] = dataclasses.replace(_nir_node, **_updates)\n"
        "    except TypeError:\n"
        "        for _field_name, _value in _updates.items():\n"
        "            setattr(_nir_node, _field_name, _value)\n"
        "\n"
        "# Akida maps at most 256 neurons per neural processor; wider layers still\n"
        "# convert here but may not map to a physical card.\n"
        "for _name, _node in graph.nodes.items():\n"
        "    if isinstance(_node, (nir.Affine, nir.Linear)) and _node.weight.shape[0] > 256:\n"
        "        print(f'WARNING: layer {_name!r} has {_node.weight.shape[0]} units; '\n"
        "              'Akida allows 256 per neural processor.')\n"
        "\n"
        "_ak_x, _ak_y, _ak_batches = [], [], 0\n"
        "net.eval()\n"
        "_ak_correct_snn = 0\n"
        "with torch.no_grad():\n"
        "    for _data, _targets in test_loader:\n" + batch_guard
        # `forward()` always returns `(spikes, membrane)` -- both the default and
        # the recurrent branch do. Binding a single name here gave the cell an
        # `AttributeError: 'tuple' object has no attribute 'sum'`.
        + "        _spk, _ = net(_data)\n"
        "        _ak_correct_snn += (_spk.sum(0).argmax(-1) == _targets).sum().item()\n"
        "        _ak_x.append(_data.reshape(_data.shape[0], -1).cpu().numpy())\n"
        "        _ak_y.append(_targets.cpu().numpy())\n"
        "        _ak_batches += 1\n"
        "_ak_x = np.concatenate(_ak_x); _ak_y = np.concatenate(_ak_y)\n"
        "_ak_total = len(_ak_y)\n"
        "\n"
        f"_ak_inputs, _ak_scale = quantize_inputs(_ak_x, input_bits={weight_bits})\n"
        "try:\n"
        "    _ak_steps = calibrate_act_steps(\n"
        f"        graph, _ak_inputs[:256], weight_bits={weight_bits}, input_bits={weight_bits},\n"
        "        input_scale=_ak_scale)\n"
        "    _ak_model = nir_to_akida(\n"
        f"        graph, weight_bits={weight_bits}, input_bits={weight_bits},\n"
        "        input_scale=_ak_scale, act_steps=_ak_steps, activation_on_last=False)\n"
        "except AkidaConversionError as _exc:\n"
        "    raise RuntimeError(f'This model cannot be converted to Akida: {_exc}') from _exc\n"
        "# predict() (activation off on the classifier) returns raw potentials. The\n"
        "# Akida host serves samples the same way, so this is also the form that has\n"
        "# to be saved for hardware.\n"
        "_ak_out = np.asarray(_ak_model.predict(_ak_inputs)).reshape(_ak_total, -1)\n"
        "_ak_pred = _ak_out.argmax(-1)\n"
        "_ak_correct = int((_ak_pred == _ak_y).sum())\n"
        "\n"
        "_snn_acc = _ak_correct_snn / _ak_total if _ak_total else 0.0\n"
        "_akd_acc = _ak_correct / _ak_total if _ak_total else 0.0\n"
        "print(f'snnTorch accuracy : {_snn_acc:.2%}  ({_ak_correct_snn}/{_ak_total})')\n"
        "print(f'Akida accuracy    : {_akd_acc:.2%}  ({_ak_correct}/{_ak_total})')\n"
        "print(f'Conversion delta  : {(_akd_acc - _snn_acc) * 100:+.2f} pp')\n"
        "if _akd_acc < 0.2:\n"
        "    print('WARNING: Akida accuracy is near chance. The conversion scaling is wrong, '\n"
        "          'not the trained model - report this rather than retraining.')\n"
        f"_ak_model.save('{filename}')\n"
        f"print('Akida model saved to {filename}')\n"
        "_ak_model.summary()\n" + bundle_code
    )


def _akida_bundle_code(stem: str, model_filename: str, eval_samples: int) -> str:
    """Emit the deploy-bundle half of the Akida Exporter cell.

    Produces a ``schemaVersion: 2`` bundle -- manifest, the converted ``.fbz``,
    and the quantized evaluation set -- in the archive shape the Akida host
    already validates. Kept separate from the conversion code only because that
    cell is long enough; it is emitted immediately after it, at the same
    0-indent level.

    `eval_samples` caps what goes into the archive. The bundle is limited to
    32 MB by the host contract and its base64 to 45 MB by the launcher proxy,
    and a full test set of wide inputs will pass either.
    """
    return (
        "\n"
        "import hashlib, importlib.metadata, io, json, zipfile\n"
        f"_ak_keep = min(_ak_total, {eval_samples})\n"
        "_ak_bundle_inputs = _ak_inputs[:_ak_keep]\n"
        "_ak_bundle_labels = _ak_y[:_ak_keep].astype(np.int32)\n"
        "_ak_features = int(_ak_bundle_inputs.shape[-1])\n"
        "_ak_classes = int(_ak_out.shape[1])\n"
        "_ak_eval_io = io.BytesIO()\n"
        "np.savez_compressed(_ak_eval_io, inputs=_ak_bundle_inputs, labels=_ak_bundle_labels)\n"
        "_ak_payloads = {\n"
        f"    'model.fbz': Path('{model_filename}').read_bytes(),\n"
        "    'evaluation.npz': _ak_eval_io.getvalue(),\n"
        "}\n"
        "_ak_versions = {}\n"
        "for _ak_pkg in ('torch', 'numpy', 'nir', 'akida'):\n"
        "    try:\n"
        "        _ak_versions[_ak_pkg] = importlib.metadata.version(_ak_pkg)\n"
        "    except importlib.metadata.PackageNotFoundError:\n"
        "        pass\n"
        "_ak_manifest = {\n"
        "    'schemaVersion': 2,\n"
        "    'bundleType': 'nmtk.akida.model',\n"
        f"    'modelName': {stem[:128]!r},\n"
        "    'sourceFramework': 'snntorch',\n"
        "    'target': 'akida2',\n"
        "    'input': {'shape': [1, 1, 1, _ak_features], 'layout': 'NHWC', 'dtype': 'uint8'},\n"
        "    'preprocessing': {'scale': float(_ak_scale), 'offset': 0.0, 'evaluation_dtype': 'uint8'},\n"
        "    'labels': [str(_ak_i) for _ak_i in range(_ak_classes)],\n"
        "    'sourceMetrics': {'snntorch_accuracy': _snn_acc, 'akida_sim_accuracy': _akd_acc},\n"
        "    'dependencyVersions': _ak_versions,\n"
        "    'files': {_ak_name: hashlib.sha256(_ak_data).hexdigest()\n"
        "              for _ak_name, _ak_data in _ak_payloads.items()},\n"
        "}\n"
        f"_ak_bundle_path = Path({stem + '.akida-bundle.zip'!r})\n"
        "with zipfile.ZipFile(_ak_bundle_path, 'w', compression=zipfile.ZIP_DEFLATED) as _ak_zip:\n"
        "    _ak_zip.writestr('manifest.json', json.dumps(_ak_manifest, indent=2, sort_keys=True))\n"
        "    for _ak_name, _ak_data in _ak_payloads.items():\n"
        "        _ak_zip.writestr(_ak_name, _ak_data)\n"
        "_ak_bundle_sha = hashlib.sha256(_ak_bundle_path.read_bytes()).hexdigest()\n"
        "print(f'Deploy bundle    : {_ak_bundle_path} ({_ak_keep} samples, sha256 {_ak_bundle_sha[:12]}...)')\n"
        "print('To run this on the card: Results -> Deploy to Hardware -> Akida -> Use Latest Bundle.')"
    )


def _weight_visualizer_code(layer_attr: str, n_cols: int) -> str:
    """Emit a post-training cell that saves a receptive-field weight grid.

    One tile per neuron, arranged in a ``n_cols``-wide grid. Saves
    ``weight_map_<layer_attr>.png`` and prints a parseable
    ``weight_map: <filename>`` line that the app reads from the job log to
    locate the artifact.

    The tile side length is ``int(round(sqrt(in_features)))``, so any input
    dimension that is a perfect square produces a square tile. Callers are
    responsible for only calling this when that condition holds.
    """
    out_name = f"weight_map_{layer_attr}.png"
    data_name = f"weight_data_{layer_attr}.bin"
    return (
        "import math as _wv_math\n"
        "import matplotlib\n"
        "matplotlib.use('Agg')\n"
        "import matplotlib.pyplot as _wv_plt\n"
        "import numpy as _wv_np\n"
        "from pathlib import Path\n"
        f"if not Path('best_model.pt').exists():\n"
        f"    print('weight_visualizer: best_model.pt not found, skipping.')\n"
        f"else:\n"
        f"    net.load_state_dict(torch.load('best_model.pt', map_location='cpu', weights_only=True))\n"
        f"    net.eval()\n"
        f"    _wv_layer = getattr(net, '{layer_attr}', None)\n"
        f"    if _wv_layer is None or not hasattr(_wv_layer, 'weight'):\n"
        f"        print('weight_visualizer: layer {layer_attr} not found or has no weight, skipping.')\n"
        f"    else:\n"
        f"        _wv_W = _wv_layer.weight.detach().cpu().numpy()  # (out, in)\n"
        f"        _wv_n = len(_wv_W)\n"
        f"        _wv_cols = min({n_cols}, _wv_n)\n"
        f"        _wv_rows = _wv_math.ceil(_wv_n / _wv_cols)\n"
        f"        _wv_in = _wv_W.shape[1]\n"
        f"        _wv_side = int(round(_wv_math.sqrt(_wv_in)))\n"
        f"        _wv_fig, _wv_axes = _wv_plt.subplots(_wv_rows, _wv_cols, figsize=(_wv_cols * 1.4, _wv_rows * 1.4))\n"
        f"        _wv_axes_flat = _wv_axes.flat if hasattr(_wv_axes, 'flat') else [_wv_axes]\n"
        f"        _wv_vmax = float(_wv_np.abs(_wv_W).max()) or 1.0\n"
        f"        for _wv_i, _wv_ax in enumerate(_wv_axes_flat):\n"
        f"            if _wv_i < _wv_n:\n"
        f"                _wv_ax.imshow(_wv_W[_wv_i].reshape(_wv_side, _wv_side), cmap='RdBu_r', vmin=-_wv_vmax, vmax=_wv_vmax, interpolation='nearest')\n"
        f"            _wv_ax.axis('off')\n"
        f"        _wv_plt.suptitle(f'Layer {layer_attr} — {{_wv_n}} neurons × {{_wv_in}} inputs', y=1.01, fontsize=8)\n"
        f"        _wv_plt.tight_layout()\n"
        f"        _wv_fig.savefig({out_name!r}, dpi=150, bbox_inches='tight')\n"
        f"        _wv_plt.close(_wv_fig)\n"
        f"        import struct as _wv_struct\n"
        f"        _wv_data_name = {data_name!r}\n"
        f"        with open(_wv_data_name, 'wb') as _wv_f:\n"
        f"            _wv_f.write(_wv_struct.pack('<iiif', _wv_n, _wv_in, _wv_side, _wv_vmax))\n"
        f"            _wv_f.write(_wv_W.astype('<f4').tobytes())\n"
        f"        print(f'weight_data: {data_name}')\n"
        f"        print(f'weight_map: {out_name}')"
    )


def _auto_weight_visualizer_cell(graph: nir.NIRGraph) -> str | None:
    """Return a weight-map notebook cell source for the first suitable layer.

    Walks the NIR graph in node-insertion order and finds the first
    ``nir.Linear`` or ``nir.Affine`` whose ``in_features`` is a perfect
    square (i.e. ``sqrt(in_features)`` is an integer).  Returns the cell
    source string, or ``None`` when no such layer exists (tabular data,
    1-D non-square features, convolutional-only networks, etc.).

    The ``n_cols`` for the grid is chosen automatically:
    * ≤ 16 neurons  → 1 column per neuron (tiny network, show everything)
    * ≤ 256 neurons → 16 columns
    * > 256 neurons → 32 columns
    """
    import math as _math

    for name, node in graph.nodes.items():
        if not isinstance(node, nir.Linear | nir.Affine):
            continue
        w = np.asarray(node.weight)
        if w.ndim != 2:
            continue
        _, in_f = w.shape
        side = _math.isqrt(in_f)
        if side * side != in_f:
            # in_features is not a perfect square — skip
            continue
        out_f = w.shape[0]
        if out_f <= 16:
            n_cols = out_f
        elif out_f <= 256:
            n_cols = 16
        else:
            n_cols = 32
        layer_attr = _python_identifier(name)
        return _weight_visualizer_code(layer_attr, n_cols)
    return None


def _attribution_visualizer_code(
    sample_index: int, n_samples: int, sigma_scale: float
) -> str:
    """Emit a post-training SmoothGrad attribution cell.

    Runs ``n_samples`` noisy forward passes through the best checkpoint,
    averages the input-gradient magnitude, and saves a two-panel figure:
    the raw input on the left, the saliency heatmap on the right.

    Uses SmoothGrad instead of standard backprop because the generated
    ``forward()`` returns ``(spk_out, mem_out)`` and the surrogate backward
    (fast_sigmoid) is active only during training — re-running the graph
    in eval mode still produces a real gradient via standard autograd on
    the surrogate-smoothed path, but SmoothGrad is more robust to the
    non-smooth spike function and requires no changes to ``forward()``.

    The cell prints a ``attribution_map: <filename>`` line per sample so
    the app can locate the artifact in the job log.
    """
    out_name = f"attribution_sample_{sample_index}.png"
    return (
        "import matplotlib\n"
        "matplotlib.use('Agg')\n"
        "import matplotlib.pyplot as _av_plt\n"
        "import numpy as _av_np\n"
        "import math as _av_math\n"
        "from pathlib import Path\n"
        f"if not Path('best_model.pt').exists():\n"
        f"    print('attribution_visualizer: best_model.pt not found, skipping.')\n"
        f"elif 'test_loader' not in globals():\n"
        f"    print('attribution_visualizer: test_loader not found — add a Test Loader node to the Train canvas.')\n"
        f"else:\n"
        f"    net.load_state_dict(torch.load('best_model.pt', map_location='cpu', weights_only=True))\n"
        f"    net.eval()\n"
        f"    _av_all_x, _av_all_y = [], []\n"
        f"    for _av_xb, _av_yb in test_loader:\n"
        f"        _av_all_x.append(_av_xb); _av_all_y.append(_av_yb)\n"
        f"    _av_all_x = torch.cat(_av_all_x); _av_all_y = torch.cat(_av_all_y)\n"
        f"    _av_idx = min({sample_index}, len(_av_all_x) - 1)\n"
        f"    _av_x = _av_all_x[_av_idx : _av_idx + 1]  # (1, in_features)\n"
        f"    _av_y = int(_av_all_y[_av_idx].item())\n"
        f"    _av_sigma = max(float(_av_x.max() - _av_x.min()) * {sigma_scale}, 1e-6)\n"
        f"    _av_grads = []\n"
        f"    for _ in range({n_samples}):\n"
        f"        _av_noisy = (_av_x + torch.randn_like(_av_x) * _av_sigma).requires_grad_(True)\n"
        f"        _av_spk, _ = net(_av_noisy)  # (T, 1, out)\n"
        f"        _av_out = _av_spk.sum(0)  # (1, out)\n"
        f"        _av_pred_class = int(_av_out[0].argmax().item())\n"
        f"        _av_out[0, _av_pred_class].backward()\n"
        f"        _av_grads.append(_av_noisy.grad.abs().detach())\n"
        f"    _av_saliency = torch.stack(_av_grads).mean(0).squeeze().cpu().numpy()\n"
        f"    _av_in = _av_saliency.shape[0]\n"
        f"    _av_side = int(round(_av_math.sqrt(_av_in)))\n"
        f"    _av_fig, _av_axes = _av_plt.subplots(1, 2, figsize=(5, 2.5))\n"
        f"    _av_axes[0].imshow(_av_x.squeeze().cpu().numpy().reshape(_av_side, _av_side), cmap='gray', interpolation='nearest')\n"
        f"    _av_axes[0].set_title(f'Input (true label: {{_av_y}})', fontsize=8)\n"
        f"    _av_axes[1].imshow(_av_saliency.reshape(_av_side, _av_side), cmap='hot', interpolation='nearest')\n"
        f"    _av_axes[1].set_title(f'Attribution — predicted: {{_av_pred_class}}', fontsize=8)\n"
        f"    for _av_ax in _av_axes: _av_ax.axis('off')\n"
        f"    _av_plt.tight_layout()\n"
        f"    _av_fig.savefig({out_name!r}, dpi=150, bbox_inches='tight')\n"
        f"    _av_plt.close(_av_fig)\n"
        f"    print(f'attribution_map: {out_name}')"
    )


def _generate_arch_code(
    target: str,
    graph: nir.NIRGraph,
    cfg: PipelineConfigPayload,
    cnl_flattened: bool,
    spec: str = "",
    spike_grad_expr: str | None = None,
    time_major_input: bool = False,
) -> tuple[str, dict[str, np.ndarray[Any, Any]], str | None]:
    """Framework-specific build cell content, dispatched on `target`.

    Extracted from _build_v2_notebook so the side-effect-free
    /notebook/preview endpoint can reuse the exact same dispatch logic
    without duplicating it. `graph` must already be the post-flatten graph
    (see _flatten_and_classify) and `cnl_flattened` its accompanying flag.
    `spec` (the original CNL source, before flattening) feeds the per-
    target/per-spec weights filename (see `_weights_artifact_name`) so a
    regenerated notebook's code can never load a stale, structurally
    incompatible weights file left behind by an earlier architecture.

    `spike_grad_expr` is forwarded only to the `snntorch_sim` target — it is
    an snnTorch-specific neuron-constructor kwarg, not applicable to the
    other simulator/hardware backends below.

    `time_major_input` is likewise forwarded only to `snntorch_sim` — see
    `_generate_snntorch_code` for what it controls.

    Returns (arch_code, arch_weights, io_error) — io_error is None except
    for the 5 targets routed through _safe_io_call.
    """
    from backend.app.routers.notebook import _weights_artifact_name

    arch_weights: dict[str, np.ndarray[Any, Any]] = {}
    io_error: str | None = None
    weights_filename = _weights_artifact_name(spec, target)
    if target == "snntorch_sim":
        arch_code, arch_weights = _generate_snntorch_code(
            graph,
            weights_filename,
            spike_grad_expr=spike_grad_expr,
            time_major_input=time_major_input,
        )
    elif target in ("lava", "lava_sim"):
        hw_mode = target == "lava"
        arch_code, io_error = _safe_io_call(
            lambda: LavaIO().from_nir(graph, hw_mode=hw_mode),
            "LavaIO",
            target,
        )
    elif target == "sc_neurocore_sim":
        arch_code, arch_weights = _generate_sc_neurocore_code(graph, weights_filename)
    elif target == "sc_neurocore_fpga":
        arch_code, arch_weights = _generate_sc_neurocore_code(graph, weights_filename)
        arch_code += (
            "\n\n"
            "# FPGA synthesis — configure RTL flow after simulation passes:\n"
            "# import sc_neurocore_fpga\n"
            "# sc_neurocore_fpga.synthesize(model, target='pynq_z2')"
        )
    elif target == "akida":
        arch_code, arch_weights = _generate_akida_code(graph, weights_filename)
    elif target == "brian2":
        arch_code, io_error = _safe_io_call(
            lambda: Brian2IO().from_nir(graph), "Brian2IO", "brian2"
        )
    elif target == "sinabs":
        arch_code, io_error = _safe_io_call(
            lambda: SinabsIO().from_nir(graph), "SinabsIO", "sinabs"
        )
    elif target == "rockpool":
        arch_code = _generate_rockpool_code(graph, embed_flatten=cnl_flattened)
    elif target == "pynn":
        arch_code, io_error = _safe_io_call(
            lambda: PyNNIO().from_nir(graph), "PyNNIO", "pynn"
        )
    elif target == "nengo":
        # cfg.nengo_dt feeds NengoIO.from_nir's CubaLIF tau_syn discretization
        # correction (paper/03_rnn/nir_to_nengo.py's `-dt/log(1-dt/tau_syn)`
        # formula) — it must match whatever dt a downstream nengo.Simulator
        # actually runs at, or the synaptic filter time constant is wrong.
        arch_code, io_error = _safe_io_call(
            lambda: NengoIO().from_nir(graph, dt=cfg.nengo_dt), "NengoIO", "nengo"
        )
    else:
        arch_code = (
            "import nir\n\n"
            "# The graph object from compile_to_nir is already available above.\n"
            "# Inspect nodes and edges:\n"
            "for node_id, node in graph.nodes.items():\n"
            "    print(f'  {node_id}: {type(node).__name__}')\n"
            "print(f'Edges: {list(graph.edges.keys())}')"
        )
    return arch_code, arch_weights, io_error
