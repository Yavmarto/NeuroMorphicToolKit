"""snnTorch simulator adapter for the shared CNL → NIR → Simulator contract.

This module bridges the T1-5 contract layer with the snnTorch surrogate-gradient
framework, used here strictly as a **fixed-weight inference simulator** — no
training, no surrogate gradients, no backward pass.

The adapter:

1. Topologically sorts a compiled ``nir.NIRGraph`` into an ordered sequence of
   ``torch.nn`` and ``snntorch`` modules.
2. Runs a deterministic timestep loop with spike injection from the shared
   :class:`~neurocnl.runtime.stimulus.ValidatedStimulus` contract.
3. Collects per-neuron spike times and membrane traces for the output population.
4. Normalises everything into the shared ``SimulatorRunResult`` schema.

Design constraints
------------------
- ``torch`` and ``snntorch`` are **never imported at module level** so missing
  dependencies cannot crash the NeuroCNL backend at startup.
- The existing ``SnnTorchAdapter`` in ``neurocnl.training`` is **not touched**;
  this module is solely concerned with simulation.
- There is no remote-worker path: snnTorch is pure PyTorch and always runs
  in-process when the dependencies are available.
- Loihi, hardware, or CUDA paths are never activated; the adapter always runs
  on CPU with ``torch.no_grad()``.
"""

from __future__ import annotations

import logging
import time
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Any

import nir
import numpy as np

from neurocnl.lif_semantics import LifDiscretization, discretize_lif
from neurocnl.runtime.cnl_nodes import RSynaptic, Synaptic
from neurocnl.runtime.lava_simulator import _infer_output_population
from neurocnl.runtime.snntorch_module_factory import build_synaptic_module
from neurocnl.runtime.stimulus import ValidatedStimulus

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# Public result type
# ---------------------------------------------------------------------------


@dataclass(slots=True)
class SnnTorchSimulatorResult:
    """Result returned by :class:`SnnTorchSimulatorAdapter`.

    Attributes
    ----------
    spikes : dict[str, dict[str, list[int]]]
        ``population_name → {neuron_index_str → [timestep, ...]}``
    voltages : dict[str, dict[str, list[float]]]
        Membrane traces for the output LIF population.
        ``population_name → {neuron_index_str → [voltage_at_t0, voltage_at_t1, ...]}``
    execution_time_ms : float
        Wall-clock time for the snnTorch timestep loop.
    runtime_mode : str
        Always ``"in_process_snntorch_sim"``.
    warnings : list[str]
        Non-fatal messages about approximated NIR semantics (e.g. CubaLIF, Delay).
    """

    spikes: dict[str, dict[str, list[int]]] = field(default_factory=dict)
    voltages: dict[str, dict[str, list[float]]] = field(default_factory=dict)
    execution_time_ms: float = 0.0
    runtime_mode: str = "in_process_snntorch_sim"
    warnings: list[str] = field(default_factory=list)


# ---------------------------------------------------------------------------
# Error type
# ---------------------------------------------------------------------------


class SnnTorchDispatchError(RuntimeError):
    """Raised when the snnTorch adapter cannot build the model or run the loop.

    Attributes
    ----------
    diagnostics : list[str]
        Human-readable messages, one per detected problem.
    """

    def __init__(self, *diagnostics: str) -> None:
        self.diagnostics: list[str] = list(diagnostics)
        super().__init__("; ".join(diagnostics))


# ---------------------------------------------------------------------------
# Import helpers (never at module level)
# ---------------------------------------------------------------------------


def _import_snntorch() -> tuple[Any, Any, Any]:
    """Import and return ``(torch, torch.nn, snntorch)``.

    Raises
    ------
    ImportError
        When ``torch`` or ``snntorch`` is not installed.
    """
    import snntorch
    import torch
    import torch.nn as nn

    return torch, nn, snntorch


# ---------------------------------------------------------------------------
# Graph helpers
# ---------------------------------------------------------------------------


def _topological_sort(graph: nir.NIRGraph) -> list[str]:
    """Return node names in a feed-forward topological order.

    Uses Kahn's algorithm.  Boundary ``nir.Input`` and ``nir.Output`` nodes are
    included so the caller can filter them; the caller decides which to use.

    Raises
    ------
    SnnTorchDispatchError
        If the graph contains a cycle (should not happen after support classification).
    """
    in_degree: dict[str, int] = dict.fromkeys(graph.nodes, 0)
    adj: dict[str, list[str]] = {name: [] for name in graph.nodes}
    for pre, post in graph.edges:
        if pre in adj and post in in_degree:
            adj[pre].append(post)
            in_degree[post] += 1

    queue = [name for name, deg in in_degree.items() if deg == 0]
    order: list[str] = []
    while queue:
        node = queue.pop(0)
        order.append(node)
        for neighbour in adj[node]:
            in_degree[neighbour] -= 1
            if in_degree[neighbour] == 0:
                queue.append(neighbour)

    if len(order) != len(graph.nodes):
        raise SnnTorchDispatchError(
            "The NIR graph contains a cycle and cannot be executed as a feed-forward "
            "snnTorch network.  Remove recurrent connections before simulating."
        )
    return order


def _input_size(graph: nir.NIRGraph) -> int:
    """Return the size of the first ``nir.Input`` node."""
    for node in graph.nodes.values():
        if isinstance(node, nir.Input):
            input_type = node.input_type
            if isinstance(input_type, dict) and input_type:
                shape = next(iter(input_type.values()))
                if hasattr(shape, "__len__") and len(shape) > 0:
                    return int(shape[0])
    return 1


def _node_input_size(node: nir.NIRNode) -> int:
    """Infer the leading input dimension for a NIR node."""
    try:
        input_type = node.input_type
        if isinstance(input_type, dict) and input_type:
            shape = next(iter(input_type.values()))
            if hasattr(shape, "__len__") and len(shape) > 0:
                values = np.asarray(shape)
                leading_size = int(values.flat[0])
                # Some valid in-memory NIR graphs describe a vector type with
                # ``np.zeros(width)``.  Its entries are sample values, not
                # dimensions, so preserve its vector width instead of creating
                # a zero-width tensor.
                return leading_size if leading_size > 0 else int(values.size)
    except (AttributeError, TypeError, IndexError, StopIteration):
        pass
    return 1


def _node_output_size(node: nir.NIRNode) -> int:
    """Infer the leading output dimension for a NIR node."""
    try:
        output_type = node.output_type
        if isinstance(output_type, dict) and output_type:
            shape = next(iter(output_type.values()))
            if hasattr(shape, "__len__") and len(shape) > 0:
                values = np.asarray(shape)
                leading_size = int(values.flat[0])
                return leading_size if leading_size > 0 else int(values.size)
    except (AttributeError, TypeError, IndexError, StopIteration):
        pass
    if isinstance(node, nir.Linear):
        return int(np.asarray(node.weight).shape[0])
    return _node_input_size(node)


def _discretize(node: nir.NIRNode, graph: nir.NIRGraph | None) -> LifDiscretization:
    """Resolve a LIF-family node onto the graph's timestep, or fail loudly.

    Wraps :func:`neurocnl.lif_semantics.discretize_lif` so an unusable time
    constant surfaces as a :class:`SnnTorchDispatchError` carrying the helper's
    actionable message, rather than as a silently substituted default decay.
    Silent defaults are what produced saturated rasters here for years.
    """
    try:
        return discretize_lif(node, graph=graph)
    except (TypeError, ValueError) as exc:
        raise SnnTorchDispatchError(str(exc)) from exc


def _lif_threshold(node: nir.NIRNode) -> float:
    """Return the mean firing threshold from a NIR LIF ``v_threshold`` array."""
    try:
        arr = np.asarray(node.v_threshold, dtype=float)
        return float(np.mean(arr))
    except (AttributeError, TypeError, ValueError):
        return 1.0


# ---------------------------------------------------------------------------
# Stimulus injection helper
# ---------------------------------------------------------------------------


def _build_input_tensor(
    stimulus: ValidatedStimulus,
    t: int,
    input_size: int,
    torch_module: Any,
) -> Any:
    """Build a binary input spike tensor for timestep ``t``.

    Parameters
    ----------
    stimulus : ValidatedStimulus
        The validated stimulus from the shared contract.
    t : int
        Current timestep index.
    input_size : int
        Number of input neurons.
    torch_module : module
        The ``torch`` module (injected to avoid top-level import).
    """
    x = torch_module.zeros(input_size, dtype=torch_module.float32)
    for neuron_idx, spike_times in stimulus.spikes.items():
        if t in spike_times:
            if 0 <= neuron_idx < input_size:
                x[neuron_idx] = 1.0
    return x


# ---------------------------------------------------------------------------
# Main adapter
# ---------------------------------------------------------------------------


class SnnTorchSimulatorAdapter:
    """Dispatch a compiled NIR graph to snnTorch for fixed-weight simulation.

    Always runs in-process.  Raises :class:`SnnTorchDispatchError` when
    ``torch`` or ``snntorch`` are not installed or when execution fails.
    """

    def run(
        self,
        graph: nir.NIRGraph,
        stimulus: ValidatedStimulus,
        timesteps: int,
        seed: int,
    ) -> SnnTorchSimulatorResult:
        """Simulate *graph* with snnTorch and return spike + voltage output.

        Parameters
        ----------
        graph : nir.NIRGraph
            Compiled NIR graph from ``compile_to_nir()``.
        stimulus : ValidatedStimulus
            Validated stimulus specifying input spike times.
        timesteps : int
            Number of simulation timesteps.
        seed : int
            Random seed, set via ``torch.manual_seed`` before simulation.
            The simulation dynamics are deterministic for fixed graph weights;
            this seed primarily affects **default stimulus generation** (when
            no explicit stimulus is provided in the API request).

        Returns
        -------
        SnnTorchSimulatorResult

        Raises
        ------
        SnnTorchDispatchError
            When ``torch`` / ``snntorch`` are not installed, the graph cannot
            be converted, or the timestep loop fails.
        """
        try:
            torch, nn, snntorch = _import_snntorch()
        except ImportError as exc:
            raise SnnTorchDispatchError(
                f"torch or snntorch is not installed: {exc}.  "
                "Install with: pip install torch snntorch"
            ) from exc

        try:
            torch.manual_seed(seed)
            return self._simulate(graph, stimulus, timesteps, torch, nn, snntorch)
        except SnnTorchDispatchError:
            raise
        except Exception as exc:  # noqa: BLE001
            raise SnnTorchDispatchError(f"snnTorch simulation failed: {exc}") from exc

    # ------------------------------------------------------------------
    # Internal simulation
    # ------------------------------------------------------------------

    def _simulate(
        self,
        graph: nir.NIRGraph,
        stimulus: ValidatedStimulus,
        timesteps: int,
        torch: Any,
        nn: Any,
        snntorch: Any,
    ) -> SnnTorchSimulatorResult:
        warnings: list[str] = []

        # ── Topological sort ─────────────────────────────────────────────────
        topo_order = _topological_sort(graph)

        # ── Build torch modules for executable nodes ─────────────────────────
        # Execute by graph dependencies rather than flattening to a single
        # sequence, so branched CNL topologies can fan out and merge cleanly.
        modules: dict[str, Any] = {}
        lif_node_names: list[str] = []
        synaptic_node_names: list[str] = []
        rsynaptic_node_names: list[str] = []
        # population name -> factor converting snnTorch's rescaled membrane
        # units back into NIR volts for reporting (see the voltage_record write).
        voltage_scales: dict[str, float] = {}

        for name in topo_order:
            node = graph.nodes[name]

            if isinstance(node, nir.Input):
                continue  # boundary — driven by stimulus
            if isinstance(node, nir.Output):
                continue  # boundary — collect from last LIF

            if isinstance(node, nir.Linear):
                weight = np.asarray(node.weight, dtype=np.float32)
                out_features, in_features = weight.shape
                linear = nn.Linear(in_features, out_features, bias=False)
                with torch.no_grad():
                    linear.weight.copy_(torch.tensor(weight))
                linear.weight.requires_grad_(False)
                modules[name] = linear

            elif isinstance(node, nir.LIF):
                discretization = _discretize(node, graph)
                modules[name] = snntorch.Leaky(
                    beta=discretization.beta, threshold=discretization.threshold
                )
                voltage_scales[name] = discretization.input_scale
                lif_node_names.append(name)
                warnings.extend(
                    f"nir.LIF '{name}': {w}" for w in discretization.warnings
                )

            elif isinstance(node, nir.CubaLIF):
                # Reads tau_mem, not tau. CubaLIF has no .tau, so the previous
                # _lif_beta(node) call fell through its AttributeError guard and
                # gave every CubaLIF the same hardcoded decay.
                discretization = _discretize(node, graph)
                modules[name] = snntorch.Leaky(
                    beta=discretization.beta, threshold=discretization.threshold
                )
                voltage_scales[name] = discretization.input_scale
                lif_node_names.append(name)
                warnings.extend(
                    f"nir.CubaLIF '{name}': {w}" for w in discretization.warnings
                )
                warnings.append(
                    f"nir.CubaLIF '{name}' is mapped to snntorch.Leaky with approximate "
                    "conductance-based dynamics. Synaptic current filtering is not modelled "
                    f"(tau_syn would give alpha={discretization.alpha:.4f})."
                    if discretization.alpha is not None
                    else f"nir.CubaLIF '{name}' is mapped to snntorch.Leaky with approximate "
                    "conductance-based dynamics. Synaptic current filtering is not modelled."
                )

            elif isinstance(node, nir.Delay):
                # Approximate — skip execution, classifier already labelled this
                warnings.append(
                    f"nir.Delay '{name}' is not modelled in the snnTorch timestep loop "
                    "and is skipped. The result is labelled 'approximate'."
                )
                # Passthrough during graph execution.

            elif isinstance(node, nir.Affine):
                weight = np.asarray(node.weight, dtype=np.float32)
                bias = np.asarray(node.bias, dtype=np.float32)
                out_features, in_features = weight.shape
                layer = nn.Linear(in_features, out_features, bias=True)
                with torch.no_grad():
                    layer.weight.copy_(torch.tensor(weight))
                    layer.bias.copy_(torch.tensor(bias))
                layer.weight.requires_grad_(False)
                layer.bias.requires_grad_(False)
                modules[name] = layer

            elif isinstance(node, nir.Conv2d):
                w = np.asarray(node.weight, dtype=np.float32)  # (out, in, kH, kW)
                out_ch, in_ch, kH, kW = w.shape
                has_bias = hasattr(node, "bias") and node.bias is not None
                stride = (
                    tuple(int(s) for s in np.asarray(node.stride).flat)
                    if hasattr(node, "stride")
                    else (1, 1)
                )
                padding = (
                    tuple(int(p) for p in np.asarray(node.padding).flat)
                    if hasattr(node, "padding")
                    else (0, 0)
                )
                layer = nn.Conv2d(
                    in_ch,
                    out_ch,
                    (kH, kW),
                    stride=stride,
                    padding=padding,
                    bias=has_bias,
                )
                with torch.no_grad():
                    layer.weight.copy_(torch.tensor(w))
                    if has_bias:
                        layer.bias.copy_(
                            torch.tensor(np.asarray(node.bias, dtype=np.float32))
                        )
                layer.weight.requires_grad_(False)
                modules[name] = layer

            elif isinstance(node, nir.Flatten):
                start_dim = int(getattr(node, "start_dim", 1))
                end_dim = int(getattr(node, "end_dim", -1))
                modules[name] = nn.Flatten(start_dim=start_dim, end_dim=end_dim)

            elif isinstance(node, nir.IF):
                threshold = (
                    _lif_threshold(node) or 1.0
                )  # ponytail: threshold=0 fires every step
                # IF has no leak.  ``Leaky(beta=1)`` exactly expresses that
                # state update and keeps IF on the same membrane-state API as
                # LIF; Lapicque uses a different initialisation method.
                modules[name] = snntorch.Leaky(beta=1.0, threshold=threshold)
                lif_node_names.append(name)

            elif isinstance(node, nir.AvgPool2d):
                pool_size = next(
                    (
                        value
                        for value in (
                            getattr(node, "kernel_size", None),
                            getattr(node, "pool_size", None),
                            getattr(node, "sumpool_size", None),
                        )
                        if value is not None
                    ),
                    None,
                )
                if pool_size is None:
                    raise SnnTorchDispatchError(
                        f"nir.AvgPool2d '{name}' has no recognisable pool_size attribute. "
                        "Check the installed NIR version."
                    )
                kernel_size = tuple(int(k) for k in np.asarray(pool_size).flat)
                stride_attr = getattr(node, "stride", None)
                stride = (
                    tuple(int(s) for s in np.asarray(stride_attr).flat)
                    if stride_attr is not None
                    else kernel_size
                )
                modules[name] = nn.AvgPool2d(kernel_size=kernel_size, stride=stride)

            elif isinstance(node, Synaptic):
                # Construction is shared with the trainable recurrent model builder
                # in neurocnl.training.snntorch_adapter — see snntorch_module_factory
                # for the alpha/beta/threshold/reset/bias/recurrent-weight logic.
                modules[name] = build_synaptic_module(node, snntorch, torch)
                synaptic_node_names.append(name)

            elif isinstance(node, RSynaptic):
                modules[name] = build_synaptic_module(node, snntorch, torch)
                if getattr(node, "recurrent_weight", None) is not None:
                    # This is a fixed-weight, inference-only preview: freeze the
                    # imported recurrent weight so it can never accidentally be
                    # updated by anything that later calls .backward() on this
                    # module (the trainable path in snntorch_adapter.py wants the
                    # opposite — see build_synaptic_module's docstring).
                    modules[name].recurrent.weight.requires_grad_(False)
                rsynaptic_node_names.append(name)

            else:
                # Should have been rejected by classifier; defensive skip
                warnings.append(
                    f"nir.{type(node).__name__} '{name}' is not supported by the snnTorch "
                    "adapter and is skipped."
                )

        if not modules:
            raise SnnTorchDispatchError(
                "The compiled NIR graph produced no executable snnTorch layers — "
                "nothing to simulate."
            )

        # ── Identify output population ────────────────────────────────────────
        # All spiking neuron lists combined for output detection and recording
        all_spiking_node_names = (
            lif_node_names + synaptic_node_names + rsynaptic_node_names
        )
        output_pop_name = _infer_output_population(graph)
        synthetic_spiking_output = not all_spiking_node_names
        if synthetic_spiking_output:
            output_nodes = [
                name for name in topo_order if isinstance(graph.nodes[name], nir.Output)
            ]
            if output_nodes:
                output_pop_name = output_nodes[-1]
            warnings.append(
                "The compiled NIR graph contains no LIF populations; snnTorch is "
                "reporting thresholded linear output activity as spikes."
            )
        elif output_pop_name not in all_spiking_node_names:
            output_pop_name = all_spiking_node_names[-1]

        # ── Initialise membrane states ────────────────────────────────────────
        mem_states: dict[str, Any] = {}
        for name in lif_node_names:
            mem_states[name] = modules[name].init_leaky()
        for name in synaptic_node_names:
            # init_synaptic() returns (syn, mem) — store as a 2-tuple
            mem_states[name] = modules[name].init_synaptic()
        for name in rsynaptic_node_names:
            # snntorch.RSynaptic.init_rsynaptic() returns a ``spk`` placeholder
            # of shape (0,) (it doesn't know the real neuron count yet). With
            # reset_delay=False (this codebase's required convention — see
            # build_synaptic_module), RSynaptic.forward's reset branch does
            # arithmetic directly on the raw ``spk`` argument, which crashes on
            # the very first call unless it is already shaped like this node's
            # real output (verified by reproducing the crash against installed
            # snntorch==1.0.0). Pre-shape the initial spk/syn/mem ourselves
            # instead of trusting the placeholder.
            n_neurons = int(graph.nodes[name].n_neurons)
            zeros = torch.zeros(n_neurons, dtype=torch.float32)
            mem_states[name] = (zeros, zeros.clone(), zeros.clone())

        predecessors: dict[str, list[str]] = {name: [] for name in graph.nodes}
        for pre, post in graph.edges:
            predecessors.setdefault(post, []).append(pre)

        # ── Timestep loop ────────────────────────────────────────────────────
        spike_record: dict[str, dict[int, list[int]]] = {
            n: defaultdict(list) for n in all_spiking_node_names
        }
        voltage_record: dict[str, dict[int, list[float]]] = {
            n: defaultdict(list) for n in all_spiking_node_names
        }
        if synthetic_spiking_output:
            spike_record[output_pop_name] = defaultdict(list)
            voltage_record[output_pop_name] = defaultdict(list)

        t_start = time.monotonic()
        with torch.no_grad():
            for t in range(timesteps):
                outputs: dict[str, Any] = {}

                for name in topo_order:
                    node = graph.nodes[name]
                    if isinstance(node, nir.Input):
                        if name == stimulus.population:
                            outputs[name] = _build_input_tensor(
                                stimulus,
                                t,
                                _node_output_size(node),
                                torch,
                            )
                        else:
                            outputs[name] = torch.zeros(
                                _node_output_size(node),
                                dtype=torch.float32,
                            )
                        continue

                    incoming = [
                        outputs[pre]
                        for pre in predecessors.get(name, [])
                        if pre in outputs
                    ]
                    if incoming:
                        x = incoming[0]
                        for extra in incoming[1:]:
                            if tuple(extra.shape) != tuple(x.shape):
                                raise SnnTorchDispatchError(
                                    f"snnTorch graph merge into '{name}' has incompatible "
                                    f"tensor shapes {tuple(x.shape)} and {tuple(extra.shape)}."
                                )
                            x = x + extra
                    else:
                        x = torch.zeros(_node_input_size(node), dtype=torch.float32)

                    module = modules[name]
                    if isinstance(node, nir.Linear):
                        outputs[name] = module(x)
                    elif isinstance(node, nir.LIF | nir.CubaLIF | nir.IF):
                        spk, mem = module(x, mem_states[name])
                        mem_states[name] = mem
                        if name in spike_record:
                            for i, s in enumerate(spk.tolist()):
                                if s:
                                    spike_record[name][i].append(t)
                            # snnTorch integrates in rescaled units (u = v /
                            # input_scale, threshold scaled to match), so the raw
                            # trace is input_scale times the real membrane
                            # voltage. Report NIR volts so this panel's y-axis
                            # means the same thing as the other backends'.
                            scale = voltage_scales.get(name, 1.0)
                            for i, v in enumerate(mem.tolist()):
                                voltage_record[name][i].append(
                                    round(float(v) * scale, 5)
                                )
                        outputs[name] = spk
                    elif isinstance(node, Synaptic):
                        # snn.Synaptic forward: spk, syn, mem = layer(cur, syn, mem)
                        syn_s, mem_s = mem_states[name]
                        spk, syn_s, mem_s = module(x, syn_s, mem_s)
                        mem_states[name] = (syn_s, mem_s)
                        if name in spike_record:
                            for i, s in enumerate(spk.tolist()):
                                if s:
                                    spike_record[name][i].append(t)
                            for i, v in enumerate(mem_s.tolist()):
                                voltage_record[name][i].append(round(float(v), 5))
                        outputs[name] = spk
                    elif isinstance(node, RSynaptic):
                        # snn.RSynaptic forward: spk, syn, mem = layer(cur, spk_prev, syn, mem)
                        spk_prev, syn_s, mem_s = mem_states[name]
                        spk, syn_s, mem_s = module(x, spk_prev, syn_s, mem_s)
                        mem_states[name] = (spk, syn_s, mem_s)
                        if name in spike_record:
                            for i, s in enumerate(spk.tolist()):
                                if s:
                                    spike_record[name][i].append(t)
                            for i, v in enumerate(mem_s.tolist()):
                                voltage_record[name][i].append(round(float(v), 5))
                        outputs[name] = spk
                    elif isinstance(node, nir.Delay):
                        outputs[name] = x
                    elif isinstance(node, nir.Affine):
                        outputs[name] = modules[name](x)
                    elif isinstance(node, nir.Conv2d):
                        spatial_shape = tuple(int(dim) for dim in node.input_shape)
                        input_channels = int(np.asarray(node.weight).shape[1])
                        required_values = input_channels * int(np.prod(spatial_shape))
                        flat_input = x.reshape(-1)
                        if flat_input.numel() < required_values:
                            flat_input = nn.functional.pad(
                                flat_input, (0, required_values - flat_input.numel())
                            )
                        conv_input = flat_input[:required_values].reshape(
                            1, input_channels, *spatial_shape
                        )
                        outputs[name] = modules[name](conv_input).reshape(-1)
                    elif isinstance(node, nir.Flatten):
                        # NIR tensors are batchless at graph boundaries while
                        # ``torch.nn.Flatten`` defaults to preserving dim 0.
                        outputs[name] = modules[name](x.reshape(1, *x.shape)).reshape(
                            -1
                        )
                    elif isinstance(node, nir.AvgPool2d):
                        flat_input = x.reshape(-1)
                        side = max(1, int(np.ceil(np.sqrt(flat_input.numel()))))
                        required_values = side * side
                        if flat_input.numel() < required_values:
                            flat_input = nn.functional.pad(
                                flat_input, (0, required_values - flat_input.numel())
                            )
                        pool_input = flat_input[:required_values].reshape(
                            1, 1, side, side
                        )
                        outputs[name] = modules[name](pool_input).reshape(-1)
                    elif isinstance(node, nir.Output):
                        outputs[name] = x
                    else:
                        outputs[name] = x

                if synthetic_spiking_output:
                    output_tensor = outputs.get(output_pop_name)
                    if output_tensor is None:
                        output_nodes = [
                            name
                            for name in topo_order
                            if isinstance(graph.nodes[name], nir.Output)
                        ]
                        if output_nodes:
                            output_tensor = outputs.get(output_nodes[-1])
                    if output_tensor is None:
                        output_tensor = outputs.get(topo_order[-1])
                    if output_tensor is not None:
                        for i, value in enumerate(output_tensor.tolist()):
                            scalar = float(value)
                            voltage_record[output_pop_name][i].append(round(scalar, 5))
                            if scalar > 0.0:
                                spike_record[output_pop_name][i].append(t)

        execution_time_ms = (time.monotonic() - t_start) * 1000.0

        # ── Normalise output ─────────────────────────────────────────────────
        spikes: dict[str, dict[str, list[int]]] = {
            pop: {str(i): times for i, times in per_pop.items() if times}
            for pop, per_pop in spike_record.items()
        }
        voltages: dict[str, dict[str, list[float]]] = {
            pop: {str(i): v_list for i, v_list in per_pop.items() if v_list}
            for pop, per_pop in voltage_record.items()
        }

        if not spikes[output_pop_name]:
            warnings.append(
                f"snnTorch ran {timesteps} timesteps but recorded no spikes in "
                f"population '{output_pop_name}'. "
                "Check your stimulus spike times and neuron threshold settings."
            )

        return SnnTorchSimulatorResult(
            spikes=spikes,
            voltages=voltages,
            execution_time_ms=round(execution_time_ms, 3),
            runtime_mode="in_process_snntorch_sim",
            warnings=warnings,
        )
