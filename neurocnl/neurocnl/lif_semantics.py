"""Single source of truth for NIR LIF time-constant discretization.

``nir.LIF.tau`` is a **membrane time constant in seconds**.  Every execution
backend that steps a network in discrete time must turn it into a per-step
decay factor, and every backend must use *the same* conversion or a network
trained on one target silently becomes a different network on another.

The conversion
--------------
NIR's LIF is the continuous-time ODE

    tau * dv/dt = (v_leak - v) + R * I

Forward Euler at step ``dt``, with ``v_leak = 0``, gives

    v[t+1] = (1 - dt/tau) * v[t] + (R * dt/tau) * I[t]

snnTorch's ``Leaky`` has no input-gain term -- it is ``u[t+1] = beta*u[t] +
I[t]``.  Substituting ``u = v / input_scale`` with ``input_scale = R*dt/tau``
makes the two *identical*, which is why the firing threshold is divided by
``input_scale``.  That is a change of variables, not an approximation, so
resist the standing temptation to "improve" the formula.

This matches upstream ``snntorch.import_nir._nir_to_snntorch_module`` exactly.
That matters: it is the code path a user hits when they take an exported
``.nir`` out of CNLStudio and load it in stock snnTorch.  Diverging from it
here would trade internal consistency for external inconsistency with the one
library we cannot patch, and would invalidate every trained checkpoint.

:class:`DiscretizationScheme.EXACT` (``beta = exp(-dt/tau)``) is provided so
the choice is documented and testable.  It is deliberately not the default and
is deliberately not surfaced in the UI: at the target regime ``dt/tau <= 0.1``
the two schemes differ by ``O((dt/tau)**2 / 2)`` -- 0.13% at ``dt/tau = 0.05``
-- which is immaterial next to the interop cost.  Note also that a
ZOH-consistent input gain would be ``R * (1 - exp(-dt/tau))``, not ``R*dt/tau``,
so switching schemes means switching *two* formulas, not one.

Unit invariants this module exists to protect
---------------------------------------------
- ``nir.LIF.tau`` / ``nir.CubaLIF.tau_mem`` / ``.tau_syn`` are **seconds**.
- ``cnl.Leaky.beta`` / ``cnl.Synaptic.alpha`` are **dimensionless per-step
  decay** at the ``dt`` recorded in that node's ``metadata["dt"]``.
- Conversion between the two goes through :func:`decay_from_tau` and
  :func:`tau_seconds_from_decay`, which are exact inverses.  Hand-rolling
  either direction is how ``tau`` values end up in timestep units inside a
  seconds-typed field.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from enum import Enum
from typing import Any

import nir
import numpy as np

__all__ = [
    "DEFAULT_LIF_DT_SECONDS",
    "DiscretizationScheme",
    "LifDiscretization",
    "decay_from_tau",
    "discretize_lif",
    "lava_lif_parameters",
    "resolve_dt",
    "tau_seconds_from_decay",
    "unreachable_threshold_warnings",
]


DEFAULT_LIF_DT_SECONDS = 1e-4
"""Timestep assumed when a graph declares none.

Hardcoded by ``snntorch.import_nir`` and mirrored by the training codegen in
``backend/app/routers/notebook.py``, so every trained artifact in the wild was
produced under it.  Changing this value would reinterpret every existing
checkpoint; declare a timestep on the graph instead (CNL ``with timestep``, or
the canvas "Network Timestep" field).
"""


class DiscretizationScheme(Enum):
    """How a continuous time constant becomes a per-step decay factor."""

    EULER = "euler"
    """``beta = 1 - dt/tau``.  Canonical -- matches ``snntorch.import_nir``."""

    EXACT = "exact"
    """``beta = exp(-dt/tau)``.  Available for comparison; not the default."""


@dataclass(frozen=True)
class LifDiscretization:
    """A LIF node's continuous parameters resolved onto a discrete timestep.

    Attributes
    ----------
    dt_seconds
        The timestep this discretization was computed at.
    tau_seconds
        Membrane time constant, in seconds, as stored on the node.
    beta
        Per-step membrane decay.  ``v[t+1] = beta*v[t] + ...``
    alpha
        Per-step *synaptic* decay for ``nir.CubaLIF`` (from ``tau_syn``);
        ``None`` for plain ``nir.LIF``, which has no synaptic filter.
    tau_steps
        ``tau/dt`` -- the time constant expressed in timesteps, for backends
        whose integrator takes ``dt = 1`` and a step-count time constant.
    input_scale
        ``r * dt/tau``.  The gain that a backend must either apply to its
        input current or divide out of its threshold.
    threshold
        ``v_threshold / input_scale`` -- the firing threshold in the rescaled
        voltage units that snnTorch's ``Leaky`` integrates in.
    v_threshold
        The raw, unscaled ``v_threshold`` from the node.
    v_leak
        Resting/leak potential from the node.
    r
        Membrane resistance from the node.
    warnings
        Human-readable diagnostics.  Empty when the node discretizes cleanly.
    dt_source
        Where ``dt_seconds`` came from: ``"node"``, ``"graph"`` or
        ``"default"``.  Surfaced so a warning can tell the user whether they
        chose the timestep or inherited it.
    """

    dt_seconds: float
    tau_seconds: float
    beta: float
    alpha: float | None
    tau_steps: float
    input_scale: float
    threshold: float
    v_threshold: float
    v_leak: float
    r: float
    warnings: tuple[str, ...]
    dt_source: str


# ---------------------------------------------------------------------------
# Scalar extraction
# ---------------------------------------------------------------------------


def _scalar(value: Any, default: float) -> float:
    """Mean-reduce a NIR parameter array to a scalar, falling back to ``default``.

    NIR stores per-neuron vectors; every backend below is scalar-parameterised,
    so a population with heterogeneous taus is approximated by its mean.  That
    approximation is called out in :func:`discretize_lif`'s warnings.
    """
    if value is None:
        return default
    try:
        arr = np.asarray(value, dtype=float)
        if arr.size == 0:
            return default
        mean = float(np.mean(arr))
    except (TypeError, ValueError):
        return default
    return mean if math.isfinite(mean) else default


def _is_heterogeneous(value: Any) -> bool:
    """True when a NIR parameter array holds more than one distinct value."""
    if value is None:
        return False
    try:
        arr = np.asarray(value, dtype=float)
    except (TypeError, ValueError):
        return False
    return bool(arr.size > 1 and not np.allclose(arr, arr.flat[0]))


# ---------------------------------------------------------------------------
# dt resolution
# ---------------------------------------------------------------------------


def resolve_dt(
    node: nir.NIRNode | None,
    graph: nir.NIRGraph | None = None,
    *,
    default: float = DEFAULT_LIF_DT_SECONDS,
) -> tuple[float, str]:
    """Resolve the timestep that applies to ``node``, with its provenance.

    Precedence, highest first:

    1. ``node.metadata["dt"]`` -- a per-node override, written by CNL's
       ``annotated with metadata dt``.
    2. ``graph.metadata["dt"]`` -- the network timestep, written by CNL's
       ``with timestep`` clause and by the canvas Network Settings field.
    3. ``default``.

    There is deliberately no request-level timestep in this chain.  Admitting
    one recreates the "two dt's disagree" bug this module exists to remove: a
    graph would then mean different things depending on which button ran it.

    Returns
    -------
    tuple[float, str]
        ``(dt_seconds, source)`` where source is ``"node"``, ``"graph"`` or
        ``"default"``.
    """
    for source, container in (("node", node), ("graph", graph)):
        metadata = getattr(container, "metadata", None)
        if not isinstance(metadata, dict) or "dt" not in metadata:
            continue
        try:
            candidate = float(metadata["dt"])
        except (TypeError, ValueError):
            continue
        if math.isfinite(candidate) and candidate > 0:
            return candidate, source
    return default, "default"


# ---------------------------------------------------------------------------
# Core conversions
# ---------------------------------------------------------------------------


def decay_from_tau(
    tau_seconds: float,
    dt_seconds: float,
    scheme: DiscretizationScheme = DiscretizationScheme.EULER,
) -> float:
    """Per-step decay factor for a time constant of ``tau_seconds``.

    ``EULER`` (default) returns ``1 - dt/tau``; ``EXACT`` returns
    ``exp(-dt/tau)``.  Both are undefined for a non-positive ``tau``, which
    raises rather than silently substituting a default -- a wrong-but-plausible
    decay is far harder to notice than an exception.

    Raises
    ------
    ValueError
        If ``tau_seconds`` or ``dt_seconds`` is not finite and positive, or if
        ``dt >= tau`` under the Euler scheme (see :func:`discretize_lif` for
        why that case is fatal rather than clamped).
    """
    if not math.isfinite(tau_seconds) or tau_seconds <= 0:
        raise ValueError(f"tau must be finite and > 0, got {tau_seconds!r}")
    if not math.isfinite(dt_seconds) or dt_seconds <= 0:
        raise ValueError(f"dt must be finite and > 0, got {dt_seconds!r}")

    if scheme is DiscretizationScheme.EXACT:
        return math.exp(-dt_seconds / tau_seconds)

    if dt_seconds >= tau_seconds:
        raise ValueError(
            f"dt ({dt_seconds}) >= tau ({tau_seconds}): forward Euler is "
            "unstable here — the membrane oscillates and diverges instead of "
            "decaying. Declare a network timestep well below the smallest "
            "time constant (dt/tau <= 0.1 is a good target)."
        )
    return 1.0 - (dt_seconds / tau_seconds)


def tau_seconds_from_decay(beta: float, dt_seconds: float) -> float:
    """Invert :func:`decay_from_tau` under the Euler scheme: ``dt / (1 - beta)``.

    Used when lowering a ``cnl.*`` node's dimensionless per-step decay back
    into a seconds-valued ``nir.LIF.tau``.  Pair every call with the ``dt``
    that ``beta`` was computed at -- ``beta`` alone does not determine ``tau``.

    Raises
    ------
    ValueError
        If ``beta`` is outside ``(0, 1)`` or ``dt_seconds`` is not positive.
    """
    if not math.isfinite(beta) or not 0.0 < beta < 1.0:
        raise ValueError(f"beta must lie strictly in (0, 1), got {beta!r}")
    if not math.isfinite(dt_seconds) or dt_seconds <= 0:
        raise ValueError(f"dt must be finite and > 0, got {dt_seconds!r}")
    return dt_seconds / (1.0 - beta)


# ---------------------------------------------------------------------------
# Node-level entry point
# ---------------------------------------------------------------------------


def discretize_lif(
    node: nir.NIRNode,
    *,
    graph: nir.NIRGraph | None = None,
    dt: float | None = None,
    scheme: DiscretizationScheme = DiscretizationScheme.EULER,
) -> LifDiscretization:
    """Resolve a ``nir.LIF`` or ``nir.CubaLIF`` onto a discrete timestep.

    Handles both node types behind one entry point so callers cannot repeat
    the long-standing mistake of reading ``.tau`` off a ``nir.CubaLIF`` (which
    has ``tau_mem``/``tau_syn`` and no ``.tau``) and silently falling back to a
    hardcoded decay.

    Parameters
    ----------
    node
        A ``nir.LIF`` or ``nir.CubaLIF``.
    graph
        Optional owning graph, consulted for ``metadata["dt"]``.
    dt
        Explicit timestep in seconds.  Overrides node and graph metadata; use
        it only where the caller genuinely owns the timestep.
    scheme
        Discretization scheme.  Leave at the default.

    Raises
    ------
    TypeError
        If ``node`` is neither ``nir.LIF`` nor ``nir.CubaLIF``.
    ValueError
        If the resolved ``tau`` or ``dt`` is non-positive, or ``dt >= tau``.
    """
    if isinstance(node, nir.CubaLIF):
        tau_raw = getattr(node, "tau_mem", None)
        tau_syn_raw = getattr(node, "tau_syn", None)
    elif isinstance(node, nir.LIF):
        tau_raw = getattr(node, "tau", None)
        tau_syn_raw = None
    else:
        raise TypeError(f"discretize_lif expects nir.LIF or nir.CubaLIF, got {type(node).__name__}")

    if dt is not None:
        if not math.isfinite(dt) or dt <= 0:
            raise ValueError(f"dt must be finite and > 0, got {dt!r}")
        dt_seconds, dt_source = float(dt), "explicit"
    else:
        dt_seconds, dt_source = resolve_dt(node, graph)

    warnings: list[str] = []

    tau_seconds = _scalar(tau_raw, 0.0)
    if tau_seconds <= 0:
        # Overwhelmingly this is a graph compiled from a CNL spec, which records
        # a neuron's parameters as a shape rather than values, so compile_to_nir
        # zero-fills them. The trained .nir written by the NIR Exporter is the
        # only artifact carrying the real numbers -- name it, rather than
        # blaming a canvas field the user probably did set.
        raise ValueError(
            f"This network has no usable time constant (tau = {tau_seconds:g}), "
            "so its neurons cannot leak or fire. A CNL spec stores time "
            "constants as a shape, not a value, so the trained network file has "
            "to supply them: add a NIR Exporter node to your Training canvas and "
            "run the pipeline, then run this target again."
        )
    if _is_heterogeneous(tau_raw):
        warnings.append(
            "Per-neuron time constants differ; the whole population is "
            f"approximated with the mean tau = {tau_seconds:g} s."
        )

    r = _scalar(getattr(node, "r", None), 1.0) or 1.0
    v_leak = _scalar(getattr(node, "v_leak", None), 0.0)
    v_threshold = _scalar(getattr(node, "v_threshold", None), 1.0) or 1.0

    beta = decay_from_tau(tau_seconds, dt_seconds, scheme)

    alpha: float | None = None
    if tau_syn_raw is not None:
        tau_syn = _scalar(tau_syn_raw, 0.0)
        if tau_syn > 0:
            alpha = decay_from_tau(tau_syn, dt_seconds, scheme)
        else:
            warnings.append(
                "Synaptic time constant is not positive; synaptic filtering "
                "is disabled for this population."
            )

    input_scale = r * dt_seconds / tau_seconds
    threshold = v_threshold / input_scale if abs(input_scale - 1.0) > 1e-6 else v_threshold

    # Upstream snntorch.import_nir asserts v_leak == 0 before applying the
    # threshold rescale, because the change of variables that justifies it
    # assumes a leak of zero. Warn rather than raise: a small non-zero leak is
    # still runnable and refusing to simulate is the worse failure.
    if abs(v_leak) > 1e-12:
        warnings.append(
            f"Leak voltage is {v_leak:g}, not 0. The firing threshold is "
            "rescaled assuming zero leak, so spike timing will drift from the "
            "trained model."
        )

    if dt_seconds / tau_seconds > 0.1:
        warnings.append(
            f"Timestep {dt_seconds:g} s is large relative to tau "
            f"{tau_seconds:g} s (dt/tau = {dt_seconds / tau_seconds:.2f}); "
            "forward Euler loses accuracy above ~0.1."
        )

    return LifDiscretization(
        dt_seconds=dt_seconds,
        tau_seconds=tau_seconds,
        beta=beta,
        alpha=alpha,
        tau_steps=tau_seconds / dt_seconds,
        input_scale=input_scale,
        threshold=threshold,
        v_threshold=v_threshold,
        v_leak=v_leak,
        r=r,
        warnings=tuple(warnings),
        dt_source=dt_source,
    )


def unreachable_threshold_warnings(
    graph: nir.NIRGraph,
    cutoff: float = 50.0,
) -> list[str]:
    """Name LIF populations whose effective firing threshold looks unreachable.

    A network authored with a biologically-typical ``tau`` (say 0.02 s) and a
    nominal threshold of 1.0, but no declared network timestep, discretizes at
    ``dt = 1e-4`` into an effective threshold of 200. That is arithmetically
    correct and practically dead: realistically-scaled input never gets near it,
    so the run comes back empty for a reason the raster itself cannot show.

    Returns one message per suspicious population, empty when none are found.
    Purely advisory -- it never raises and never changes how a graph runs.
    """
    messages: list[str] = []
    for name, node in graph.nodes.items():
        if not isinstance(node, nir.LIF | nir.CubaLIF):
            continue
        try:
            d = discretize_lif(node, graph=graph)
        except (TypeError, ValueError):
            continue  # a node that cannot discretize is reported by the backend
        if d.threshold <= cutoff:
            continue
        suggested = _suggested_timestep(d.tau_seconds)
        messages.append(
            f"'{name}': firing threshold is effectively {d.threshold:.1f} at a "
            f"timestep of {d.dt_seconds:g} s (tau = {d.tau_seconds:g} s), which "
            "realistically-scaled input is unlikely to reach, so this population "
            "may never spike. Set the network timestep to about "
            f"{suggested:g} s, or lower the firing threshold."
        )
    return messages


def _suggested_timestep(tau_seconds: float) -> float:
    """A timestep that keeps forward Euler accurate: about tau/10, rounded down.

    Rounding to one significant figure keeps the number something a person would
    plausibly type into the Network Settings field.
    """
    raw = tau_seconds / 10.0
    if raw <= 0:
        return DEFAULT_LIF_DT_SECONDS
    exponent = math.floor(math.log10(raw))
    return float(math.floor(raw / (10**exponent)) * (10**exponent))


def lava_lif_parameters(
    tau_seconds: float,
    dt_seconds: float,
    r: float = 1.0,
    v_threshold: float = 1.0,
) -> tuple[float, float, float]:
    """Map a LIF onto Lava's ``LIF(du, dv, vth)``.

    Lava's ``dv`` is the per-step *voltage decay fraction* -- ``dt/tau``, the
    complement of the ``beta`` every other backend uses. ``du`` is the synaptic
    current decay; ``1.0`` means no synaptic filtering, correct for a plain LIF.

    The threshold is divided by ``input_scale`` for the same reason snnTorch's
    is: Lava's LIF, like snnTorch's Leaky, applies no ``r*dt/tau`` gain to its
    input current.

    Lives here rather than in either Lava caller because both the in-process
    adapter and the runtime payload sent to the remote worker need it, and they
    must not disagree.

    Raises
    ------
    ValueError
        Propagated from :func:`decay_from_tau` for an unusable tau/dt pair.
    """
    beta = decay_from_tau(tau_seconds, dt_seconds)
    input_scale = r * dt_seconds / tau_seconds
    threshold = v_threshold / input_scale if abs(input_scale - 1.0) > 1e-6 else v_threshold
    return 1.0, 1.0 - beta, threshold
