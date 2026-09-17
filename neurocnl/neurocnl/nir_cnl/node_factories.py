"""Per-Primitive node construction for the NIR-Native CNL compiler.

Extracted from :mod:`neurocnl.nir_cnl.compiler` (Stage 6 refactor). Each
``_build_*`` function is a pure ``(record) -> nir.NIRNode`` builder; the
compiler's per-node materialisation phase dispatches through
:data:`_BUILDERS`. Behaviour, diagnostics, and error codes are unchanged
by this move — see the compiler's module docstring for the full
materialisation contract.
"""

from __future__ import annotations

from typing import Any

import nir
import numpy as np

from neurocnl._nir_compat import make_nir_flatten
from neurocnl.nir_cnl.grammar_tables import parameter_phrases
from neurocnl.nir_cnl.ir_types import (
    ArraySpec,
    ArrayValues,
    NIREdgeRecord,
    NIRNodeRecord,
)
from neurocnl.nir_cnl.param_resolution import (
    _MISSING,
    _missing_param_error,
    _raise_single,
    _resolve_param,
    _scalar,
)
from neurocnl.runtime.cnl_nodes import Leaky as CnlLeaky
from neurocnl.runtime.cnl_nodes import RLeaky as CnlRLeaky
from neurocnl.runtime.cnl_nodes import RSynaptic as CnlRSynaptic
from neurocnl.runtime.cnl_nodes import Synaptic as CnlSynaptic

__all__ = ["_BUILDERS", "_build_flatten", "_flatten_input_shape"]


def _io_shape_dict(
    shape: tuple[int, ...], *, port_name: str
) -> dict[str, np.ndarray[Any, Any]]:
    """Wrap an ``int_tuple`` as the ``{port_name: shape_array}`` form
    expected by ``nir.Input.input_type`` / ``nir.Output.output_type``."""
    return {port_name: np.asarray(shape, dtype=int)}


# Each builder is a pure function ``(record) -> nir.NIRNode``.


def _build_input(record: NIRNodeRecord) -> nir.Input:
    # Directly read the parsed int-tuple value to bypass the
    # grammar table's ``rank=1`` constraint. The reference fixtures
    # include image-input graphs whose ``Input.input_type`` is a
    # 3-tuple ``(channels, height, width)`` (cnn_sinabs.nir), and
    # the renderer round-trips the original tuple verbatim. The
    # ``int_tuple`` parser path already validates entries are
    # non-negative integers.
    raw = record.params.get("input_type", _MISSING)
    if raw is _MISSING:
        spec = parameter_phrases["Input"]["input_type"]
        raise _missing_param_error(
            primitive="Input", arg_name="input_type", spec=spec, line=record.line
        )
    if isinstance(raw, ArraySpec | ArrayValues):
        _raise_single(
            code="shape_for_scalar",
            message=(
                "Parameter 'input_type' on 'Input' expects an integer tuple, "
                "not a shape declaration."
            ),
            line=record.line,
        )
    if not isinstance(raw, tuple):
        _raise_single(
            code="invalid_value",
            message=(
                f"Parameter 'input_type' on 'Input' expects an integer tuple, "
                f"got {type(raw).__name__!s}."
            ),
            line=record.line,
        )
    shape = tuple(int(x) for x in raw)
    return nir.Input(input_type=_io_shape_dict(shape, port_name="input"))


def _build_output(record: NIRNodeRecord) -> nir.Output:
    # Same rank-relaxation as ``_build_input``; see that builder for
    # the rationale tied to image-output reference fixtures.
    raw = record.params.get("output_type", _MISSING)
    if raw is _MISSING:
        spec = parameter_phrases["Output"]["output_type"]
        raise _missing_param_error(
            primitive="Output", arg_name="output_type", spec=spec, line=record.line
        )
    if isinstance(raw, ArraySpec | ArrayValues):
        _raise_single(
            code="shape_for_scalar",
            message=(
                "Parameter 'output_type' on 'Output' expects an integer "
                "tuple, not a shape declaration."
            ),
            line=record.line,
        )
    if not isinstance(raw, tuple):
        _raise_single(
            code="invalid_value",
            message=(
                f"Parameter 'output_type' on 'Output' expects an integer "
                f"tuple, got {type(raw).__name__!s}."
            ),
            line=record.line,
        )
    shape = tuple(int(x) for x in raw)
    return nir.Output(output_type=_io_shape_dict(shape, port_name="output"))


def _build_if(record: NIRNodeRecord) -> nir.IF:
    table = parameter_phrases["IF"]
    r = _resolve_param(record, "r", table["r"])
    v_threshold = _resolve_param(record, "v_threshold", table["v_threshold"])
    return nir.IF(r=r, v_threshold=v_threshold)


def _build_lif(record: NIRNodeRecord) -> nir.LIF:
    table = parameter_phrases["LIF"]
    return nir.LIF(
        tau=_resolve_param(record, "tau", table["tau"]),
        r=_resolve_param(record, "r", table["r"]),
        v_leak=_resolve_param(record, "v_leak", table["v_leak"]),
        v_threshold=_resolve_param(record, "v_threshold", table["v_threshold"]),
    )


def _build_li(record: NIRNodeRecord) -> nir.LI:
    table = parameter_phrases["LI"]
    return nir.LI(
        tau=_resolve_param(record, "tau", table["tau"]),
        r=_resolve_param(record, "r", table["r"]),
        v_leak=_resolve_param(record, "v_leak", table["v_leak"]),
    )


def _build_cubalif(record: NIRNodeRecord) -> nir.CubaLIF:
    table = parameter_phrases["CubaLIF"]
    kwargs: dict[str, np.ndarray[Any, Any]] = {
        "tau_syn": _resolve_param(record, "tau_syn", table["tau_syn"]),
        "tau_mem": _resolve_param(record, "tau_mem", table["tau_mem"]),
        "r": _resolve_param(record, "r", table["r"]),
        "v_leak": _resolve_param(record, "v_leak", table["v_leak"]),
        "v_threshold": _resolve_param(record, "v_threshold", table["v_threshold"]),
    }
    w_in = _resolve_param(record, "w_in", table["w_in"])
    if w_in is not _MISSING:
        kwargs["w_in"] = w_in
    return nir.CubaLIF(**kwargs)


def _build_cubali(record: NIRNodeRecord) -> nir.CubaLI:
    table = parameter_phrases["CubaLI"]
    kwargs: dict[str, np.ndarray[Any, Any]] = {
        "tau_syn": _resolve_param(record, "tau_syn", table["tau_syn"]),
        "tau_mem": _resolve_param(record, "tau_mem", table["tau_mem"]),
        "r": _resolve_param(record, "r", table["r"]),
        "v_leak": _resolve_param(record, "v_leak", table["v_leak"]),
    }
    w_in = _resolve_param(record, "w_in", table["w_in"])
    if w_in is not _MISSING:
        kwargs["w_in"] = w_in
    return nir.CubaLI(**kwargs)


def _build_i(record: NIRNodeRecord) -> nir.I:
    table = parameter_phrases["I"]
    return nir.I(r=_resolve_param(record, "r", table["r"]))


def _build_linear(record: NIRNodeRecord) -> nir.Linear:
    table = parameter_phrases["Linear"]
    weight = _resolve_param(record, "weight", table["weight"], expected_rank=2)
    return nir.Linear(weight=weight)


def _build_affine(record: NIRNodeRecord) -> nir.Affine:
    table = parameter_phrases["Affine"]
    weight = _resolve_param(record, "weight", table["weight"], expected_rank=2)

    # Auto-bias derivation (Requirement 11.4): when the user supplied a
    # ``weight matrix`` clause and omitted the ``bias vector`` clause,
    # synthesise zeros of length ``weight.shape[0]``. An explicit bias
    # always wins (Requirement 11.5).
    bias_raw = record.params.get("bias", _MISSING)
    if bias_raw is _MISSING:
        bias = np.zeros((weight.shape[0],), dtype=float)
    else:
        bias = _resolve_param(record, "bias", table["bias"])
    return nir.Affine(weight=weight, bias=bias)


def _build_scale(record: NIRNodeRecord) -> nir.Scale:
    table = parameter_phrases["Scale"]
    return nir.Scale(scale=_resolve_param(record, "scale", table["scale"]))


def _build_conv1d(record: NIRNodeRecord) -> nir.Conv1d:
    table = parameter_phrases["Conv1d"]
    weight = _resolve_param(record, "weight", table["weight"], expected_rank=3)
    bias = _resolve_param(record, "bias", table["bias"])

    # Conv1d uses scalar (rank-1 → unwrapped) values for stride /
    # padding / dilation. The grammar table tags these as int_tuple
    # rank=1; the resolver returns a length-1 tuple, which we unwrap.
    stride_t = _resolve_param(record, "stride", table["stride"], expected_rank=1)
    padding_t = _resolve_param(record, "padding", table["padding"], expected_rank=1)
    dilation_t = _resolve_param(record, "dilation", table["dilation"], expected_rank=1)
    groups = _resolve_param(record, "groups", table["groups"])
    input_shape = _resolve_param(record, "input_shape", table["input_shape"])

    return nir.Conv1d(
        input_shape=int(input_shape),
        weight=weight,
        stride=int(stride_t[0]),
        padding=int(padding_t[0]),
        dilation=int(dilation_t[0]),
        groups=int(groups),
        bias=bias,
    )


def _build_conv2d(record: NIRNodeRecord) -> nir.Conv2d:
    table = parameter_phrases["Conv2d"]
    weight = _resolve_param(record, "weight", table["weight"], expected_rank=4)

    stride = _resolve_param(record, "stride", table["stride"], expected_rank=2)
    padding = _resolve_param(record, "padding", table["padding"], expected_rank=2)
    dilation = _resolve_param(record, "dilation", table["dilation"], expected_rank=2)
    groups = _resolve_param(record, "groups", table["groups"])
    input_shape = _resolve_param(
        record, "input_shape", table["input_shape"], expected_rank=2
    )

    # Auto-bias (Requirement 11.3): zeros vector keyed off the kernel's
    # out-channel dimension when the user omitted the bias clause.
    bias_raw = record.params.get("bias", _MISSING)
    if bias_raw is _MISSING:
        bias = np.zeros((weight.shape[0],), dtype=float)
    else:
        bias = _resolve_param(record, "bias", table["bias"])

    return nir.Conv2d(
        input_shape=tuple(int(x) for x in input_shape),
        weight=weight,
        stride=tuple(int(x) for x in stride),
        padding=tuple(int(x) for x in padding),
        dilation=tuple(int(x) for x in dilation),
        groups=int(groups),
        bias=bias,
    )


def _build_avgpool2d(record: NIRNodeRecord) -> nir.AvgPool2d:
    table = parameter_phrases["AvgPool2d"]
    kernel_size = _resolve_param(
        record, "kernel_size", table["kernel_size"], expected_rank=2
    )
    stride = _resolve_param(record, "stride", table["stride"], expected_rank=2)
    padding = _resolve_param(record, "padding", table["padding"], expected_rank=2)
    return nir.AvgPool2d(
        kernel_size=np.asarray(kernel_size, dtype=int),
        stride=np.asarray(stride, dtype=int),
        padding=np.asarray(padding, dtype=int),
    )


def _build_sumpool2d(record: NIRNodeRecord) -> nir.SumPool2d:
    table = parameter_phrases["SumPool2d"]
    kernel_size = _resolve_param(
        record, "kernel_size", table["kernel_size"], expected_rank=2
    )
    stride = _resolve_param(record, "stride", table["stride"], expected_rank=2)
    padding = _resolve_param(record, "padding", table["padding"], expected_rank=2)
    return nir.SumPool2d(
        kernel_size=np.asarray(kernel_size, dtype=int),
        stride=np.asarray(stride, dtype=int),
        padding=np.asarray(padding, dtype=int),
    )


def _build_flatten(
    record: NIRNodeRecord, input_shape: tuple[int, ...] | None = None
) -> nir.Flatten:
    table = parameter_phrases["Flatten"]
    kwargs: dict[str, int] = {}
    start_dim = _resolve_param(record, "start_dim", table["start_dim"])
    if start_dim is not _MISSING:
        kwargs["start_dim"] = int(start_dim)
    end_dim = _resolve_param(record, "end_dim", table["end_dim"])
    if end_dim is not _MISSING:
        kwargs["end_dim"] = int(end_dim)
    if input_shape is None:
        serialized_shape = record.metadata.get("nmtk_flatten_input_shape")
        if isinstance(serialized_shape, str):
            try:
                input_shape = tuple(
                    int(dimension) for dimension in serialized_shape.split(",")
                )
            except ValueError:
                input_shape = None
    input_type = None
    if input_shape is not None:
        input_type = {"input": np.asarray(input_shape, dtype=int)}
    return make_nir_flatten(input_type=input_type, **kwargs)


def _build_delay(record: NIRNodeRecord) -> nir.Delay:
    table = parameter_phrases["Delay"]
    return nir.Delay(delay=_resolve_param(record, "delay", table["delay"]))


def _build_threshold(record: NIRNodeRecord) -> nir.Threshold:
    table = parameter_phrases["Threshold"]
    return nir.Threshold(
        threshold=_resolve_param(record, "threshold", table["threshold"])
    )


def _build_synaptic(record: NIRNodeRecord) -> CnlSynaptic:
    table = parameter_phrases["Synaptic"]
    return CnlSynaptic(
        n_neurons=_resolve_param(record, "n_neurons", table["n_neurons"]),
        alpha=_scalar(_resolve_param(record, "alpha", table["alpha"])),
        beta=_scalar(_resolve_param(record, "beta", table["beta"])),
        threshold=_scalar(_resolve_param(record, "threshold", table["threshold"])),
    )


def _build_rsynaptic(record: NIRNodeRecord) -> CnlRSynaptic:
    table = parameter_phrases["RSynaptic"]
    return CnlRSynaptic(
        n_neurons=_resolve_param(record, "n_neurons", table["n_neurons"]),
        alpha=_scalar(_resolve_param(record, "alpha", table["alpha"])),
        beta=_scalar(_resolve_param(record, "beta", table["beta"])),
        threshold=_scalar(_resolve_param(record, "threshold", table["threshold"])),
    )


def _build_leaky(record: NIRNodeRecord) -> CnlLeaky:
    table = parameter_phrases["Leaky"]
    return CnlLeaky(
        n_neurons=_resolve_param(record, "n_neurons", table["n_neurons"]),
        beta=_scalar(_resolve_param(record, "beta", table["beta"])),
        threshold=_scalar(_resolve_param(record, "threshold", table["threshold"])),
    )


def _build_rleaky(record: NIRNodeRecord) -> CnlRLeaky:
    table = parameter_phrases["RLeaky"]
    return CnlRLeaky(
        n_neurons=_resolve_param(record, "n_neurons", table["n_neurons"]),
        beta=_scalar(_resolve_param(record, "beta", table["beta"])),
        threshold=_scalar(_resolve_param(record, "threshold", table["threshold"])),
    )


_BUILDERS: dict[str, Any] = {
    "Input": _build_input,
    "Output": _build_output,
    "IF": _build_if,
    "LIF": _build_lif,
    "LI": _build_li,
    "CubaLIF": _build_cubalif,
    "CubaLI": _build_cubali,
    "I": _build_i,
    "Linear": _build_linear,
    "Affine": _build_affine,
    "Scale": _build_scale,
    "Conv1d": _build_conv1d,
    "Conv2d": _build_conv2d,
    "AvgPool2d": _build_avgpool2d,
    "SumPool2d": _build_sumpool2d,
    "Flatten": _build_flatten,
    "Delay": _build_delay,
    "Threshold": _build_threshold,
    "Synaptic": _build_synaptic,
    "RSynaptic": _build_rsynaptic,
    "Leaky": _build_leaky,
    "RLeaky": _build_rleaky,
}


def _flatten_input_shape(
    record: NIRNodeRecord,
    edge_records: list[NIREdgeRecord],
    shapes: dict[str, tuple[int, ...]],
) -> tuple[int, ...]:
    sources = [edge.src for edge in edge_records if edge.target == record.name]
    serialized_shape = record.metadata.get("nmtk_flatten_input_shape")
    if isinstance(serialized_shape, str):
        try:
            return tuple(int(dimension) for dimension in serialized_shape.split(","))
        except ValueError:
            pass
    known_shapes = [(source, shapes[source]) for source in sources if source in shapes]
    if len(known_shapes) == 1:
        return known_shapes[0][1]
    if len(known_shapes) > 1:
        _raise_single(
            code="ambiguous_flatten_input_shape",
            message=f"Flatten node {record.name!r} has multiple shaped inputs.",
            line=record.line,
            hint="Connect exactly one upstream tensor-producing node to each Flatten node.",
        )
    _raise_single(
        code="missing_flatten_input_shape",
        message=f"Could not infer input shape for Flatten node {record.name!r}.",
        line=record.line,
        hint=(
            "Connect Flatten after an Input, Conv2d, pooling, or shape-preserving node "
            "so CNLStudio can infer the required NIR input_type."
        ),
    )
