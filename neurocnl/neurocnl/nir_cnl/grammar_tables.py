"""Grammar tables for the NIR-native Controlled Natural Language.

This module is a *pure-data* foundation for the NIR-native CNL pipeline.
It defines every table that the renderer, parser, and compiler share so
that there is exactly one source of truth for:

* which English noun phrase identifies which NIR Primitive,
* which English parameter phrase identifies which ``nir.*`` constructor
  argument,
* which English keywords drive the grammar (case-insensitively),
* which token forms are *forbidden* — either Biological_Grammar keywords
  inherited from the legacy reflex-arc CNL or Structured_DSL_Tokens
  inherited from the legacy structured CNL.

Module guarantees
-----------------
This module **only** imports from the Python standard library
(``dataclasses``, ``re``, ``typing``). It never imports ``numpy`` or
``nir``, which keeps it loadable in minimal environments and means the
renderer and parser can pull these tables in at module-import time
without dragging the heavyweight neuromorphic-graph runtime along.

The tables are immutable in spirit (we use plain ``dict`` literals and
``frozenset`` so type-checkers stay happy with the documented public
types from the design document) and the spec for this feature treats
every entry as part of the contract surface.

Tables exposed
--------------
``primitive_phrases``
    Maps each Primitive class name (``"LIF"``, ``"Conv2d"``, …) to its
    canonical English noun phrase as written by the renderer
    (Requirement 1.2, 2.1).

``noun_phrase_to_primitive``
    Inverse of ``primitive_phrases``, keyed by the *lowercased* English
    noun phrase so the parser can perform a case-insensitive lookup as
    ``noun_phrase_to_primitive[phrase.lower()]`` (Requirement 1.10).

``parameter_phrases``
    Two-level table: Primitive class name → constructor-argument name →
    :class:`ParamSpec`. Every entry mirrors a row of the design
    document's per-Primitive parameter mapping table and carries the
    canonical English phrase, the value kind, the rank (or ``None`` for
    scalars), and whether the underlying ``nir.*`` constructor supplies
    a default value for that argument (Requirement 1.5, 2.7, 11.6).

``keyword_set``
    The closed set of case-insensitive grammar keywords drawn from
    Requirement 1.10:
    ``{Define, Create, named, with, and, Connect, to, network,
    annotated, metadata, equal, shape}``. Stored verbatim as a
    ``frozenset[str]`` using the canonical surface casing the renderer
    emits (``Define``, ``Create``, ``Connect`` capitalised; the rest
    lowercase). Case-insensitive matching is the parser's job, which
    typically lowercases tokens before comparing against
    ``{k.lower() for k in keyword_set}``.

``forbidden_biological_keywords``
    The seven Biological_Grammar tokens whose presence outside a
    double-quoted string literal indicates the legacy reflex-arc CNL
    (Requirement 8.1).

``structured_dsl_token_patterns``
    Compiled regular expressions for the Structured_DSL_Token forms
    listed in Requirement 1.8 / 8.2. The patterns intentionally only
    cover the forms that can be matched *cleanly* without false
    positives; see the per-pattern comments for the precise scope.

See ``.kiro/specs/nir-native-cnl/design.md`` (sections "Data Models" and
"English-to-Primitive Mapping Table") for the authoritative tables that
this module mirrors.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Literal

__all__ = [
    "ParamSpec",
    "ParamKind",
    "primitive_phrases",
    "noun_phrase_to_primitive",
    "parameter_phrases",
    "keyword_set",
    "forbidden_biological_keywords",
    "structured_dsl_token_patterns",
    "COMPACT_METADATA_SKIP",
    "optimizer_id_to_phrase",
    "optimizer_phrase_to_id",
    "training_strategy_id_to_phrase",
    "training_strategy_phrase_to_id",
    "loss_function_id_to_phrase",
    "loss_function_phrase_to_id",
    "export_target_id_to_phrase",
    "export_target_phrase_to_id",
]


# ---------------------------------------------------------------------------
# Parameter specification record
# ---------------------------------------------------------------------------


ParamKind = Literal["scalar", "vector", "tensor", "int_tuple", "int_scalar"]
"""Tagged enumeration of parameter value kinds the grammar recognises.

* ``"scalar"`` — a single numeric literal; always materialised as
  ``float``.
* ``"vector"`` — a 1-D array. The grammar accepts both an explicit
  numeric scalar (broadcast at compile time) and an explicit value list
  via the ``shape (N,) and ... values (...)`` form. See Requirement 2.5
  for the trailing-comma convention.
* ``"tensor"`` — an N-D array (rank ≥ 2) such as a Linear weight matrix
  or a Conv2d weight kernel. The grammar accepts an optional
  ``values (...)`` clause, but the renderer emits shape-only tensor
  clauses to keep CNL compact.
* ``"int_tuple"`` — a parenthesised tuple of integers, used for
  structural parameters (``stride``, ``padding``, ``dilation``,
  ``input_shape``, ``kernel_size``).
* ``"int_scalar"`` — a single integer literal (``groups``,
  ``start_dim``, ``end_dim``).
"""


@dataclass(frozen=True, slots=True)
class ParamSpec:
    """Description of one parameter clause in the parameter mapping table.

    Attributes
    ----------
    phrase:
        Canonical lowercase English phrase that maps to this parameter,
        as it appears in the design document's parameter mapping table
        (e.g. ``"time constant"``, ``"weight matrix"``,
        ``"firing threshold"``).
    kind:
        Value kind taken from :data:`ParamKind`. The renderer and
        compiler dispatch on this field.
    rank:
        Expected rank of the array for ``"vector"``, ``"tensor"``, and
        ``"int_tuple"`` kinds. ``None`` for ``"scalar"`` and
        ``"int_scalar"`` because those carry no shape. The compiler
        validates ``ArraySpec`` / ``ArrayValues`` records against this
        rank (Requirement 11.8).
    has_default:
        ``True`` when the underlying ``nir.*`` constructor supplies a
        default value for this argument, ``False`` otherwise. The
        compiler uses this to distinguish missing-but-allowed (omit and
        let the constructor default fire — Requirement 2.7) from
        missing-and-required (raise ``CompileError`` with
        ``code="missing_required_parameter"`` — Requirement 2.10).
    """

    phrase: str
    kind: ParamKind
    rank: int | None
    has_default: bool


# ---------------------------------------------------------------------------
# Primitive ↔ noun phrase mapping (Requirement 1.2, 2.1)
# ---------------------------------------------------------------------------


# One canonical English noun phrase per Primitive. Phrases are stored
# lowercase; the renderer emits them as-is and the parser lowercases the
# user's noun phrase before lookup (Requirement 1.10). The first 18
# entries match the design document's English-to-Primitive mapping table
# verbatim, with no duplicate values; ``Synaptic``/``RSynaptic``/
# ``Leaky``/``RLeaky`` are CNL-Studio-internal snnTorch neuron
# extensions added later (see comment above those entries).
primitive_phrases: dict[str, str] = {
    "Input": "input port",
    "Output": "output port",
    "IF": "IF neuron",
    "LIF": "LIF neuron",
    "LI": "LI neuron",
    "CubaLIF": "CubaLIF neuron",
    "CubaLI": "CubaLI neuron",
    "I": "I neuron",
    "Linear": "linear transformation",
    "Affine": "affine transformation",
    "Scale": "scale transformation",
    "Conv1d": "1D convolution layer",
    "Conv2d": "2D convolution layer",
    "AvgPool2d": "2D average pooling layer",
    "SumPool2d": "2D sum pooling layer",
    "Flatten": "flatten layer",
    "Delay": "delay element",
    "Threshold": "threshold element",
    # CNL-Studio's own snnTorch-flavored neuron extensions (not part of
    # the upstream ``nir`` primitive set) — ``notebook.py`` codegen has
    # always supported these; they were simply never added here, so a
    # canvas-built network using them silently lost these nodes (and
    # every edge touching them) on every CNL render, producing a
    # disconnected graph on re-parse. See
    # ``current tasks/2026-07-15/cnl-renderer-synaptic-gap-fix.md``.
    "Synaptic": "Synaptic neuron",
    "RSynaptic": "RSynaptic neuron",
    "Leaky": "Leaky neuron",
    "RLeaky": "RLeaky neuron",
}


# Inverse table for the parser. Keys are *lowercased* so the parser can
# do a single ``noun_phrase_to_primitive[phrase.lower()]`` lookup
# without per-call normalisation (Requirement 1.10). Values are the
# Primitive class names exactly as they appear in ``primitive_phrases``.
noun_phrase_to_primitive: dict[str, str] = {
    phrase.lower(): primitive for primitive, phrase in primitive_phrases.items()
}


# ---------------------------------------------------------------------------
# Per-Primitive parameter mapping (Requirement 1.5, 2.1, 2.7, 11.6)
# ---------------------------------------------------------------------------


# Each inner dict's keys are the ``nir.*`` constructor-argument names
# exactly as they appear in the upstream ``nir`` package; each value is
# the :class:`ParamSpec` that describes the canonical English phrase,
# the value kind, the rank (or ``None`` for scalars), and whether the
# constructor supplies a default for that argument.
#
# The ``has_default`` flags reflect the actual upstream ``nir`` library
# defaults. Most structural and physical parameters are required; only
# ``CubaLIF.w_in`` and ``CubaLI.w_in`` (default ``1.0``), ``Flatten``'s
# ``start_dim`` (default ``1``) and ``end_dim`` (default ``-1``) carry
# real defaults today. The compiler consults this flag in its
# missing-parameter validation pass (Requirement 2.7, 2.10).
#
# Vector parameters such as ``LIF.tau`` accept either an explicit numeric
# scalar (which the compiler broadcasts to the documented shape) or a
# value list via the ``shape (N,) and ... values (...)`` form. They are
# tagged ``kind="vector"`` here; the renderer always emits the
# value-list form for round-trip identity (Requirement 5.13), while the
# compiler accepts a bare scalar as a convenience for hand-authored CNL.
parameter_phrases: dict[str, dict[str, ParamSpec]] = {
    "Input": {
        # ``input_type`` is a 1-D shape descriptor expressed as the
        # ``shape (...)`` literal in CNL (Requirement 1.5). The parser
        # produces a tuple of ints; the compiler converts to the
        # ``numpy.ndarray`` shape that ``nir.Input`` expects.
        "input_type": ParamSpec(phrase="shape", kind="int_tuple", rank=1, has_default=False),
    },
    "Output": {
        "output_type": ParamSpec(phrase="shape", kind="int_tuple", rank=1, has_default=False),
    },
    "IF": {
        # Scalar-or-vector parameters: see module docstring on
        # broadcasting. Tagged ``"vector"`` so the renderer round-trips
        # an explicit value list (Requirement 5.13).
        "r": ParamSpec(phrase="resistance", kind="vector", rank=1, has_default=False),
        "v_threshold": ParamSpec(
            phrase="firing threshold", kind="vector", rank=1, has_default=False
        ),
    },
    "LIF": {
        # All four are scalar-or-vector; renderer emits explicit value
        # lists for round-trip identity, compiler accepts bare scalars.
        "tau": ParamSpec(phrase="time constant", kind="vector", rank=1, has_default=False),
        "r": ParamSpec(phrase="resistance", kind="vector", rank=1, has_default=False),
        "v_leak": ParamSpec(phrase="leak voltage", kind="vector", rank=1, has_default=False),
        "v_threshold": ParamSpec(
            phrase="firing threshold", kind="vector", rank=1, has_default=False
        ),
    },
    "LI": {
        "tau": ParamSpec(phrase="time constant", kind="vector", rank=1, has_default=False),
        "r": ParamSpec(phrase="resistance", kind="vector", rank=1, has_default=False),
        "v_leak": ParamSpec(phrase="leak voltage", kind="vector", rank=1, has_default=False),
    },
    "CubaLIF": {
        "tau_syn": ParamSpec(
            phrase="synaptic time constant", kind="vector", rank=1, has_default=False
        ),
        "tau_mem": ParamSpec(
            phrase="membrane time constant", kind="vector", rank=1, has_default=False
        ),
        "r": ParamSpec(phrase="resistance", kind="vector", rank=1, has_default=False),
        "v_leak": ParamSpec(phrase="leak voltage", kind="vector", rank=1, has_default=False),
        "v_threshold": ParamSpec(
            phrase="firing threshold", kind="vector", rank=1, has_default=False
        ),
        # ``w_in`` defaults to ``1.0`` in the upstream ``nir`` library —
        # the only non-structural default we honour for CubaLIF.
        "w_in": ParamSpec(phrase="input weight", kind="vector", rank=1, has_default=True),
    },
    "CubaLI": {
        "tau_syn": ParamSpec(
            phrase="synaptic time constant", kind="vector", rank=1, has_default=False
        ),
        "tau_mem": ParamSpec(
            phrase="membrane time constant", kind="vector", rank=1, has_default=False
        ),
        "r": ParamSpec(phrase="resistance", kind="vector", rank=1, has_default=False),
        "v_leak": ParamSpec(phrase="leak voltage", kind="vector", rank=1, has_default=False),
        # Same default story as CubaLIF.w_in.
        "w_in": ParamSpec(phrase="input weight", kind="vector", rank=1, has_default=True),
    },
    "I": {
        "r": ParamSpec(phrase="resistance", kind="vector", rank=1, has_default=False),
    },
    "Linear": {
        # Rank-2 weight matrix. The renderer emits only
        # ``weight matrix shape (...)``; explicit values remain optional
        # parser/compiler input for hand-authored CNL.
        "weight": ParamSpec(phrase="weight matrix", kind="tensor", rank=2, has_default=False),
    },
    "Affine": {
        "weight": ParamSpec(phrase="weight matrix", kind="tensor", rank=2, has_default=False),
        # ``Affine.bias`` is required by the upstream constructor but
        # the compiler auto-derives ``numpy.zeros((out_channels,))``
        # when the user supplies a weight clause and omits the bias
        # clause (Requirement 11.4). ``has_default=False`` here keeps
        # the constructor-truth honest; the auto-derivation is a
        # separate compiler convenience.
        "bias": ParamSpec(phrase="bias vector", kind="vector", rank=1, has_default=False),
    },
    "Scale": {
        "scale": ParamSpec(phrase="scale factor", kind="vector", rank=1, has_default=False),
    },
    "Conv1d": {
        # Rank-3 weight kernel: (out_channels, in_channels/groups, kT).
        "weight": ParamSpec(phrase="weight kernel", kind="tensor", rank=3, has_default=False),
        "bias": ParamSpec(phrase="bias vector", kind="vector", rank=1, has_default=False),
        "stride": ParamSpec(phrase="stride", kind="int_tuple", rank=1, has_default=False),
        "padding": ParamSpec(phrase="padding", kind="int_tuple", rank=1, has_default=False),
        "dilation": ParamSpec(phrase="dilation", kind="int_tuple", rank=1, has_default=False),
        "groups": ParamSpec(phrase="groups", kind="int_scalar", rank=None, has_default=False),
        # ``input_shape`` for Conv1d is a single integer length (the L
        # dimension of (C, L) input). Tagged ``int_scalar``.
        "input_shape": ParamSpec(
            phrase="input length", kind="int_scalar", rank=None, has_default=False
        ),
    },
    "Conv2d": {
        # Rank-4 weight kernel: (out_channels, in_channels/groups, kH, kW).
        "weight": ParamSpec(phrase="weight kernel", kind="tensor", rank=4, has_default=False),
        # See Affine.bias above on auto-derivation for Conv2d
        # (Requirement 11.3, 11.4).
        "bias": ParamSpec(phrase="bias vector", kind="vector", rank=1, has_default=False),
        "stride": ParamSpec(phrase="stride", kind="int_tuple", rank=2, has_default=False),
        "padding": ParamSpec(phrase="padding", kind="int_tuple", rank=2, has_default=False),
        "dilation": ParamSpec(phrase="dilation", kind="int_tuple", rank=2, has_default=False),
        "groups": ParamSpec(phrase="groups", kind="int_scalar", rank=None, has_default=False),
        "input_shape": ParamSpec(
            phrase="input height and width", kind="int_tuple", rank=2, has_default=False
        ),
    },
    "AvgPool2d": {
        "kernel_size": ParamSpec(phrase="kernel size", kind="int_tuple", rank=2, has_default=False),
        "stride": ParamSpec(phrase="stride", kind="int_tuple", rank=2, has_default=False),
        "padding": ParamSpec(phrase="padding", kind="int_tuple", rank=2, has_default=False),
    },
    "SumPool2d": {
        "kernel_size": ParamSpec(phrase="kernel size", kind="int_tuple", rank=2, has_default=False),
        "stride": ParamSpec(phrase="stride", kind="int_tuple", rank=2, has_default=False),
        "padding": ParamSpec(phrase="padding", kind="int_tuple", rank=2, has_default=False),
    },
    "Flatten": {
        # Both ``start_dim`` and ``end_dim`` carry real defaults in the
        # upstream ``nir.Flatten`` constructor (1 and -1).
        "start_dim": ParamSpec(
            phrase="start dimension", kind="int_scalar", rank=None, has_default=True
        ),
        "end_dim": ParamSpec(
            phrase="end dimension", kind="int_scalar", rank=None, has_default=True
        ),
    },
    "Delay": {
        "delay": ParamSpec(phrase="delay value", kind="vector", rank=1, has_default=False),
    },
    "Threshold": {
        "threshold": ParamSpec(phrase="threshold value", kind="vector", rank=1, has_default=False),
    },
    # ``Synaptic``/``RSynaptic``/``Leaky``/``RLeaky`` (see primitive_phrases
    # above): only the numeric fields that are always concretely-valued
    # are exposed here. ``reset_mechanism`` (str) and ``use_bias``/
    # ``recurrent_weight`` (RSynaptic/RLeaky-only, and ``None``-able —
    # unlike every field above, which is never ``None`` on a real node)
    # are deliberately NOT round-tripped through CNL text yet — no
    # ParamKind for a string enum or an optional/nullable tensor exists
    # today, and every canvas-built network seen so far leaves these at
    # their dataclass defaults (``"subtract"``, ``False``, ``None``), so
    # omitting them here just means the compiler always reconstructs
    # those three at their defaults rather than silently misrepresenting
    # them. Revisit if a workspace is found that actually customises
    # them.
    "Synaptic": {
        "n_neurons": ParamSpec(
            phrase="neuron count", kind="int_scalar", rank=None, has_default=False
        ),
        "alpha": ParamSpec(phrase="synaptic decay", kind="vector", rank=1, has_default=False),
        "beta": ParamSpec(phrase="membrane decay", kind="vector", rank=1, has_default=False),
        "threshold": ParamSpec(phrase="firing threshold", kind="vector", rank=1, has_default=False),
    },
    "RSynaptic": {
        "n_neurons": ParamSpec(
            phrase="neuron count", kind="int_scalar", rank=None, has_default=False
        ),
        "alpha": ParamSpec(phrase="synaptic decay", kind="vector", rank=1, has_default=False),
        "beta": ParamSpec(phrase="membrane decay", kind="vector", rank=1, has_default=False),
        "threshold": ParamSpec(phrase="firing threshold", kind="vector", rank=1, has_default=False),
    },
    "Leaky": {
        "n_neurons": ParamSpec(
            phrase="neuron count", kind="int_scalar", rank=None, has_default=False
        ),
        "beta": ParamSpec(phrase="membrane decay", kind="vector", rank=1, has_default=False),
        "threshold": ParamSpec(phrase="firing threshold", kind="vector", rank=1, has_default=False),
    },
    "RLeaky": {
        "n_neurons": ParamSpec(
            phrase="neuron count", kind="int_scalar", rank=None, has_default=False
        ),
        "beta": ParamSpec(phrase="membrane decay", kind="vector", rank=1, has_default=False),
        "threshold": ParamSpec(phrase="firing threshold", kind="vector", rank=1, has_default=False),
    },
}


# ---------------------------------------------------------------------------
# Keyword set (Requirement 1.10)
# ---------------------------------------------------------------------------


# The closed set of case-insensitive grammar keywords, stored with the
# canonical surface casing the renderer emits (``Define``, ``Create``,
# ``Connect`` capitalised; the rest lowercase). Case-insensitive
# matching is the parser's job — callers typically build a
# ``{k.lower() for k in keyword_set}`` lookup once and check
# ``token.lower() in lowered`` to decide whether a token participates in
# the grammar's connective scaffold or is part of an identifier or
# parameter phrase.
#
# Note: ``"MUST NOT"`` from the legacy biological grammar is *not* a
# keyword here — that token belongs to ``forbidden_biological_keywords``
# below and is rejected by the parser, not consumed.
keyword_set: frozenset[str] = frozenset(
    {
        "Define",
        "Create",
        "named",
        "with",
        "and",
        "Connect",
        "to",
        "network",
        "annotated",
        "metadata",
        "equal",
        "shape",
        "Train",
        "Evaluate",
        "Export",
        "the",
        "for",
        "epochs",
        "learning",
        "rate",
        "batch",
        "size",
        "optimizer",
        "training",
        "strategy",
        "loss",
        "metrics",
        "trained",
        "script",
    }
)


# ---------------------------------------------------------------------------
# Forbidden biological grammar tokens (Requirement 8.1)
# ---------------------------------------------------------------------------


# Seven Biological_Grammar keywords whose presence outside a double-quoted
# string literal triggers the legacy-grammar denylist
# (Requirement 8.1, 8.4). Stored case-sensitively because the source
# tokens are mixed-case (``MUST``, ``MUST NOT``) and the legacy grammar
# itself was case-sensitive on these keywords.
#
# ``"MUST NOT"`` is a multi-word token; the validator must look for the
# exact two-word sequence ``MUST NOT`` before falling back to the
# single-word ``MUST`` match so the more-specific token wins.
forbidden_biological_keywords: frozenset[str] = frozenset(
    {
        "sensory",
        "motor",
        "MUST",
        "MUST NOT",
        "threshold_firing",
        "refractory_period",
        "STDP",
    }
)


# ---------------------------------------------------------------------------
# Structured DSL token patterns (Requirement 1.8, 8.2)
# ---------------------------------------------------------------------------


# The Primitive class names that can appear adjacent to a quoted
# identifier in the legacy structured grammar. Used inside the first
# regex pattern below to bound the false-positive surface — only a
# Primitive keyword followed by a quoted id is suspicious; an arbitrary
# identifier next to a quoted string is not.
_PRIMITIVE_KEYWORDS_RE = "|".join(re.escape(name) for name in primitive_phrases.keys())


# Compiled regex patterns for each Structured_DSL_Token form. Each
# pattern is intentionally narrow so the legacy-token validator does
# not flag legitimate natural-language CNL.
#
# The validator runs these patterns line-by-line on the *non-comment,
# non-string-literal* portion of the source — the responsibility for
# stripping ``#`` lines and double-quoted segments lives in
# ``nir_cnl/validator.py``.
structured_dsl_token_patterns: list[re.Pattern[str]] = [
    # (a) Primitive keyword followed by a double-quoted identifier
    #     (e.g. ``LIF "lif1"``) — Requirement 1.8 case (a) and 8.2 case (a).
    re.compile(rf"\b(?:{_PRIMITIVE_KEYWORDS_RE})\s+\"[^\"]+\""),
    # (b) Quoted-id arrow quoted-id, with ASCII or Unicode arrow forms
    #     (``->``, ``→``, ``=>``) between two double-quoted identifiers
    #     — Requirement 1.8 case (b) and 8.2 case (b).
    re.compile(r"\"[^\"]+\"\s*(?:->|→|=>)\s*\"[^\"]+\""),
    # (c) Bare-identifier arrow bare-identifier (``foo -> bar``) — covers
    #     the common case where the legacy grammar wrote arrows between
    #     unquoted identifiers as well.
    re.compile(r"\b[A-Za-z_][A-Za-z0-9_]*\s*(?:->|→|=>)\s*[A-Za-z_][A-Za-z0-9_]*\b"),
    # Note on the bare-pair form (``tau 0.01, r 1.0``): the legacy
    # structured DSL always prefixed a bare-pair clause with a Primitive
    # keyword followed by a quoted identifier (``LIF "lif1" tau 0.01, r
    # 1.0``), which pattern (a) above already catches. A standalone regex
    # for the bare-pair form is intentionally not included because the
    # canonical natural-language CNL routinely emits ``time constant
    # 0.02, resistance 1.0`` and any cleaning of the bare-pair regex
    # against natural-language phrases would be brittle — the bare-pair
    # form is detected indirectly via the parser's unknown-parameter
    # check at sentence dispatch time, not at the legacy-token gate.
]


# ---------------------------------------------------------------------------
# Pipeline (Train / Evaluate / Export) closed-vocabulary tables
# ---------------------------------------------------------------------------


# Mirrors the frontend's ``PipelineOptimizer`` enum (pipeline_config.dart)
# 1:1 so CNL phrases map onto backend ids the UI can already produce.
# Keys are the canonical backend id (as used by ``PipelineConfigPayload
# .optimizer``); values are the English surface phrase the renderer
# emits after the ``<phrase> optimizer`` clause form.
optimizer_id_to_phrase: dict[str, str] = {
    "Adam": "adam",
    "SGD": "sgd",
    "AdamW": "adamw",
    "RMSprop": "rmsprop",
}

# Mirrors the frontend's ``TrainingStrategy`` enum.
training_strategy_id_to_phrase: dict[str, str] = {
    "surrogate_gradient": "surrogate gradient",
    "bptt": "bptt",
    "rate_coding": "rate coding",
}

# Mirrors the frontend's ``LossFunction`` enum.
loss_function_id_to_phrase: dict[str, str] = {
    "mse_count": "mse count",
    "cross_entropy": "cross entropy",
    "membrane_potential": "membrane potential",
}

# The only two ``PipelineConfigPayload`` boolean export fields the
# grammar addresses. Keys are the ``PipelineConfigPayload`` field name.
export_target_id_to_phrase: dict[str, str] = {
    "export_nir": "NIR",
    "generate_py_download": "a Python script",
}

# Inverse lookup tables for the parser, keyed by the *lowercased*
# English phrase — mirrors the ``noun_phrase_to_primitive`` convention.
optimizer_phrase_to_id: dict[str, str] = {
    phrase.lower(): backend_id for backend_id, phrase in optimizer_id_to_phrase.items()
}
training_strategy_phrase_to_id: dict[str, str] = {
    phrase.lower(): backend_id for backend_id, phrase in training_strategy_id_to_phrase.items()
}
loss_function_phrase_to_id: dict[str, str] = {
    phrase.lower(): backend_id for backend_id, phrase in loss_function_id_to_phrase.items()
}
export_target_phrase_to_id: dict[str, str] = {
    phrase.lower(): field_name for field_name, phrase in export_target_id_to_phrase.items()
}


# ---------------------------------------------------------------------------
# Compact-render metadata skip set
# ---------------------------------------------------------------------------


# Metadata keys that the renderer omits from the compact output because
# they carry canvas layout data rather than model semantics.
COMPACT_METADATA_SKIP: frozenset[str] = frozenset(
    {
        "canvas_position",
        "canvas_component_id",
        "canvas_label",
        "display_label",
        "label",
        "category",
    }
)
