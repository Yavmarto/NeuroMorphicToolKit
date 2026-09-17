"""CNLStudio-internal node types that extend beyond the standard NIR primitive set.

These classes are **not** part of the upstream NIR specification.  They exist
so CNLStudio can represent snnTorch-specific neuron types (RSynaptic, Synaptic)
in a ``nir.NIRGraph`` without waiting for those types to be added to the NIR
standard.

Design notes
------------
* Each class carries a ``CNL_NIR_TYPE`` class attribute with the canonical
  ``"cnl.<ClassName>"`` string used in canvas ``nir_type`` fields and the
  ``NIR_CANVAS_TYPE_SPECS`` registry.
* The ``make_nir_graph`` compat helper uses ``skip_type_check=True`` by default,
  so these non-NIRNode objects can be placed in ``nir.NIRGraph.nodes`` without
  triggering type-check errors on nir ≥ 1.0.0.
* ``classify_nir_graph`` in ``nir_support.py`` identifies nodes by
  ``type(node).__name__``, so adding ``"Synaptic"`` and ``"RSynaptic"`` to
  ``COMPLETE_PRIMITIVE_SET`` and the per-backend support tables is sufficient.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any


@dataclass
class Synaptic:
    """Non-recurrent snnTorch Synaptic neuron (snn.Synaptic).

    Implements a two-state leaky integrate-and-fire neuron with an explicit
    synaptic current trace:
        syn[t+1] = alpha * syn[t] + I[t]
        mem[t+1] = beta  * mem[t] + syn[t+1]
        spk[t]   = mem[t] >= threshold

    Parameters
    ----------
    n_neurons : int
        Population size.
    alpha : float
        Synaptic decay factor ∈ (0, 1).  Maps to snn.Synaptic ``alpha``.
    beta : float
        Membrane decay factor ∈ (0, 1).  Maps to snn.Synaptic ``beta``.
    threshold : float
        Firing threshold.
    reset_mechanism : str
        ``"subtract"`` (default) or ``"zero"``.
    metadata : dict, optional
        Canvas provenance metadata (label, position, etc.).
    """

    CNL_NIR_TYPE: str = field(default="cnl.Synaptic", init=False, repr=False, compare=False)

    n_neurons: int = 1
    alpha: float = 0.9
    beta: float = 0.8
    threshold: float = 1.0
    reset_mechanism: str = "subtract"
    metadata: dict[str, Any] | None = None


@dataclass
class RSynaptic:
    """Recurrent snnTorch RSynaptic neuron (snn.RSynaptic).

    Identical to :class:`Synaptic` but with an additional built-in recurrent
    ``nn.Linear`` that feeds the previous spike back as an extra input current:
        cur_rec[t] = W_rec @ spk[t-1]
        syn[t+1] = alpha * syn[t] + I[t] + cur_rec[t]
        mem[t+1] = beta  * mem[t] + syn[t+1]
        spk[t]   = mem[t] >= threshold

    The recurrent Linear weight matrix is initialised by snnTorch and has shape
    ``(n_neurons, n_neurons)``.

    Parameters
    ----------
    n_neurons : int
        Population size (also the ``linear_features`` passed to snn.RSynaptic).
    alpha : float
        Synaptic decay factor ∈ (0, 1).
    beta : float
        Membrane decay factor ∈ (0, 1).
    threshold : float
        Firing threshold.
    reset_mechanism : str
        ``"subtract"`` (default) or ``"zero"``.
    use_bias : bool
        Whether the internal recurrent Linear layer uses a bias term.
    recurrent_weight : list[list[float]], optional
        Trained recurrent ``nn.Linear`` weight matrix (shape ``(n_neurons,
        n_neurons)``), populated when this node was produced by fusing an
        imported ``nir.CubaLIF`` + self-loop ``nir.Linear`` pair
        (``nir_topology.fuse_recurrent_pairs``). ``None`` (the default) means
        no trained recurrent weight is available and snnTorch's own random
        initialisation is used instead. Defaulting to ``None`` keeps every
        existing caller that builds an ``RSynaptic`` without this field
        (e.g. ``snntorch_simulator.py``'s preview path, ``cnl_flatten.py``)
        unaffected.
    metadata : dict, optional
        Canvas provenance metadata.
    """

    CNL_NIR_TYPE: str = field(default="cnl.RSynaptic", init=False, repr=False, compare=False)

    n_neurons: int = 1
    alpha: float = 0.9
    beta: float = 0.8
    threshold: float = 1.0
    reset_mechanism: str = "subtract"
    use_bias: bool = False
    metadata: dict[str, Any] | None = None
    recurrent_weight: list[list[float]] | None = None


@dataclass
class RLeaky:
    """Recurrent snnTorch Leaky neuron (snn.RLeaky).

    A Leaky (LIF) neuron with a built-in recurrent ``nn.Linear(n, n)`` that
    feeds the previous spike output back as an extra input current:
        cur_rec[t] = W_rec @ spk[t-1]
        mem[t+1]   = beta * mem[t] + I[t] + cur_rec[t]
        spk[t]     = mem[t] >= threshold

    Simpler than RSynaptic: single time constant, two hidden states (spk, mem)
    instead of three.  Appears as a commented alternative in the paper notebooks
    (``paper/03_rnn``).

    Parameters
    ----------
    n_neurons : int
        Population size (also the ``linear_features`` passed to snn.RLeaky).
    beta : float
        Membrane decay factor ∈ (0, 1).
    threshold : float
        Firing threshold.
    reset_mechanism : str
        ``"subtract"`` (default) or ``"zero"``.
    metadata : dict, optional
        Canvas provenance metadata.
    """

    CNL_NIR_TYPE: str = field(default="cnl.RLeaky", init=False, repr=False, compare=False)

    n_neurons: int = 1
    beta: float = 0.9
    threshold: float = 1.0
    reset_mechanism: str = "subtract"
    metadata: dict[str, Any] | None = None


@dataclass
class Leaky:
    """Explicit-beta snnTorch Leaky neuron (snn.Leaky, init_hidden=False).

    Like ``nir.LIF`` but parameterised by ``beta`` directly — the natural
    snnTorch parameterisation — instead of requiring tau/r/v_threshold.
    Uses explicit state threading (``init_hidden=False``).

    Parameters
    ----------
    n_neurons : int
        Population size.
    beta : float
        Membrane decay factor ∈ (0, 1).
    threshold : float
        Firing threshold.
    reset_mechanism : str
        ``"subtract"`` (default) or ``"zero"``.
    metadata : dict, optional
        Canvas provenance metadata.
    """

    CNL_NIR_TYPE: str = field(default="cnl.Leaky", init=False, repr=False, compare=False)

    n_neurons: int = 1
    beta: float = 0.9
    threshold: float = 1.0
    reset_mechanism: str = "subtract"
    metadata: dict[str, Any] | None = None


@dataclass
class BatchNorm1d:
    """nn.BatchNorm1d inserted as a canvas layer node.

    Stateless — no hidden state.  Placed between a linear layer and a spiking
    layer to stabilise training of deep SNNs.

    Parameters
    ----------
    num_features : int
        Number of input features (= output size of the preceding layer).
    metadata : dict, optional
        Canvas provenance metadata.
    """

    CNL_NIR_TYPE: str = field(default="cnl.BatchNorm1d", init=False, repr=False, compare=False)

    num_features: int = 1
    metadata: dict[str, Any] | None = None


@dataclass
class Dropout:
    """nn.Dropout inserted as a canvas layer node.

    Stateless — zeroes activations randomly during training.  Especially useful
    in recurrent networks to prevent memorisation.

    Parameters
    ----------
    p : float
        Drop probability ∈ [0, 1).
    metadata : dict, optional
        Canvas provenance metadata.
    """

    CNL_NIR_TYPE: str = field(default="cnl.Dropout", init=False, repr=False, compare=False)

    p: float = 0.5
    metadata: dict[str, Any] | None = None
