"""Parameter resolution for the NIR-Native CNL compiler.

Extracted from :mod:`neurocnl.nir_cnl.compiler` (Stage 6 refactor). This
module owns the "kind"-dispatched value resolvers (``vector``, ``tensor``,
``int_tuple``, ``int_scalar``) described in the compiler's module
docstring, plus the diagnostic-construction helpers and shape validators
they share. :mod:`~neurocnl.nir_cnl.compiler` and
:mod:`~neurocnl.nir_cnl.node_factories` both import from here; the
compiler's public behaviour and diagnostics are unchanged by this move.
"""

from __future__ import annotations

from typing import Any, NoReturn

import numpy as np

from neurocnl.compile import CompileError, Diagnostic
from neurocnl.nir_cnl.grammar_tables import ParamSpec
from neurocnl.nir_cnl.ir_types import ArraySpec, ArrayValues, NIRNodeRecord

__all__ = [
    "_MISSING",
    "_SHAPE_DIM_MAX",
    "_SHAPE_DIM_MIN",
    "_diag",
    "_missing_param_error",
    "_raise_single",
    "_resolve_int_scalar",
    "_resolve_int_tuple",
    "_resolve_param",
    "_resolve_tensor",
    "_resolve_vector",
    "_scalar",
    "_validate_shape_dims",
    "_validate_shape_rank",
]


# Documented dimension range for shape literals (Requirement 4.3, 11.7).
_SHAPE_DIM_MIN: int = 1
_SHAPE_DIM_MAX: int = 4096


# Sentinel used by per-builder lookups to distinguish "user omitted this
# parameter" from "user passed ``None`` explicitly". The IR records
# never store ``None`` so the sentinel collision is safe.
_MISSING: Any = object()


# ---------------------------------------------------------------------------
# Diagnostic helpers
# ---------------------------------------------------------------------------


def _diag(
    code: str,
    message: str,
    *,
    line: int | None = None,
    raw: str | None = None,
    hint: str | None = None,
) -> Diagnostic:
    """Build a :class:`Diagnostic` tagged ``stage="materializer"``.

    Centralising the stage label here keeps the codebase honest about
    where each diagnostic was raised — the renderer uses ``"validator"``
    and the parser uses ``"parser"``.
    """
    return Diagnostic(
        stage="materializer",
        code=code,
        message=message,
        line=line,
        raw=raw,
        hint=hint,
    )


def _raise_single(
    code: str,
    message: str,
    *,
    line: int | None = None,
    hint: str | None = None,
) -> NoReturn:
    """Raise a :class:`CompileError` carrying exactly one diagnostic."""
    raise CompileError(message, [_diag(code, message, line=line, hint=hint)])


# ---------------------------------------------------------------------------
# Shape validation
# ---------------------------------------------------------------------------


def _validate_shape_rank(
    shape: tuple[int, ...],
    expected_rank: int,
    *,
    primitive: str,
    arg_name: str,
    line: int,
) -> None:
    """Raise ``shape_rank_mismatch`` when *shape* has the wrong rank."""
    if len(shape) != expected_rank:
        _raise_single(
            code="shape_rank_mismatch",
            message=(
                f"Parameter {arg_name!r} on {primitive!r} expects rank "
                f"{expected_rank}, got rank {len(shape)} (shape={shape})."
            ),
            line=line,
            hint=(
                f"Use a shape literal with exactly {expected_rank} dimension(s) for this parameter."
            ),
        )


def _validate_shape_dims(
    shape: tuple[int, ...],
    *,
    primitive: str,
    arg_name: str,
    line: int,
) -> None:
    """Raise ``invalid_shape`` when any dim is outside ``[1, 4096]``."""
    for dim in shape:
        if not (_SHAPE_DIM_MIN <= dim <= _SHAPE_DIM_MAX):
            _raise_single(
                code="invalid_shape",
                message=(
                    f"Shape {shape} for {arg_name!r} on {primitive!r} "
                    f"contains dimension {dim} outside the documented "
                    f"range [{_SHAPE_DIM_MIN}, {_SHAPE_DIM_MAX}]."
                ),
                line=line,
                hint=(
                    f"Each dimension must be a positive integer in "
                    f"[{_SHAPE_DIM_MIN}, {_SHAPE_DIM_MAX}]."
                ),
            )


# ---------------------------------------------------------------------------
# Per-kind value resolvers
# ---------------------------------------------------------------------------


def _resolve_vector(
    value: Any,
    *,
    primitive: str,
    arg_name: str,
    line: int,
) -> np.ndarray[Any, Any]:
    """Resolve a ``"vector"`` kind parameter to a ``float64`` ``ndarray``.

    Accepts:

    * :class:`ArraySpec` → ``numpy.zeros(shape, dtype=float)``;
    * :class:`ArrayValues` →
      ``numpy.asarray(values, dtype=float).reshape(shape)``;
    * Python ``int`` / ``float`` (scalar broadcast) →
      ``numpy.array([value], dtype=float)``.
    """
    if isinstance(value, ArraySpec):
        # The grammar table tags vectors as ``rank=1`` to match the
        # documented ``shape (N,)`` form, but several reference NIR
        # fixtures store these parameters as higher-rank arrays
        # (e.g. ``IF.r`` of shape ``(16, 16, 16)`` in
        # ``cnn_sinabs.nir``). The renderer round-trips the original
        # shape verbatim; the compiler accepts any rank ≥ 1 so the
        # round-trip preserves the source shape rather than rejecting
        # it on a strict rank check.
        if len(value.shape) < 1:
            _validate_shape_rank(
                value.shape,
                1,
                primitive=primitive,
                arg_name=arg_name,
                line=line,
            )
        _validate_shape_dims(
            value.shape, primitive=primitive, arg_name=arg_name, line=line
        )
        return np.zeros(value.shape, dtype=float)

    if isinstance(value, ArrayValues):
        # See note above on relaxed-rank acceptance.
        if len(value.shape) < 1:
            _validate_shape_rank(
                value.shape,
                1,
                primitive=primitive,
                arg_name=arg_name,
                line=line,
            )
        _validate_shape_dims(
            value.shape, primitive=primitive, arg_name=arg_name, line=line
        )
        flat = np.asarray(value.values, dtype=float)
        expected = int(np.prod(value.shape)) if value.shape else 1
        if flat.size != expected:
            _raise_single(
                code="invalid_value",
                message=(
                    f"Parameter {arg_name!r} on {primitive!r}: values "
                    f"list has {flat.size} elements but shape {value.shape} "
                    f"requires {expected}."
                ),
                line=line,
            )
        return flat.reshape(value.shape)

    # Bare scalar: parser emits ``int`` for pure integer literals and
    # ``float`` for anything carrying a decimal point or exponent.
    # ``bool`` is a subclass of ``int`` but is not a valid neuromorphic
    # parameter; reject it explicitly so an off-by-one cast cannot slip
    # through (Requirement 9.5 hint clarity).
    if isinstance(value, bool):
        _raise_single(
            code="invalid_value",
            message=(f"Parameter {arg_name!r} on {primitive!r} cannot be a boolean."),
            line=line,
        )
    if isinstance(value, int | float):
        return np.array([float(value)], dtype=float)

    _raise_single(
        code="invalid_value",
        message=(
            f"Cannot resolve value of type {type(value).__name__!s} for "
            f"vector parameter {arg_name!r} on {primitive!r}."
        ),
        line=line,
    )
    raise AssertionError("unreachable")  # pragma: no cover


def _resolve_tensor(
    value: Any,
    *,
    expected_rank: int,
    primitive: str,
    arg_name: str,
    line: int,
    record: NIRNodeRecord,
) -> np.ndarray[Any, Any]:
    """Resolve a ``"tensor"`` kind parameter to a ``float64`` ``ndarray``."""
    if isinstance(value, ArraySpec):
        _validate_shape_rank(
            value.shape,
            expected_rank,
            primitive=primitive,
            arg_name=arg_name,
            line=line,
        )
        _validate_shape_dims(
            value.shape, primitive=primitive, arg_name=arg_name, line=line
        )
        shape = value.shape

        # ── 2. Read and normalise weight_init (Requirements 1.1, 1.2, 5.1) ──
        raw_init = record.metadata.get("weight_init", "")
        weight_init = str(raw_init).strip().lower()

        # No init requested → backward-compatible zero-fill path preserved
        if not weight_init:
            return np.zeros(shape, dtype=float)

        # ── 3. Validate weight_init string (Requirements 2.6, 5.6, 6.1, 6.5) ──
        # This check MUST occur before any seed or rank validation (Requirement 6.5).
        if weight_init not in {"xavier", "kaiming"}:
            _raise_single(
                code="invalid_value",
                message=(
                    f"Unsupported weight_init value {raw_init!r} on node "
                    f"{record.name!r}. Accepted values are 'xavier' and "
                    f"'kaiming'."
                ),
                line=line,
                hint='Use weight_init equal to "xavier" or "kaiming".',
            )

        # ── 4. Validate and resolve seed (Requirements 4.7, 6.2, 6.3, 6.4) ──
        raw_seed = record.metadata.get("seed", 42)
        # Reject floats that are not exact integers (e.g. 1.5), negative values,
        # and any value that cannot be converted to int at all (e.g. "abc").
        # The check order is: type guard first, then numeric range.
        _seed_valid = False
        try:
            if isinstance(raw_seed, bool):
                # bool is a subclass of int in Python — reject it (not a valid seed)
                raise TypeError("bool")
            if isinstance(raw_seed, float):
                # float is not an integer type; reject even exact-integer floats
                # (e.g. 2.0) to match Requirement 4.7 which calls out "float" explicitly.
                raise TypeError("float")
            seed = int(raw_seed)
            if seed < 0:
                raise ValueError("negative")
            _seed_valid = True
        except (ValueError, TypeError):
            pass
        if not _seed_valid:
            _raise_single(
                code="invalid_value",
                message=(
                    f"Metadata 'seed' on node {record.name!r} must be a "
                    f"non-negative integer, got {raw_seed!r}."
                ),
                line=line,
                hint="Use an integer literal: annotated with metadata seed equal to 42.",
            )

        # ── 5. Rank guard for initialisation (Requirements 2.7, 3.6) ──────
        rank = len(shape)
        if rank < 2:
            _raise_single(
                code="invalid_value",
                message=(
                    f"weight_init={weight_init!r} on {primitive!r} "
                    f"parameter {arg_name!r} requires a tensor of rank >= 2, "
                    f"got rank {rank} (shape={shape})."
                ),
                line=line,
                hint="Provide a shape with at least 2 dimensions.",
            )

        # ── 6. Fan-in / fan-out derivation (Requirements 2.1, 2.2, 2.3, 3.1, 3.2, 3.3) ──
        if rank == 2:
            receptive_field_size = 1
        else:  # rank > 2 (convolutional)
            receptive_field_size = int(np.prod(shape[2:]))

        fan_in = shape[1] * receptive_field_size
        fan_out = shape[0] * receptive_field_size

        # ── 7. Guard against degenerate fan_in (Requirement 3.7) ─────────────
        if fan_in == 0:
            _raise_single(
                code="invalid_value",
                message=(
                    f"Computed fan_in=0 for {primitive!r} parameter "
                    f"{arg_name!r} (shape={shape}). Cannot compute "
                    f"{weight_init!r} bound."
                ),
                line=line,
                hint="Ensure all shape dimensions are >= 1.",
            )

        # ── 8. Compute distribution bound ────────────────────────────────────
        if weight_init == "xavier":
            if fan_in + fan_out == 0:
                _raise_single(
                    code="invalid_value",
                    message=(
                        f"Computed fan_in + fan_out = 0 for {primitive!r} "
                        f"parameter {arg_name!r}. Cannot compute Xavier bound."
                    ),
                    line=line,
                )
            limit = np.sqrt(6.0 / (fan_in + fan_out))
        else:  # kaiming
            limit = np.sqrt(3.0 / fan_in)

        # ── 9. Sample using isolated RNG (Requirements 7.1, 7.3, 4.1) ─────────
        rng = np.random.default_rng(seed=seed)
        return rng.uniform(-limit, limit, size=shape).astype(np.float64)

    if isinstance(value, ArrayValues):
        _validate_shape_rank(
            value.shape,
            expected_rank,
            primitive=primitive,
            arg_name=arg_name,
            line=line,
        )
        _validate_shape_dims(
            value.shape, primitive=primitive, arg_name=arg_name, line=line
        )
        flat = np.asarray(value.values, dtype=float)
        expected = int(np.prod(value.shape)) if value.shape else 1
        if flat.size != expected:
            _raise_single(
                code="invalid_value",
                message=(
                    f"Parameter {arg_name!r} on {primitive!r}: values "
                    f"list has {flat.size} elements but shape {value.shape} "
                    f"requires {expected}."
                ),
                line=line,
            )
        return flat.reshape(value.shape)

    _raise_single(
        code="invalid_value",
        message=(
            f"Tensor parameter {arg_name!r} on {primitive!r} requires a "
            f"shape (...) clause (and optionally a values (...) clause); "
            f"got {type(value).__name__!s}."
        ),
        line=line,
    )
    raise AssertionError("unreachable")  # pragma: no cover


def _resolve_int_tuple(
    value: Any,
    *,
    expected_rank: int,
    primitive: str,
    arg_name: str,
    line: int,
) -> tuple[int, ...]:
    """Resolve an ``"int_tuple"`` kind parameter to a plain ``tuple[int, ...]``."""
    if isinstance(value, ArraySpec | ArrayValues):
        _raise_single(
            code="shape_for_scalar",
            message=(
                f"Parameter {arg_name!r} on {primitive!r} expects an "
                f"integer tuple, not a shape declaration."
            ),
            line=line,
        )
    if isinstance(value, tuple):
        if len(value) != expected_rank:
            _raise_single(
                code="shape_rank_mismatch",
                message=(
                    f"Parameter {arg_name!r} on {primitive!r} expects "
                    f"a tuple of {expected_rank} integers, got "
                    f"{len(value)}."
                ),
                line=line,
            )
        return tuple(int(x) for x in value)

    _raise_single(
        code="invalid_value",
        message=(
            f"Parameter {arg_name!r} on {primitive!r} must be an integer "
            f"tuple; got {type(value).__name__!s}."
        ),
        line=line,
    )
    raise AssertionError("unreachable")  # pragma: no cover


def _resolve_int_scalar(
    value: Any,
    *,
    primitive: str,
    arg_name: str,
    line: int,
) -> int:
    """Resolve an ``"int_scalar"`` kind parameter to a Python ``int``.

    ``bool`` values (e.g. a ``True``/``False`` literal accidentally
    surviving from a metadata-string parser glitch) are coerced via
    ``int()`` rather than rejected, mirroring the implementation note
    in the spec.
    """
    if isinstance(value, ArraySpec | ArrayValues):
        _raise_single(
            code="shape_for_scalar",
            message=(
                f"Parameter {arg_name!r} on {primitive!r} expects a "
                f"single integer, not a shape declaration."
            ),
            line=line,
        )
    if isinstance(value, bool):
        return int(value)
    if isinstance(value, int):
        return value
    if isinstance(value, float) and float(value).is_integer():
        return int(value)
    _raise_single(
        code="invalid_value",
        message=(
            f"Parameter {arg_name!r} on {primitive!r} must be an integer; "
            f"got {type(value).__name__!s}."
        ),
        line=line,
    )
    raise AssertionError("unreachable")  # pragma: no cover


# ---------------------------------------------------------------------------
# Required-parameter helpers
# ---------------------------------------------------------------------------


def _missing_param_error(
    *,
    primitive: str,
    arg_name: str,
    spec: ParamSpec,
    line: int,
) -> CompileError:
    """Construct the ``CompileError`` for a missing required parameter.

    Per Requirements 2.10 and 11.6, the error code differs by parameter
    kind: an array-bearing parameter (``"vector"`` or ``"tensor"``)
    raises ``code="missing_shape"``; everything else raises
    ``code="missing_required_parameter"``.
    """
    if spec.kind in ("vector", "tensor"):
        code = "missing_shape"
        msg = (
            f"Primitive {primitive!r} requires parameter {arg_name!r} "
            f"({spec.phrase!r}) but no shape clause was provided."
        )
        hint = (
            f"Add a clause: '{spec.phrase} shape (d1, ..., dN)' or "
            f"'{spec.phrase} shape (...) and {spec.phrase} values (...)'."
        )
    else:
        code = "missing_required_parameter"
        msg = f"Primitive {primitive!r} requires parameter {arg_name!r} ({spec.phrase!r})."
        hint = f"Add a clause: '{spec.phrase} <value>'."
    return CompileError(msg, [_diag(code, msg, line=line, hint=hint)])


# ---------------------------------------------------------------------------
# Per-Primitive builder support
# ---------------------------------------------------------------------------


def _resolve_param(
    record: NIRNodeRecord,
    arg_name: str,
    spec: ParamSpec,
    *,
    expected_rank: int | None = None,
) -> Any:
    """Look up *arg_name* on *record* and resolve it per *spec.kind*.

    Raises :class:`CompileError` when the parameter is missing and has
    no default, or when the recorded value is incompatible with the
    declared kind. The ``expected_rank`` override lets the
    Conv1d/Conv2d builders specialise the rank constraint for tensor
    weights without growing the grammar table.
    """
    primitive = record.primitive
    line = record.line
    raw = record.params.get(arg_name, _MISSING)

    if raw is _MISSING:
        if spec.has_default:
            return _MISSING
        raise _missing_param_error(
            primitive=primitive, arg_name=arg_name, spec=spec, line=line
        )

    kind = spec.kind
    if kind == "vector":
        return _resolve_vector(raw, primitive=primitive, arg_name=arg_name, line=line)
    if kind == "tensor":
        rank = expected_rank if expected_rank is not None else (spec.rank or 2)
        return _resolve_tensor(
            raw,
            expected_rank=rank,
            primitive=primitive,
            arg_name=arg_name,
            line=line,
            record=record,
        )
    if kind == "int_tuple":
        rank = expected_rank if expected_rank is not None else (spec.rank or 1)
        return _resolve_int_tuple(
            raw,
            expected_rank=rank,
            primitive=primitive,
            arg_name=arg_name,
            line=line,
        )
    if kind == "int_scalar":
        return _resolve_int_scalar(
            raw, primitive=primitive, arg_name=arg_name, line=line
        )
    if kind == "scalar":
        # Reserved kind; treat exactly like a length-1 vector for now.
        return _resolve_vector(raw, primitive=primitive, arg_name=arg_name, line=line)

    # Unreachable in practice — the grammar table only emits the five
    # documented kinds — but defended for forward-compatibility.
    _raise_single(
        code="invalid_value",
        message=(
            f"Internal: unhandled ParamSpec.kind {kind!r} for {primitive}.{arg_name}."
        ),
        line=line,
    )
    raise AssertionError("unreachable")  # pragma: no cover


def _scalar(value: Any) -> float:
    """Unwrap a resolved ``"vector"``-kind value to a plain Python float.

    Every ``_resolve_param`` "vector" result is an ``ndarray`` (nir.* neuron
    fields are per-population arrays) — but ``Synaptic``/``RSynaptic``/
    ``Leaky``/``RLeaky`` (``neurocnl.runtime.cnl_nodes``) declare
    ``alpha``/``beta``/``threshold`` as plain ``float``, which downstream
    codegen (``notebook.py``) formats with ``f"{node.alpha:.6f}"`` — that
    fails on an ndarray. Scalar CNL clauses always resolve to a length-1
    array (see ``_emit_param_clauses``'s "vector" scalar-broadcast case),
    so taking the first element is exact, not an approximation.
    """
    return float(np.asarray(value).reshape(-1)[0])
