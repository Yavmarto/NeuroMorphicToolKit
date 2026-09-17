"""nir library runtime compatibility shim.

The ``nir`` package has introduced new keyword arguments over time that are
not present in older releases that may be installed on remote hardware
targets (e.g. Raspberry Pi boards running the neurosim backend).

Specifically:

* ``nir.NIRGraph(…, type_check=False)`` — added in nir ≥ 1.0.0.
  Older builds raise ``TypeError: __init__() got an unexpected keyword
  argument 'type_check'``.
* ``nir.LIF(…, v_reset=…)`` / ``nir.IF(…, v_reset=…)`` /
  ``nir.CubaLIF(…, v_reset=…)`` — added alongside ``type_check``.
  Older builds raise the same error.

Both flags are detected once at module import so every call-site in the
codebase can use the helper functions below rather than sprinkling
``try/except`` blocks or version-string comparisons everywhere.
"""

from __future__ import annotations

import inspect
import os
from typing import Any

import nir
import numpy as np

# ---------------------------------------------------------------------------
# Capability flags — evaluated once at import time
# ---------------------------------------------------------------------------

_NIR_GRAPH_PARAMS: frozenset[str] = frozenset(
    inspect.signature(nir.NIRGraph).parameters.keys()
)
_NIR_LIF_PARAMS: frozenset[str] = frozenset(
    inspect.signature(nir.LIF).parameters.keys()
)

#: ``True`` when the installed nir build accepts the ``type_check`` kwarg.
NIR_HAS_TYPE_CHECK: bool = "type_check" in _NIR_GRAPH_PARAMS

#: ``True`` when the installed nir build accepts the ``v_reset`` kwarg on
#: LIF/IF/CubaLIF nodes.
NIR_HAS_V_RESET: bool = "v_reset" in _NIR_LIF_PARAMS

_NIR_INPUT_PARAMS: frozenset[str] = frozenset(
    inspect.signature(nir.Input).parameters.keys()
)
_NIR_OUTPUT_PARAMS: frozenset[str] = frozenset(
    inspect.signature(nir.Output).parameters.keys()
)
_NIR_FLATTEN_PARAMS: frozenset[str] = frozenset(
    inspect.signature(nir.Flatten).parameters.keys()
)

#: ``True`` when the installed nir build accepts the ``metadata`` kwarg on Input nodes.
NIR_HAS_INPUT_METADATA: bool = "metadata" in _NIR_INPUT_PARAMS

#: ``True`` when the installed nir build accepts the ``metadata`` kwarg on Output nodes.
NIR_HAS_OUTPUT_METADATA: bool = "metadata" in _NIR_OUTPUT_PARAMS

#: ``True`` when the installed nir build requires/accepts ``input_type`` on Flatten nodes.
NIR_FLATTEN_HAS_INPUT_TYPE: bool = "input_type" in _NIR_FLATTEN_PARAMS

#: ``True`` when the installed nir build accepts the ``metadata`` kwarg on Flatten nodes.
NIR_HAS_FLATTEN_METADATA: bool = "metadata" in _NIR_FLATTEN_PARAMS

_NIR_READ_PARAMS: frozenset[str] = (
    frozenset(inspect.signature(nir.read).parameters.keys())
    if hasattr(nir, "read")
    else frozenset()
)

#: ``True`` when ``nir.read()`` itself accepts (and passes) ``type_check``
#: into the deserialized data dict.  When this is ``True`` but
#: ``NIR_HAS_TYPE_CHECK`` is ``False``, ``nir.read()`` will always fail.
NIR_READ_HAS_TYPE_CHECK: bool = "type_check" in _NIR_READ_PARAMS

# These are imported at module level so tests can patch them at the
# neurocnl._nir_compat namespace.  They remain optional at runtime.
try:
    import h5py
    from nir.serialization import hdf2dict
except ImportError:  # pragma: no cover
    h5py = None
    hdf2dict = None


# ---------------------------------------------------------------------------
# Helper: read a NIR HDF5 file with nir-version-mismatch tolerance
# ---------------------------------------------------------------------------


def safe_nir_read(filename: str | os.PathLike[str]) -> nir.NIRGraph:
    """Read a ``.nir`` HDF5 file, tolerating nir version mismatches.

    On nir builds where ``nir.read()`` internally injects ``type_check``
    into the deserialized data dict but ``NIRGraph.__init__`` does not
    accept it (a transitional build inconsistency), this function falls
    back to the lower-level ``nir`` internals to reconstruct the graph
    without passing ``type_check``.

    Parameters
    ----------
    filename:
        Path to a ``.nir`` (HDF5) file.

    Raises
    ------
    TypeError
        Re-raised verbatim if ``nir.read()`` fails for any reason other
        than a ``type_check`` kwarg mismatch.
    RuntimeError
        Raised when the ``type_check`` mismatch is detected but the
        fallback HDF5 internals are not accessible (e.g. h5py not
        installed or nir internals changed).
    """
    try:
        return nir.read(str(filename))
    except TypeError as exc:
        if "type_check" not in str(exc):
            raise
        # Mismatch: nir.read() serialization layer passes type_check but
        # NIRGraph constructor rejects it.  Fall back to manual HDF5 read.
        try:
            if h5py is None or hdf2dict is None:
                raise ImportError("h5py or nir.serialization.hdf2dict unavailable")
            with h5py.File(str(filename), "r") as _f:
                _data = hdf2dict(_f["node"])
            return nir.dict2NIRNode(_data)
        except (ImportError, AttributeError, KeyError):
            raise RuntimeError(
                "nir version incompatibility: nir.read() passes 'type_check' "
                "to NIRGraph but the installed nir does not accept it. "
                "Please reinstall nir>=1.0.0 consistently. "
                f"Original error: {exc}"
            ) from exc


# ---------------------------------------------------------------------------
# Helper: build NIRGraph with optional type_check suppression
# ---------------------------------------------------------------------------


def make_nir_graph(
    nodes: dict[str, Any],
    edges: list[tuple[str, str]],
    *,
    skip_type_check: bool = True,
    **kwargs: Any,
) -> nir.NIRGraph:
    """Construct a :class:`nir.NIRGraph`, suppressing type-checking when
    the installed nir version supports the ``type_check`` keyword.

    On older nir versions that lack ``type_check`` the graph is returned
    without the argument (type-checking will run and may raise for graphs
    with missing ``input_type``/``output_type`` on non-boundary nodes —
    this is the same behaviour callers got before this shim existed).

    Parameters
    ----------
    nodes:
        Mapping of node name → NIR node.
    edges:
        List of ``(source_name, target_name)`` tuples.
    skip_type_check:
        When ``True`` (default) and the installed nir supports the flag,
        pass ``type_check=False`` to avoid NIR's strict shape validation
        on intermediate nodes that may not yet have inferred types.
    **kwargs:
        Additional keyword arguments forwarded verbatim to
        ``nir.NIRGraph``.
    """
    if skip_type_check and NIR_HAS_TYPE_CHECK:
        kwargs["type_check"] = False
    try:
        return nir.NIRGraph(nodes=nodes, edges=edges, **kwargs)
    except TypeError as exc:
        if "type_check" not in str(exc):
            raise
        # NIR_HAS_TYPE_CHECK detection was wrong for this build.
        # Strip type_check and retry without it.
        kwargs.pop("type_check", None)
        return nir.NIRGraph(nodes=nodes, edges=edges, **kwargs)


# ---------------------------------------------------------------------------
# Helper: build nir.LIF with optional v_reset
# ---------------------------------------------------------------------------


def make_nir_lif(
    *,
    tau: np.ndarray[Any, Any],
    r: np.ndarray[Any, Any],
    v_leak: np.ndarray[Any, Any],
    v_threshold: np.ndarray[Any, Any],
    v_reset: np.ndarray[Any, Any] | None = None,
    **kwargs: Any,
) -> nir.LIF:
    """Construct a :class:`nir.LIF`, omitting ``v_reset`` on older nir builds.

    Parameters
    ----------
    tau, r, v_leak, v_threshold:
        Required LIF parameters.
    v_reset:
        Optional reset potential array.  Forwarded only when the installed
        nir version accepts the ``v_reset`` keyword; silently dropped
        otherwise.
    **kwargs:
        Additional keyword arguments forwarded verbatim to ``nir.LIF``.
    """
    if v_reset is not None and NIR_HAS_V_RESET:
        kwargs["v_reset"] = v_reset
    return nir.LIF(tau=tau, r=r, v_leak=v_leak, v_threshold=v_threshold, **kwargs)


# ---------------------------------------------------------------------------
# Helper: build nir.IF with optional v_reset
# ---------------------------------------------------------------------------


def make_nir_if(
    *,
    r: np.ndarray[Any, Any],
    v_threshold: np.ndarray[Any, Any],
    v_reset: np.ndarray[Any, Any] | None = None,
    **kwargs: Any,
) -> nir.IF:
    """Construct a :class:`nir.IF`, omitting ``v_reset`` on older nir builds."""
    if v_reset is not None and NIR_HAS_V_RESET:
        kwargs["v_reset"] = v_reset
    return nir.IF(r=r, v_threshold=v_threshold, **kwargs)


# ---------------------------------------------------------------------------
# Helper: build nir.CubaLIF with optional v_reset
# ---------------------------------------------------------------------------


def make_nir_cubalif(
    *,
    tau_syn: np.ndarray[Any, Any],
    tau_mem: np.ndarray[Any, Any],
    r: np.ndarray[Any, Any],
    v_leak: np.ndarray[Any, Any],
    v_threshold: np.ndarray[Any, Any],
    v_reset: np.ndarray[Any, Any] | None = None,
    w_in: np.ndarray[Any, Any] | None = None,
    **kwargs: Any,
) -> nir.CubaLIF:
    """Construct a :class:`nir.CubaLIF`, omitting ``v_reset`` on older nir builds."""
    if v_reset is not None and NIR_HAS_V_RESET:
        kwargs["v_reset"] = v_reset
    if w_in is not None:
        kwargs["w_in"] = w_in
    return nir.CubaLIF(
        tau_syn=tau_syn,
        tau_mem=tau_mem,
        r=r,
        v_leak=v_leak,
        v_threshold=v_threshold,
        **kwargs,
    )


# ---------------------------------------------------------------------------
# Helper: build nir.Input with optional metadata
# ---------------------------------------------------------------------------


def make_nir_input(
    *,
    input_type: dict[str, np.ndarray[Any, Any]],
    **kwargs: Any,
) -> nir.Input:
    """Construct a :class:`nir.Input`, omitting ``metadata`` on older nir builds."""
    if "metadata" in kwargs and not NIR_HAS_INPUT_METADATA:
        kwargs.pop("metadata")
    return nir.Input(input_type=input_type, **kwargs)


# ---------------------------------------------------------------------------
# Helper: build nir.Output with optional metadata
# ---------------------------------------------------------------------------


def make_nir_output(
    *,
    output_type: dict[str, np.ndarray[Any, Any]],
    **kwargs: Any,
) -> nir.Output:
    """Construct a :class:`nir.Output`, omitting ``metadata`` on older nir builds."""
    if "metadata" in kwargs and not NIR_HAS_OUTPUT_METADATA:
        kwargs.pop("metadata")
    return nir.Output(output_type=output_type, **kwargs)


# ---------------------------------------------------------------------------
# Helper: build nir.Flatten with optional input_type/metadata
# ---------------------------------------------------------------------------


def make_nir_flatten(
    *,
    input_type: dict[str, np.ndarray[Any, Any]] | None = None,
    start_dim: int = 1,
    end_dim: int = -1,
    **kwargs: Any,
) -> nir.Flatten:
    """Construct a :class:`nir.Flatten` across nir constructor variants."""
    if "metadata" in kwargs and not NIR_HAS_FLATTEN_METADATA:
        kwargs.pop("metadata")
    if NIR_FLATTEN_HAS_INPUT_TYPE:
        if input_type is None:
            input_type = {"input": np.asarray([1], dtype=int)}
        kwargs["input_type"] = input_type
    return nir.Flatten(start_dim=start_dim, end_dim=end_dim, **kwargs)


# ---------------------------------------------------------------------------
# Helper: generic node-class ``metadata`` kwarg detection, and nir.Linear
# ---------------------------------------------------------------------------


def nir_node_accepts_metadata(node_cls: Any) -> bool:
    """Return ``True`` when ``node_cls``'s constructor accepts ``metadata``.

    Unlike the per-node-type ``NIR_HAS_*_METADATA`` flags above (evaluated
    once at import time), this is a general-purpose, call-time check so it
    works for any nir node class — including ones without a dedicated flag —
    and so callers/tests can rely on it reflecting the *current* installed
    nir build rather than a cached value.
    """
    try:
        return "metadata" in inspect.signature(node_cls).parameters
    except (TypeError, ValueError):
        return False


#: ``True`` when the installed nir build accepts the ``metadata`` kwarg on
#: Linear nodes.
NIR_HAS_LINEAR_METADATA: bool = nir_node_accepts_metadata(nir.Linear)


def make_nir_node(
    node_cls: Any, *, metadata: dict[str, Any] | None = None, **kwargs: Any
) -> Any:
    """Construct any nir node class, omitting ``metadata`` when unsupported.

    ``node_cls`` is called with ``metadata`` included only when
    :func:`nir_node_accepts_metadata` reports support for it, so this
    delegates safely to older nir builds that lack the kwarg entirely.
    """
    if metadata is not None and nir_node_accepts_metadata(node_cls):
        kwargs["metadata"] = metadata
    return node_cls(**kwargs)


def make_nir_linear(
    *,
    weight: np.ndarray[Any, Any],
    metadata: dict[str, Any] | None = None,
    **kwargs: Any,
) -> nir.Linear:
    """Construct a :class:`nir.Linear`, omitting ``metadata`` on older nir builds."""
    return make_nir_node(nir.Linear, weight=weight, metadata=metadata, **kwargs)
